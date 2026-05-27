/**
 * EncryptedChannel — 端到端加密通道
 *
 * 四态状态机: connecting → handshaking → open → closed
 *               ↑                              │
 *               └────────── re-hello ──────────┘
 *
 * - control(type, payload): 发送明文 text frame（不受加密状态影响）
 * - send(data): 加密后发送 binary frame（需 open 状态）
 * - 控制消息: heartbeat, e2ee_hello, e2ee_ready, server_info
 */

import crypto from 'node:crypto';

// ── Types ──────────────────────────────────────────────────────────

export interface EncryptedChannelOptions {
  role: 'host' | 'client';
  /** Host 侧需要 hostIdentity 来签名/验证 */
  hostIdentity?: {
    hostId: string;
    ed25519PrivateKeyHex?: string;
    ed25519PublicKeyHex?: string;
    privateKeyHex?: string;
    publicKeyHex?: string;
  };
  /** Client 侧需要已知的 Host Ed25519 公钥 */
  hostEd25519PublicKeyHex?: string;
  /** Client 侧需要自己的 clientId 和 Ed25519 密钥 */
  clientId?: string;
  clientEd25519PrivateKeyHex?: string;
  clientEd25519PublicKeyHex?: string;
  /** WS 连接超时（ms） */
  connectTimeoutMs?: number;
  /** 握手超时（ms） */
  handshakeTimeoutMs?: number;
  /** 协议版本 */
  protocolVersion?: number;
}

export interface EncryptedChannelEvents {
  oncontrol?: (type: string, payload: Record<string, unknown>) => void;
  onmessage?: (data: string | ArrayBuffer) => void;
  onopen?: () => void;
  onclose?: (code: number, reason: string) => void;
  onerror?: (error: Error) => void;
}

/** 传输层接口（适配 ws.WebSocket / webSocket.WebSocket / relay adapter） */
export interface Transport {
  on(event: 'message', listener: (data: string | Buffer) => void): void;
  on(event: 'close', listener: () => void): void;
  on(event: 'error', listener: (err: Error) => void): void;
  send(data: string | Buffer): void;
  close(): void;
  readyState?: number;
}

type ChannelState = 'connecting' | 'handshaking' | 'open' | 'closed';

interface PendingFrame {
  data: string | ArrayBuffer;
  isControl: boolean;
}

// ── Constants ──────────────────────────────────────────────────────

const MAX_PENDING = 200;
const DEFAULT_CONNECT_TIMEOUT_MS = 10_000;
const DEFAULT_HANDSHAKE_TIMEOUT_MS = 15_000;
const CURRENT_PROTOCOL_VERSION = 1;
const MIN_PROTOCOL_VERSION = 1;

// ── Handshake Rate Limiting (Phase 2b) ─────────────────────────────
// Per-source sliding window: max 5 handshake attempts per 1 second
const MAX_HANDSHAKES_PER_SECOND = 5;
const HANDSHAKE_RATE_WINDOW_MS = 1000;
const handshakeAttempts: number[] = [];

function checkHandshakeRateLimit(): boolean {
  const now = Date.now();
  // Prune entries older than the window
  while (handshakeAttempts.length > 0 && handshakeAttempts[0] < now - HANDSHAKE_RATE_WINDOW_MS) {
    handshakeAttempts.shift();
  }
  if (handshakeAttempts.length >= MAX_HANDSHAKES_PER_SECOND) {
    return false;
  }
  handshakeAttempts.push(now);
  return true;
}

// ── EncryptedChannel ───────────────────────────────────────────────

export class EncryptedChannel {
  private state: ChannelState = 'connecting';
  private transport: Transport | null = null;
  private options: Required<EncryptedChannelOptions>;
  private events: EncryptedChannelEvents = {};
  private pendingQueue: PendingFrame[] = [];
  private connectTimer: ReturnType<typeof setTimeout> | null = null;
  private handshakeTimer: ReturnType<typeof setTimeout> | null = null;
  private seqNum: number = 0;
  private lastRemoteSeq: number = -1;
  private aesKey: Buffer | null = null;

