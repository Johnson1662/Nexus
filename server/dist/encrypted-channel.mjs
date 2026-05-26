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
// ── Constants ──────────────────────────────────────────────────────
const MAX_PENDING = 200;
const DEFAULT_CONNECT_TIMEOUT_MS = 10_000;
const DEFAULT_HANDSHAKE_TIMEOUT_MS = 15_000;
const CURRENT_PROTOCOL_VERSION = 1;
const MIN_PROTOCOL_VERSION = 1;
// ── EncryptedChannel ───────────────────────────────────────────────
export class EncryptedChannel {
    state = 'connecting';
    transport = null;
    options;
    events = {};
    pendingQueue = [];
    connectTimer = null;
    handshakeTimer = null;
    seqNum = 0;
    aesKey = null;
    // Ephemeral X25519 keypair for PFS
    ephKeyPair = null;
    constructor(opts, events) {
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
        };
        if (events)
            this.events = events;
        this.startConnectTimer();
    }
    // ── Public API ───────────────────────────────────────────────────
    /** 绑定传输层（transport open 后调用） */
    attachTransport(transport) {
        this.transport = transport;
        transport.on('message', (data) => {
            const raw = typeof data === 'string' ? data : data.toString('utf-8');
            // 区分 text frame(控制) vs binary frame(加密)
            if (typeof data === 'string' || !(data instanceof Buffer)) {
                // text frame → 控制消息
                this.handleControl(raw);
            }
            else {
                // binary frame → 加密消息
                this.handleBinary(data);
            }
        });
        transport.on('close', () => {
            this.transition('closed');
        });
        transport.on('error', (err) => {
            if (this.events.onerror)
                this.events.onerror(err);
            this.transition('closed');
        });
        // transport open → connecting → handshaking
        this.transition('handshaking');
        this.cancelConnectTimer();
    }
    /** 发送控制消息（明文 text frame），不受加密状态影响 */
    control(type, payload) {
        const data = JSON.stringify({ type, ...payload });
        if (this.state === 'closed')
            return;
        if (!this.transport) {
            this.enqueue({ data, isControl: true });
            return;
        }
        this.transport.send(data);
    }
    /** 发送加密消息（binary frame），channel 必须是 open 状态 */
    async send(data) {
        if (this.state === 'closed')
            return;
        if (this.state !== 'open') {
            this.enqueue({ data, isControl: false });
            return;
        }
        if (!this.aesKey)
            throw new Error('E2EE not ready');
        const plain = typeof data === 'string' ? Buffer.from(data, 'utf-8') : Buffer.from(data);
        const seqBuf = Buffer.alloc(8);
        seqBuf.writeBigUInt64BE(BigInt(this.seqNum++));
        const iv = crypto.randomBytes(12);
        const cipher = crypto.createCipheriv('aes-256-gcm', this.aesKey, iv);
        const ciphertext = Buffer.concat([cipher.update(plain), cipher.final()]);
        const tag = cipher.getAuthTag();
        const frame = Buffer.concat([seqBuf, iv, ciphertext, tag]);
        this.transport.send(frame);
    }
    /** 关闭通道 */
    close() {
        this.transition('closed');
        if (this.transport) {
            try {
                this.transport.close();
            }
            catch { }
        }
    }
    /** 获取当前状态 */
    getState() {
        return this.state;
    }
    /** 设置事件回调 */
    setEvents(events) {
        this.events = events;
    }
    /** 重置序列号（re-hello 时调用） */
    resetSeq() {
        this.seqNum = 0;
    }
    // ── State Machine ────────────────────────────────────────────────
    transition(newState) {
        const old = this.state;
        if (old === newState || old === 'closed')
            return;
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
                if (this.events.onopen)
                    this.events.onopen();
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
    startConnectTimer() {
        this.connectTimer = setTimeout(() => {
            if (this.state === 'connecting') {
                this.transition('closed');
            }
        }, this.options.connectTimeoutMs);
    }
    cancelConnectTimer() {
        if (this.connectTimer !== null) {
            clearTimeout(this.connectTimer);
            this.connectTimer = null;
        }
    }
    startHandshakeTimer() {
        this.handshakeTimer = setTimeout(() => {
            if (this.state === 'handshaking') {
                this.transition('closed');
            }
        }, this.options.handshakeTimeoutMs);
    }
    cancelHandshakeTimer() {
        if (this.handshakeTimer !== null) {
            clearTimeout(this.handshakeTimer);
            this.handshakeTimer = null;
        }
    }
    cancelAllTimers() {
        this.cancelConnectTimer();
        this.cancelHandshakeTimer();
    }
    // ── Pending Queue ────────────────────────────────────────────────
    enqueue(frame) {
        if (this.pendingQueue.length >= MAX_PENDING)
            return;
        this.pendingQueue.push(frame);
    }
    flushPending() {
        const queue = this.pendingQueue;
        this.pendingQueue = [];
        for (const frame of queue) {
            if (frame.isControl) {
                const parsed = JSON.parse(frame.data);
                const { type, ...payload } = parsed;
                this.transport.send(frame.data);
            }
            else {
                this.send(frame.data).catch(() => { });
            }
        }
    }
    // ── Control Message Handling ─────────────────────────────────────
    handleControl(raw) {
        let parsed;
        try {
            parsed = JSON.parse(raw);
        }
        catch {
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
    generateEphemeralKeyPair() {
        const pair = crypto.generateKeyPairSync('x25519', {
            publicKeyEncoding: { type: 'spki', format: 'jwk' },
            privateKeyEncoding: { type: 'pkcs8', format: 'jwk' },
        });
        const pubJwk = pair.publicKey;
        const privJwk = pair.privateKey;
        return {
            publicKey: Buffer.from(pubJwk.x, 'base64url'),
            privateKey: Buffer.from(privJwk.d, 'base64url'),
        };
    }
    /** Client 发送 E2EEHello */
    sendE2EEHello() {
        this.ephKeyPair = this.generateEphemeralKeyPair();
        const clientId = this.options.clientId;
        const hostId = this.options.hostIdentity?.hostId ?? '';
        const ephPubHex = this.ephKeyPair.publicKey.toString('hex');
        const clientPubHex = this.options.clientEd25519PublicKeyHex;
        // sign(hostId + ephemeralKey + clientId)
        const signPayload = `${hostId}${ephPubHex}${clientId}`;
        let signature = '';
        if (this.options.clientEd25519PrivateKeyHex) {
            const signKey = this.ed25519PrivateKey(this.options.clientEd25519PrivateKeyHex, this.options.clientEd25519PublicKeyHex);
            signature = crypto.sign(null, Buffer.from(signPayload), signKey).toString('hex');
        }
        this.control('e2ee_hello', {
            protocolVersion: this.options.protocolVersion,
            clientId,
            clientPublicKey: clientPubHex,
            ephemeralKey: ephPubHex,
            hostId,
            signature,
        });
    }
    /** Host 处理 E2EEHello */
    handleE2EEHello(msg) {
        if (this.state === 'closed')
            return;
        const ver = Number(msg['protocolVersion'] ?? 0);
        if (ver < MIN_PROTOCOL_VERSION) {
            // reject
            this.control('e2ee_ready', {
                protocolVersion: CURRENT_PROTOCOL_VERSION,
                accepted: false,
                error: 'version_too_old',
            });
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
        const signature = String(msg['signature'] ?? '');
        const hostId = String(msg['hostId'] ?? '');
        // Verify Ed25519 signature
        const signPayload = `${hostId}${ephHex}${clientId}`;
        let valid = false;
        if (clientPubHex && signature) {
            try {
                const verifyKey = this.ed25519PublicKey(clientPubHex);
                valid = crypto.verify(null, Buffer.from(signPayload), verifyKey, Buffer.from(signature, 'hex'));
            }
            catch {
                valid = false;
            }
        }
        if (!valid) {
            this.control('e2ee_ready', {
                protocolVersion: CURRENT_PROTOCOL_VERSION,
                accepted: false,
                error: 'signature_verification_failed',
            });
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
            }
            else {
                // Same key → just re-send ready
                this.control('e2ee_ready', {
                    protocolVersion: CURRENT_PROTOCOL_VERSION,
                    ephemeralKey: this.ephKeyPair.publicKey.toString('hex'),
                    accepted: true,
                    signature: this.buildHostSignature(this.ephKeyPair.publicKey.toString('hex'), clientId),
                });
                return;
            }
        }
        // Generate ephemeral keypair if not already (first handshake)
        if (!this.ephKeyPair) {
            this.ephKeyPair = this.generateEphemeralKeyPair();
        }
        const ephClient = Buffer.from(ephHex, 'hex');
        const sharedSecret = this.x25519DiffieHellman(this.ephKeyPair.privateKey, this.ephKeyPair.publicKey, ephClient);
        // HKDF-SHA256
        const salt = ephClient.subarray(0, 16);
        this.aesKey = hkdfExpand(sharedSecret, salt, 'anywhere-e2ee-v1');
        // Send E2EEReady
        this.control('e2ee_ready', {
            protocolVersion: CURRENT_PROTOCOL_VERSION,
            ephemeralKey: this.ephKeyPair.publicKey.toString('hex'),
            accepted: true,
            signature: this.buildHostSignature(this.ephKeyPair.publicKey.toString('hex'), clientId),
        });
        this.transition('open');
    }
    /** Client 处理 E2EEReady */
    handleE2EEReady(msg) {
        if (this.state === 'closed')
            return;
        const accepted = Boolean(msg['accepted']);
        if (!accepted) {
            const error = String(msg['error'] ?? 'unknown_error');
            if (this.events.onerror) {
                this.events.onerror(new Error(`Handshake rejected: ${error}`));
            }
            this.close();
            return;
        }
        if (!this.ephKeyPair)
            return;
        const ephHostHex = String(msg['ephemeralKey'] ?? '');
        const hostSignature = String(msg['signature'] ?? '');
        const hostId = this.options.hostIdentity?.hostId ?? '';
        // Verify host signature
        const signPayload = `${hostId}${ephHostHex}${this.options.clientId}`;
        let valid = false;
        if (this.options.hostEd25519PublicKeyHex && hostSignature) {
            try {
                const verifyKey = this.ed25519PublicKey(this.options.hostEd25519PublicKeyHex);
                valid = crypto.verify(null, Buffer.from(signPayload), verifyKey, Buffer.from(hostSignature, 'hex'));
            }
            catch {
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
        const sharedSecret = this.x25519DiffieHellman(this.ephKeyPair.privateKey, this.ephKeyPair.publicKey, ephHost);
        // HKDF-SHA256
        const salt = this.ephKeyPair.publicKey.subarray(0, 16);
        this.aesKey = hkdfExpand(sharedSecret, salt, 'anywhere-e2ee-v1');
        this.transition('open');
    }
    buildHostSignature(ephHex, clientId) {
        const hostId = this.options.hostIdentity?.hostId ?? '';
        const signPayload = `${hostId}${ephHex}${clientId}`;
        if (this.options.hostIdentity?.ed25519PrivateKeyHex && this.options.hostIdentity?.ed25519PublicKeyHex) {
            const signKey = this.ed25519PrivateKey(this.options.hostIdentity.ed25519PrivateKeyHex, this.options.hostIdentity.ed25519PublicKeyHex);
            return crypto.sign(null, Buffer.from(signPayload), signKey).toString('hex');
        }
        return '';
    }
    // ── Ed25519 Key Helpers ──────────────────────────────────────────
    /** Create Ed25519 private key from hex strings (raw 32-byte values from JWK) */
    ed25519PrivateKey(privateHex, publicHex) {
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
    /** Create Ed25519 public key from hex string */
    ed25519PublicKey(publicHex) {
        return crypto.createPublicKey({
            key: {
                kty: 'OKP',
                crv: 'Ed25519',
                x: Buffer.from(publicHex, 'hex').toString('base64url'),
            },
            format: 'jwk',
        });
    }
    /** X25519 ECDH using crypto.diffieHellman */
    x25519DiffieHellman(myPrivateKeyRaw, myPublicKeyRaw, theirPublicKeyRaw) {
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
    handleBinary(frame) {
        if (!this.aesKey || this.state !== 'open')
            return;
        if (frame.length < 36)
            return; // 8 seq + 12 iv + 16 tag minimum
        const seqBuf = frame.subarray(0, 8);
        const iv = frame.subarray(8, 20);
        const tag = frame.subarray(frame.length - 16);
        const ciphertext = frame.subarray(20, frame.length - 16);
        const seq = Number(seqBuf.readBigUInt64BE());
        // Note: we should validate sequence number monotonicity here
        // For Phase 2a, basic check — full check needs per-connection state
        try {
            const decipher = crypto.createDecipheriv('aes-256-gcm', this.aesKey, iv);
            decipher.setAuthTag(tag);
            const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
            if (this.events.onmessage) {
                this.events.onmessage(plain.toString('utf-8'));
            }
        }
        catch {
            // Decryption failure — corrupt or tampered, drop silently
        }
    }
    /** 对外暴露：处理对方发来的 binary frame（从外部传输层注入） */
    feedBinary(frame) {
        this.handleBinary(frame);
    }
}
// ── Utility ────────────────────────────────────────────────────────
function hkdfExpand(secret, salt, info) {
    // Simple HKDF-Expand using HMAC-SHA256
    // Step 1: Extract (PRK = HMAC-SHA256(salt, secret))
    const prk = crypto.createHmac('sha256', salt).update(secret).digest();
    // Step 2: Expand (single block since we need 32 bytes, ≤ 32)
    const t1 = crypto.createHmac('sha256', prk).update(Buffer.from(info, 'utf-8')).update(Buffer.from([0x01])).digest();
    return t1.subarray(0, 32);
}
function stateReason(state) {
    switch (state) {
        case 'connecting': return 'Connect timeout';
        case 'handshaking': return 'Handshake timeout or failure';
        default: return 'Channel closed';
    }
}
export { CURRENT_PROTOCOL_VERSION, MIN_PROTOCOL_VERSION };
//# sourceMappingURL=encrypted-channel.mjs.map