  // Ephemeral X25519 keypair for PFS
  private ephKeyPair: { publicKey: Buffer; privateKey: Buffer } | null = null;
  private peerEphemeralKeyHex: string = '';

  constructor(opts: EncryptedChannelOptions, events?: EncryptedChannelEvents) {
    this.options = {
      role: opts.role,
      hostIdentity: opts.hostIdentity,
      hostEd25519PublicKeyHex: opts.hostEd25519PublicKeyHex ?? '',
      clientId: opts.clientId ?? '',
      clientEd25519PrivateKeyHex: opts.clientEd25519PrivateKeyHex ?? '',
      clientEd25519PublicKeyHex: opts.clientEd25519PublicKeyHex ?? '',
      connectTimeoutMs: opts.connectTimeoutMs ?? DEFAULT_CONNECT_TIMEOUT_MS,
      handshakeTimeoutMs: opts.handshakeTimeoutMs ?? DEFAULT_HANDSHAKE_TIMEOUT_MS,
      protocolVersion: opts.protocolVersion ?? CURRENT_PROTOCOL_VERSION,
    } as Required<EncryptedChannelOptions>;
    if (events) this.events = events;
    this.startConnectTimer();
  }

  // ── Public API ───────────────────────────────────────────────────

  /** 绑定传输层（transport open 后调用） */
  attachTransport(transport: Transport): void {
    this.transport = transport;

    transport.on('message', (data: string | Buffer) => {
      const raw = typeof data === 'string' ? data : data.toString('utf-8');
      // 区分 text frame(控制) vs binary frame(加密)
      if (typeof data === 'string' || !(data instanceof Buffer)) {
        // text frame → 控制消息
        this.handleControl(raw);
      } else {
        // binary frame → 加密消息
        this.handleBinary(data as Buffer);
      }
    });

    transport.on('close', () => {
      this.transition('closed');
    });

    transport.on('error', (err: Error) => {
      if (this.events.onerror) this.events.onerror(err);
      this.transition('closed');
    });

    // transport open → connecting → handshaking
    this.transition('handshaking');
    this.cancelConnectTimer();
  }

  /** 发送控制消息（明文 text frame），不受加密状态影响 */
  control(type: string, payload: Record<string, unknown>): void {
    const channelId = this.options.role === 'client' 
      ? (this.ephKeyPair ? this.ephKeyPair.publicKey.toString('hex').slice(0, 16) : '')
      : (this.peerEphemeralKeyHex ? this.peerEphemeralKeyHex.slice(0, 16) : '');
    const data = JSON.stringify({ type, channelId, ...payload });
    if (this.state === 'closed') return;
    if (!this.transport) {
      this.enqueue({ data, isControl: true });
      return;
    }
    this.transport.send(data);
  }

  /** 发送加密消息（binary frame），channel 必须是 open 状态 */
  async send(data: string | ArrayBuffer): Promise<void> {
    if (this.state === 'closed') return;
    if (this.state !== 'open') {
      this.enqueue({ data, isControl: false });
      return;
    }
    if (!this.aesKey) throw new Error('E2EE not ready');

    const plain = typeof data === 'string' ? Buffer.from(data, 'utf-8') : Buffer.from(data as ArrayBuffer);
    const seqBuf = Buffer.alloc(8);
    seqBuf.writeBigUInt64BE(BigInt(this.seqNum++));
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.aesKey, iv);
    const ciphertext = Buffer.concat([cipher.update(plain), cipher.final()]);
    const tag = cipher.getAuthTag();
    
    // channelId is the first 8 bytes of the client's ephemeral public key
    const clientEphPubHex = this.options.role === 'client' 
      ? this.ephKeyPair!.publicKey.toString('hex') 
      : this.peerEphemeralKeyHex;
    const channelIdBuf = Buffer.from(clientEphPubHex, 'hex').subarray(0, 8);
    
    const frame = Buffer.concat([channelIdBuf, seqBuf, iv, ciphertext, tag]);
    this.transport!.send(frame);
  }

  /** 关闭通道 */
  close(): void {
    this.transition('closed');
    if (this.transport) {
      try { this.transport.close(); } catch {}
    }
  }

  /** 获取当前状态 */
  getState(): ChannelState {
    return this.state;
  }

  /** 设置事件回调 */
  setEvents(events: EncryptedChannelEvents): void {
    this.events = events;
  }

  /** 重置序列号（re-hello 时调用） */
  resetSeq(): void {
    this.seqNum = 0;
  }

  // ── State Machine ────────────────────────────────────────────────

  private transition(newState: ChannelState): void {
    const old = this.state;
    if (old === newState || old === 'closed') return;
    this.state = newState;

    switch (newState) {
      case 'handshaking':
        this.cancelConnectTimer();
        this.startHandshakeTimer();
        // Host 侧等待 E2EEHello；Client 侧立即发送
        if (this.options.role === 'client') {
          this.sendE2EEHello();
        }
        break;

      case 'open':
        this.cancelHandshakeTimer();
        this.flushPending();
        if (this.events.onopen) this.events.onopen();
        break;

      case 'closed':
        this.cancelAllTimers();
        this.pendingQueue = [];
        this.aesKey = null;
        this.ephKeyPair = null;
        if (this.events.onclose) {
          this.events.onclose(1000, stateReason(old));
        }
        break;
    }
  }

  // ── Timers ───────────────────────────────────────────────────────

  private startConnectTimer(): void {
    this.connectTimer = setTimeout(() => {
      if (this.state === 'connecting') {
        this.transition('closed');
      }
    }, this.options.connectTimeoutMs);
  }

  private cancelConnectTimer(): void {
    if (this.connectTimer !== null) {
      clearTimeout(this.connectTimer);
      this.connectTimer = null;
    }
  }

  private startHandshakeTimer(): void {
    this.handshakeTimer = setTimeout(() => {
      if (this.state === 'handshaking') {
        this.transition('closed');
      }
    }, this.options.handshakeTimeoutMs);
  }

  private cancelHandshakeTimer(): void {
    if (this.handshakeTimer !== null) {
      clearTimeout(this.handshakeTimer);
      this.handshakeTimer = null;
    }
  }

  private cancelAllTimers(): void {
    this.cancelConnectTimer();
    this.cancelHandshakeTimer();
  }

  // ── Pending Queue ────────────────────────────────────────────────

  private enqueue(frame: PendingFrame): void {
    if (this.pendingQueue.length >= MAX_PENDING) return;
    this.pendingQueue.push(frame);
  }

  private flushPending(): void {
    const queue = this.pendingQueue;
    this.pendingQueue = [];
    for (const frame of queue) {
      if (frame.isControl) {
        const parsed = JSON.parse(frame.data as string);
        const { type, ...payload } = parsed;
        this.transport!.send(frame.data as string);
      } else {
        this.send(frame.data).catch(() => {});
      }
    }
  }

  // ── Control Message Handling ─────────────────────────────────────

  private handleControl(raw: string): void {
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return; // invalid JSON, drop
    }

    const type = String(parsed['type'] ?? '');

    // E2EE handshake messages are handled internally
    if (type === 'e2ee_hello') {
      this.handleE2EEHello(parsed);
      return;
    }
    if (type === 'e2ee_ready') {
      this.handleE2EEReady(parsed);
      return;
    }

    // Route other control messages to user callback
    if (this.events.oncontrol) {
      this.events.oncontrol(type, parsed);
    }
  }

  // ── E2EE Handshake ───────────────────────────────────────────────

  private generateEphemeralKeyPair(): { publicKey: Buffer; privateKey: Buffer } {
    const pair = crypto.generateKeyPairSync('x25519' as any, {
      publicKeyEncoding: { type: 'spki', format: 'jwk' } as any,
      privateKeyEncoding: { type: 'pkcs8', format: 'jwk' } as any,
    });
    const pubJwk = pair.publicKey as any;
    const privJwk = pair.privateKey as any;
    return {
      publicKey: Buffer.from(pubJwk.x as string, 'base64url'),
      privateKey: Buffer.from(privJwk.d as string, 'base64url'),
    };
  }

  /** Client 发送 E2EEHello */
  private sendE2EEHello(): void {
    this.ephKeyPair = this.generateEphemeralKeyPair();
    const clientId = this.options.clientId;
    const hostId = this.options.hostIdentity?.hostId ?? '';
    const ephPubHex = this.ephKeyPair.publicKey.toString('hex');
    const clientPubHex = this.options.clientEd25519PublicKeyHex;

    // sign(hostId + ephemeralKey + clientId)
    const signPayload = `${hostId}${ephPubHex}${clientId}`;
    let signature = '';
    if (this.options.clientEd25519PrivateKeyHex) {
      const signKey = this.ed25519PrivateKey(
        this.options.clientEd25519PrivateKeyHex,
        this.options.clientEd25519PublicKeyHex,
      );
      signature = crypto.sign(null, Buffer.from(signPayload), signKey).toString('hex');
    }

    this.control('e2ee_hello', {
      protocolVersion: this.options.protocolVersion,
      clientId,
      clientPublicKey: clientPubHex,
      ephemeralKey: ephPubHex,
      hostId,
      signature,
    } as unknown as Record<string, unknown>);
  }

  /** Host 处理 E2EEHello */
  private handleE2EEHello(msg: Record<string, unknown>): void {
    if (this.state === 'closed') return;

    // Phase 2b: Handshake rate limiting
    if (!checkHandshakeRateLimit()) {
      console.log('[encrypted-channel] Handshake rate limit exceeded, rejecting');
      this.control('e2ee_ready', {
        protocolVersion: CURRENT_PROTOCOL_VERSION,
        accepted: false,
        error: 'rate_limited',
      } as unknown as Record<string, unknown>);
      this.close();
      return;
    }

    const ver = Number(msg['protocolVersion'] ?? 0);
    if (ver < MIN_PROTOCOL_VERSION) {
      // reject
      this.control('e2ee_ready', {
        protocolVersion: CURRENT_PROTOCOL_VERSION,
        accepted: false,
        error: 'version_too_old',
      } as unknown as Record<string, unknown>);
      this.close();
      return;
    }

    if (!this.options.hostIdentity) {
      this.close();
      return;
    }

    const clientId = String(msg['clientId'] ?? '');
    const clientPubHex = String(msg['clientPublicKey'] ?? '');
    const ephHex = String(msg['ephemeralKey'] ?? '');
    this.peerEphemeralKeyHex = ephHex;
    const signature = String(msg['signature'] ?? '');
    const hostId = String(msg['hostId'] ?? '');

    // Verify Ed25519 signature
    const signPayload = `${hostId}${ephHex}${clientId}`;
    let valid = false;
    if (clientPubHex && signature) {
      try {
        const verifyKey = this.ed25519PublicKey(clientPubHex);
        valid = crypto.verify(null, Buffer.from(signPayload), verifyKey, Buffer.from(signature, 'hex'));
      } catch {
        valid = false;
      }
    }

    if (!valid) {
      this.control('e2ee_ready', {
        protocolVersion: CURRENT_PROTOCOL_VERSION,
        accepted: false,
        error: 'signature_verification_failed',
      } as unknown as Record<string, unknown>);
      this.close();
      return;
    }

    // Re-hello check: if already open with different key, re-key
    if (this.state === 'open') {
      if (this.ephKeyPair && this.ephKeyPair.publicKey.toString('hex') !== ephHex) {
        // Different key → re-key
        this.state = 'handshaking';
        this.pendingQueue = [];
        this.seqNum = 0;
      } else {
        // Same key → just re-send ready
        this.control('e2ee_ready', {
          protocolVersion: CURRENT_PROTOCOL_VERSION,
          ephemeralKey: this.ephKeyPair!.publicKey.toString('hex'),
          accepted: true,
          signature: this.buildHostSignature(this.ephKeyPair!.publicKey.toString('hex'), clientId),
        } as unknown as Record<string, unknown>);
        return;
      }
    }

    // Generate ephemeral keypair if not already (first handshake)
    if (!this.ephKeyPair) {
      this.ephKeyPair = this.generateEphemeralKeyPair();
    }

    const ephClient = Buffer.from(ephHex, 'hex');
    const sharedSecret = this.x25519DiffieHellman(
      this.ephKeyPair.privateKey,
      this.ephKeyPair.publicKey,
      ephClient,
    );

    // HKDF-SHA256
    const salt = ephClient.subarray(0, 16);
    this.aesKey = hkdfExpand(sharedSecret, salt, 'anywhere-e2ee-v1');

    // Send E2EEReady
    this.control('e2ee_ready', {
      protocolVersion: CURRENT_PROTOCOL_VERSION,
      ephemeralKey: this.ephKeyPair.publicKey.toString('hex'),
      accepted: true,
      signature: this.buildHostSignature(this.ephKeyPair.publicKey.toString('hex'), clientId),
    } as unknown as Record<string, unknown>);

    this.transition('open');
  }

  /** Client 处理 E2EEReady */
  private handleE2EEReady(msg: Record<string, unknown>): void {
    if (this.state === 'closed') return;

    const accepted = Boolean(msg['accepted']);
    if (!accepted) {
      const error = String(msg['error'] ?? 'unknown_error');
      if (this.events.onerror) {
        this.events.onerror(new Error(`Handshake rejected: ${error}`));
      }
      this.close();
      return;
    }

    if (!this.ephKeyPair) return;

    const ephHostHex = String(msg['ephemeralKey'] ?? '');
    this.peerEphemeralKeyHex = ephHostHex;
    const hostSignature = String(msg['signature'] ?? '');
    const hostId = this.options.hostIdentity?.hostId ?? '';

    // Verify host signature
    const signPayload = `${hostId}${ephHostHex}${this.options.clientId}`;
    let valid = false;
    if (this.options.hostEd25519PublicKeyHex && hostSignature) {
      try {
        const verifyKey = this.ed25519PublicKey(this.options.hostEd25519PublicKeyHex);
        valid = crypto.verify(null, Buffer.from(signPayload), verifyKey, Buffer.from(hostSignature, 'hex'));
      } catch {
        valid = false;
      }
    }

    if (!valid) {
      if (this.events.onerror) {
        this.events.onerror(new Error('Host signature verification failed'));
      }
      this.close();
      return;
    }

    const ephHost = Buffer.from(ephHostHex, 'hex');
    const sharedSecret = this.x25519DiffieHellman(
      this.ephKeyPair.privateKey,
      this.ephKeyPair.publicKey,
      ephHost,
    );

    // HKDF-SHA256
    const salt = this.ephKeyPair.publicKey.subarray(0, 16);
    this.aesKey = hkdfExpand(sharedSecret, salt, 'anywhere-e2ee-v1');

    this.transition('open');
  }

  private buildHostSignature(ephHex: string, clientId: string): string {
    const hostId = this.options.hostIdentity?.hostId ?? '';
    const signPayload = `${hostId}${ephHex}${clientId}`;
    if (this.options.hostIdentity?.ed25519PrivateKeyHex && this.options.hostIdentity?.ed25519PublicKeyHex) {
      const signKey = this.ed25519PrivateKey(
        this.options.hostIdentity.ed25519PrivateKeyHex,
        this.options.hostIdentity.ed25519PublicKeyHex,
      );
      return crypto.sign(null, Buffer.from(signPayload), signKey).toString('hex');
    }
    return '';
  }

  // ── Ed25519 Key Helpers ──────────────────────────────────────────

  /** Create Ed25519 private key from hex strings (raw 32-byte values from JWK) */
  private ed25519PrivateKey(privateHex: string, publicHex: string): crypto.KeyObject {
    return crypto.createPrivateKey({
      key: {
        kty: 'OKP',
        crv: 'Ed25519',
        x: Buffer.from(publicHex, 'hex').toString('base64url'),
        d: Buffer.from(privateHex, 'hex').toString('base64url'),
      },
      format: 'jwk',
    });
  }

  /** Create Ed25519 public key from hex string, accepting both raw 32-byte and DER SPKI format */
  private ed25519PublicKey(publicHex: string): crypto.KeyObject {
    const raw: Buffer = Buffer.from(publicHex, 'hex');
    // Raw 32-byte key → JWK format
    if (raw.length === 32) {
      return crypto.createPublicKey({
        key: {
          kty: 'OKP',
          crv: 'Ed25519',
          x: raw.toString('base64url'),
        },
        format: 'jwk',
      });
    }
    // DER SPKI format (e.g. from HarmonyOS cryptoFramework.getEncoded())
    return crypto.createPublicKey({
      key: raw,
      format: 'der',
      type: 'spki',
    });
  }

  /** X25519 ECDH using crypto.diffieHellman */
  private x25519DiffieHellman(
    myPrivateKeyRaw: Buffer,
    myPublicKeyRaw: Buffer,
    theirPublicKeyRaw: Buffer,
  ): Buffer {
    const privateKey = crypto.createPrivateKey({
      key: {
        kty: 'OKP',
        crv: 'X25519',
        x: myPublicKeyRaw.toString('base64url'),
        d: myPrivateKeyRaw.toString('base64url'),
      },
      format: 'jwk',
    });
    const publicKey = crypto.createPublicKey({
      key: {
        kty: 'OKP',
        crv: 'X25519',
        x: theirPublicKeyRaw.toString('base64url'),
    },
    format: 'jwk',
  });
    return crypto.diffieHellman({ privateKey, publicKey });
  }


  private handleBinary(frame: Buffer): void {
    if (!this.aesKey || this.state !== 'open') return;

    if (frame.length < 8 + 36) return; // 8 channelId + 8 seq + 12 iv + 16 tag minimum
    // The first 8 bytes are the channelId. Skip them.
    const seqBuf = frame.subarray(8, 16);
    const iv = frame.subarray(16, 28);
    const tag = frame.subarray(frame.length - 16);
    const ciphertext = frame.subarray(28, frame.length - 16);

    const seq = Number(seqBuf.readBigUInt64BE());
    // Phase 2b: Validate sequence number monotonicity (strictly increasing)
    if (seq <= this.lastRemoteSeq) {
      console.log(`[encrypted-channel] Invalid sequence: ${seq} <= ${this.lastRemoteSeq}, closing`);
      this.close();
      return;
    }
    this.lastRemoteSeq = seq;

    try {
      const decipher = crypto.createDecipheriv('aes-256-gcm', this.aesKey, iv);
      decipher.setAuthTag(tag);
      const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      if (this.events.onmessage) {
        this.events.onmessage(plain.toString('utf-8'));
      }
    } catch {
      // Decryption failure — corrupt or tampered, drop silently
    }
  }

  /** 对外暴露：处理对方发来的 binary frame（从外部传输层注入） */
  feedBinary(frame: Buffer): void {
    this.handleBinary(frame);
  }
}

// ── Utility ────────────────────────────────────────────────────────

function hkdfExpand(secret: Buffer, salt: Buffer, info: string): Buffer {
  // Simple HKDF-Expand using HMAC-SHA256
  // Step 1: Extract (PRK = HMAC-SHA256(salt, secret))
  const prk = crypto.createHmac('sha256', salt).update(secret).digest();
  // Step 2: Expand (single block since we need 32 bytes, ≤ 32)
  const t1 = crypto.createHmac('sha256', prk).update(Buffer.from(info, 'utf-8')).update(Buffer.from([0x01])).digest();
  return t1.subarray(0, 32);
}

function stateReason(state: ChannelState): string {
  switch (state) {
    case 'connecting': return 'Connect timeout';
    case 'handshaking': return 'Handshake timeout or failure';
    default: return 'Channel closed';
  }
}

export { CURRENT_PROTOCOL_VERSION, MIN_PROTOCOL_VERSION };
