import { webSocket, http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ChatStore } from '../model/ChatState';
import { ServerSession, HostStore, DeviceEntry } from '../model/WorkspaceInfo';
import { HostRuntimeStore } from '../model/HostState';
import {
  StorageService,
  PrefsKeys,
  saveHosts,
  saveWorkspaceModelCache,
  saveWorkspaceSessionCache,
  saveAgentCache,
  saveLastModelSelection,
  loadLastModelSelection
} from '../../services/StorageService';
import { WorkspaceStore } from '../model/WorkspaceInfo';
import { ClientMessage, ServerMessage, AcpUpdate, AgentInfo, ServerInfoMessage, SyncResponseMessage, SyncResponseEntry } from './WSProtocol';
import { getOrCreateClientKeyPair, signWithClientKey, generateEphemeralKeyPair } from './CryptoHelper';
import { PhoneEncryptedChannel } from './PhoneEncryptedChannel';
import { DeviceAgentStore } from '../model/DeviceAgentStore';

import { ModelItem, ModeItem } from '../model/ChatState';

function repairRelayJson(raw: string): string {
  let trimmed = raw.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    if (trimmed.indexOf('"') < 0 && trimmed.indexOf('\'') < 0) {
      // Repaired missing quotes in key-value pairs (e.g. {type:heartbeat,ts:12345} -> {"type":"heartbeat","ts":"12345"})
      let repaired = trimmed
        .replace(/([{,])\s*([a-zA-Z0-9_]+)\s*:/g, '$1"$2":') 
        .replace(/:\s*([a-zA-Z0-9_\-\.]+)\s*([,}])/g, ':"$1"$2');
      return repaired;
    }
  }
  return raw;
}

const DOMAIN: number = 0x0000;
const TAG: string = 'WSClient';
const PROBE_TIMEOUT_MS: number = 1200;

interface ProbeCandidateResult {
  url: string;
  probeUrl: string;
  ok: boolean;
  latencyMs: number;
  kind: string;
  hostId: string;
  hostname: string;
  error: string;
}

function stripQuery(url: string): string {
  let qIdx: number = url.indexOf('?');
  return qIdx >= 0 ? url.substring(0, qIdx) : url;
}

function getUrlScheme(url: string): string {
  let schemeEnd: number = url.indexOf('://');
  if (schemeEnd > 0) {
    return url.substring(0, schemeEnd);
  }
  return 'ws';
}

function getUrlPort(url: string): string {
  let cleanUrl: string = stripQuery(url);
  let schemeEnd: number = cleanUrl.indexOf('://');
  let rest: string = schemeEnd >= 0 ? cleanUrl.substring(schemeEnd + 3) : cleanUrl;
  if (rest.startsWith('[')) {
    let closeBracket: number = rest.indexOf(']');
    if (closeBracket >= 0 && closeBracket + 2 < rest.length && rest[closeBracket + 1] === ':') {
      return rest.substring(closeBracket + 2);
    }
  }
  let portSep: number = rest.lastIndexOf(':');
  if (portSep >= 0 && portSep + 1 < rest.length) {
    return rest.substring(portSep + 1);
  }
  return '12138';
}

function getUrlHost(url: string): string {
  let cleanUrl: string = stripQuery(url);
  let schemeEnd: number = cleanUrl.indexOf('://');
  let rest: string = schemeEnd >= 0 ? cleanUrl.substring(schemeEnd + 3) : cleanUrl;
  if (rest.startsWith('[')) {
    let closeBracket: number = rest.indexOf(']');
    return closeBracket >= 0 ? rest.substring(1, closeBracket) : rest;
  }
  let slashIdx: number = rest.indexOf('/');
  if (slashIdx >= 0) {
    rest = rest.substring(0, slashIdx);
  }
  let portSep: number = rest.lastIndexOf(':');
  if (portSep >= 0) {
    return rest.substring(0, portSep);
  }
  return rest;
}

function getIpv4Part(ip: string, index: number): number {
  let parts: string[] = ip.split('.');
  if (parts.length !== 4 || index < 0 || index >= parts.length) return -1;
  let value: number = Number(parts[index]);
  return Number.isFinite(value) ? value : -1;
}

function isTailscaleIpv4(host: string): boolean {
  let first: number = getIpv4Part(host, 0);
  let second: number = getIpv4Part(host, 1);
  return first === 100 && second >= 64 && second <= 127;
}

function isPrivate172Ipv4(host: string): boolean {
  let first: number = getIpv4Part(host, 0);
  let second: number = getIpv4Part(host, 1);
  return first === 172 && second >= 16 && second <= 31;
}

function getCandidatePriority(url: string): number {
  let host: string = getUrlHost(url);
  if (host === '192.168.137.1') return 0;
  if (host.startsWith('192.168.')) return 1;
  if (host.startsWith('10.') || isPrivate172Ipv4(host)) return 2;
  if (isTailscaleIpv4(host)) return 3;
  if (isRelayClientUrl(url)) return 4;
  if (isKnownRelayUrl(url)) return 5;
  return 2;
}

function getUrlQueryValue(url: string, key: string): string {
  let marker: string = key + '=';
  let start: number = url.indexOf(marker);
  if (start < 0) return '';
  start += marker.length;
  let end: number = url.indexOf('&', start);
  if (end < 0) end = url.length;
  return url.substring(start, end);
}

function isKnownRelayUrl(url: string): boolean {
  return url.indexOf('relay.anywhere12138.lat') >= 0 || url.indexOf('35.212.155.17') >= 0;
}

function isRelayClientUrl(url: string): boolean {
  return isKnownRelayUrl(url) && url.indexOf('targetHostId=') >= 0;
}

function isDirtyRelayPairUrl(url: string): boolean {
  return url.indexOf('targetHostId=') >= 0 && !isKnownRelayUrl(url);
}

function isDirectIpv6Url(url: string): boolean {
  return url.startsWith('ws://[') || url.startsWith('wss://[');
}

function toPrimaryConnectionUrl(url: string): string {
  if (url.length === 0) return '';
  return isRelayClientUrl(url) ? url : stripQuery(url);
}

function buildProbeUrl(url: string): string {
  let cleanUrl: string = stripQuery(url);
  let base: string = '';
  if (cleanUrl.startsWith('ws://')) {
    base = 'http://' + cleanUrl.substring(5);
  } else if (cleanUrl.startsWith('wss://')) {
    base = 'https://' + cleanUrl.substring(6);
  } else {
    return '';
  }

  if (isRelayClientUrl(url)) {
    let targetHostId: string = getUrlQueryValue(url, 'targetHostId');
    if (targetHostId.length === 0) return '';
    return base + '/probe?targetHostId=' + targetHostId;
  }
  return base + '/probe';
}

function getStringField(data: Record<string, Object>, key: string): string {
  let value = data[key];
  if (value === undefined || value === null) return '';
  return String(value);
}

function getBooleanField(data: Record<string, Object>, key: string): boolean {
  let value = data[key];
  if (value === undefined || value === null) return false;
  if (typeof value === 'boolean') return Boolean(value);
  return String(value) === 'true';
}

function matchesExpectedHost(data: Record<string, Object>, expectedHostKey: string): boolean {
  if (expectedHostKey.length === 0) return true;
  return getStringField(data, 'hostId') === expectedHostKey || getStringField(data, 'hostname') === expectedHostKey;
}

function buildWsUrlFromIp(ip: string, port: string, scheme: string): string {
  if (ip.length === 0 || ip.startsWith('HOST:')) {
    return '';
  }
  if (ip.indexOf(':') >= 0) {
    return '';
  }
  let host: string = ip;
  return scheme + '://' + host + ':' + port;
}

function addUniqueUrl(urls: string[], url: string): void {
  if (url.length > 0 && urls.indexOf(url) < 0) {
    urls.push(url);
  }
}

function getMessageSessionId(messageId: string): string {
  let idx: number = messageId.lastIndexOf(':');
  if (idx <= 0) return '';
  return messageId.substring(0, idx);
}

function getMessageSeq(messageId: string): number {
  let idx: number = messageId.lastIndexOf(':');
  if (idx < 0 || idx + 1 >= messageId.length) return 0;
  return parseInt(messageId.substring(idx + 1), 10) || 0;
}

function hasProcessedMessage(messageId: string): boolean {
  if (messageId.length === 0 || ChatStore.lastMessageId.length === 0) return false;
  if (messageId === ChatStore.lastMessageId) return true;
  let sessionId: string = getMessageSessionId(messageId);
  let currentSessionId: string = getMessageSessionId(ChatStore.lastMessageId);
  if (sessionId.length === 0 || sessionId !== currentSessionId) return false;
  let seq: number = getMessageSeq(messageId);
  let currentSeq: number = getMessageSeq(ChatStore.lastMessageId);
  return seq > 0 && currentSeq > 0 && seq <= currentSeq;
}

let lastMessagePersistTime: number = 0;

function rememberMessageId(messageId: string): void {
  if (messageId.length === 0) return;
  ChatStore.lastMessageId = messageId;
  let now: number = Date.now();
  if (now - lastMessagePersistTime >= 1000) {
    lastMessagePersistTime = now;
    StorageService.getInstance().putString(PrefsKeys.LAST_MESSAGE_ID, messageId);
  }
}

function clearMessageId(): void {
  ChatStore.lastMessageId = '';
  StorageService.getInstance().putString(PrefsKeys.LAST_MESSAGE_ID, '');
}

export type StateChangeCallback = (connected: boolean, detail: string) => void;
export type ModelListCallback = (models: ModelItem[], modes: ModeItem[]) => void;
export type SessionListCallback = (sessions: ServerSession[]) => void;
export type AcpUpdateCallback = (update: AcpUpdate) => void;
export type AgentListCallback = (agents: AgentInfo[]) => void;
export type ErrorCallback = (text: string) => void;
export type EmptyCallback = () => void;

export class WSClient {
  private ws: webSocket.WebSocket | null = null;
  private stateListeners: StateChangeCallback[] = [];
  private modelListeners: ModelListCallback[] = [];
  private sessionListeners: SessionListCallback[] = [];
  private updateListeners: AcpUpdateCallback[] = [];
  private agentListListeners: AgentListCallback[] = [];
  private errorListeners: ErrorCallback[] = [];
  private sessionStartedListeners: EmptyCallback[] = [];
  private serverInfoListeners: EmptyCallback[] = [];
  private lastUrl: string = '';
  private reconnectTimer: number | null = null;
  private reconnectAttempts: number = 0;
  private intentionalClose: boolean = false;
  private suspendRequestId: number | null = null;
  private wsGen: number = 0;
  private everConnected: boolean = false;
  private hostEverOnline: boolean = false;
  private targetHostKey: string = '';
  private reconnectCandidates: string[] = [];
  private waitingHostTimer: number | null = null;
  private _e2eeReady: boolean = false;
  private _e2eeClientId: string = '';
  private channel: PhoneEncryptedChannel = new PhoneEncryptedChannel();
  // Heartbeat state (Phase 2b)
  private lastHeartbeatReceived: number = 0;
  private heartbeatWatchdog: number | null = null;
  private heartbeatSender: number | null = null;
  private readonly HEARTBEAT_WATCHDOG_MS: number = 45_000;  // 45s no heartbeat → disconnect

  connect(url: string, hostKey: string = ''): void {
    this.reconnectCandidates = this.normalizeCandidateUrls([url]);
    this.connectSelected(url, hostKey);
  }

  private connectSelected(url: string, hostKey: string = ''): void {
    this.cancelReconnect();
    this.cancelWaitingHostTimer();
    this.lastUrl = url;
    this.targetHostKey = this.resolveHostKey(url, hostKey);
    this.hostEverOnline = HostRuntimeStore.hasEverOnline(this.targetHostKey) || this.reconnectCandidates.length > 1;
    this.intentionalClose = false;
    this.reconnectAttempts = 0;
    this.everConnected = false;
    HostRuntimeStore.markConnecting(this.targetHostKey, url);
    ChatStore.connected = false;
    ChatStore.currentDeviceId = '';
    this.doConnect(url);
  }

  private normalizeCandidateUrls(urls: string[]): string[] {
    let result: string[] = [];
    for (let i: number = 0; i < urls.length; i++) {
      let url: string = urls[i];
      if (isDirectIpv6Url(url) || isDirtyRelayPairUrl(url)) {
        continue;
      }
      if (url.length > 0 && result.indexOf(url) < 0) {
        result.push(url);
      }
    }
    return result;
  }

  private resolveHostKey(url: string, hostKey: string): string {
    if (hostKey.length > 0) return hostKey;
    let targetHostId: string = getUrlQueryValue(url, 'targetHostId');
    if (targetHostId.length > 0) return targetHostId;
    return stripQuery(url);
  }

  async probeCandidate(url: string, expectedHostKey: string): Promise<ProbeCandidateResult> {
    let probeUrl: string = buildProbeUrl(url);
    let start: number = Date.now();
    if (probeUrl.length === 0) {
      return {
        url,
        probeUrl,
        ok: false,
        latencyMs: -1,
        kind: '',
        hostId: '',
        hostname: '',
        error: 'invalid probe url',
      };
    }

    let request = http.createHttp();
    try {
      let response = await request.request(probeUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: PROBE_TIMEOUT_MS,
        readTimeout: PROBE_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      });
      let latencyMs: number = Date.now() - start;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return {
          url,
          probeUrl,
          ok: false,
          latencyMs: -1,
          kind: '',
          hostId: '',
          hostname: '',
          error: 'http ' + response.responseCode.toString(),
        };
      }

      let data: Record<string, Object> = JSON.parse(String(response.result));
      let kind: string = getStringField(data, 'kind');
      let hostId: string = getStringField(data, 'hostId');
      let hostname: string = getStringField(data, 'hostname');
      let ok: boolean = getBooleanField(data, 'ok') && matchesExpectedHost(data, expectedHostKey);
      if (kind === 'relay') {
        ok = ok && getBooleanField(data, 'hostOnline') && getBooleanField(data, 'pong') && this.hasRelayCredentials();
      }
      return {
        url,
        probeUrl,
        ok,
        latencyMs: ok ? latencyMs : -1,
        kind,
        hostId,
        hostname,
        error: ok ? '' : 'probe rejected',
      };
    } catch {
      return {
        url,
        probeUrl,
        ok: false,
        latencyMs: -1,
        kind: '',
        hostId: '',
        hostname: '',
        error: 'probe failed',
      };
    } finally {
      try { request.destroy(); } catch {}
    }
  }

  // Connect to the fastest reachable URL from a device, then use that URL
  async connectBest(urls: string[], hostKey: string = ''): Promise<void> {
    let candidates: string[] = this.normalizeCandidateUrls(urls);
    let resolvedHostKey: string = candidates.length > 0 ? this.resolveHostKey(candidates[0], hostKey) : hostKey;
    if (candidates.length === 0) {
      hilog.error(DOMAIN, TAG, 'connectBest: empty urls, abort');
      HostRuntimeStore.markOffline(resolvedHostKey, 'no candidate urls');
      return;
    }
    this.reconnectCandidates = candidates;
    HostRuntimeStore.markConnecting(resolvedHostKey, candidates[0]);
    let bestUrl: string = await this.pickBestCandidate(candidates, resolvedHostKey, 'connectBest');
    this.connectSelected(bestUrl, resolvedHostKey);
  }

  private async pickBestCandidate(urls: string[], resolvedHostKey: string, source: string): Promise<string> {
    let bestUrl: string = urls[0];
    let bestLatency: number = -1;
    let bestPriority: number = 999;
    let results: Promise<ProbeCandidateResult>[] = [];
    for (let i: number = 0; i < urls.length; i++) {
      results.push(this.probeCandidate(urls[i], resolvedHostKey));
    }
    for (let i: number = 0; i < results.length; i++) {
      let result: ProbeCandidateResult = await results[i];
      let priority: number = getCandidatePriority(result.url);
      if (result.ok && result.latencyMs >= 0 &&
        (bestLatency < 0 || priority < bestPriority ||
          (priority === bestPriority && result.latencyMs < bestLatency))) {
        bestPriority = priority;
        bestLatency = result.latencyMs;
        bestUrl = result.url;
      }
    }
    if (bestLatency < 0) {
      hilog.error(DOMAIN, TAG, source + ': all probes failed, trying first candidate');
      return this.pickFallbackCandidate(urls);
    }
    hilog.info(DOMAIN, TAG, source + `: selected ${bestUrl} via probe (${bestLatency}ms)`);
    return bestUrl;
  }

  private hasRelayCredentials(): boolean {
    let hostEd25519PubKey: string = AppStorage.get<string>('hostEd25519PublicKey') || '';
    let hostId: string = AppStorage.get<string>('hostId') || '';
    return hostEd25519PubKey.length > 0 && hostId.length > 0;
  }

  private pickFallbackCandidate(urls: string[]): string {
    if (!this.hasRelayCredentials()) {
      for (let i: number = 0; i < urls.length; i++) {
        if (!isRelayClientUrl(urls[i])) {
          return urls[i];
        }
      }
    }
    return urls[0];
  }

  private doConnect(url: string): void {
    this.disconnectInternal();
    this.ws = webSocket.createWebSocket();
    let gen: number = ++this.wsGen;
    let connectNotified: boolean = false;
    let connectTimeout = setTimeout(() => {
      if (!connectNotified) {
        onConnectFailure('Connect timeout (10s)');
      }
    }, 10000);

    let onConnectFailure = (detail: string): void => {
      if (connectNotified) return;
      connectNotified = true;
      clearTimeout(connectTimeout);
      this.cancelWaitingHostTimer();
      hilog.error(DOMAIN, TAG, detail);
      ChatStore.connected = false;
      ChatStore.currentDeviceId = '';
      this.notifyState(false, detail);
      if (!this.intentionalClose && this.hostEverOnline) {
        this.scheduleReconnect(detail);
      } else {
        ChatStore.reconnectPhase = '';
        HostRuntimeStore.markOffline(this.targetHostKey, detail);
      }
    };

    this.ws.on('open', () => {
      if (gen !== this.wsGen) return;
      clearTimeout(connectTimeout);
      connectNotified = true;
      hilog.info(DOMAIN, TAG, 'websocket open: ' + url);
      ChatStore.connected = false;
      if (isRelayClientUrl(url)) {
        HostRuntimeStore.markWaitingHost(this.targetHostKey, url);
      } else {
        HostRuntimeStore.markConnecting(this.targetHostKey, url);
      }
      this.startWaitingHostTimer();
      // Auto-initiate E2EE for relay connections (URL contains targetHostId)
      if (isRelayClientUrl(url)) {
        this.initiateE2EE(url, gen);
      }
    });

    this.ws.on('message', (_err: BusinessError, data: string | ArrayBuffer) => {
      if (typeof data === 'string') {
        this.handleMessage(data);
      } else if (data instanceof ArrayBuffer) {
        let bytes: Uint8Array = new Uint8Array(data);
        if (bytes.length > 0 && (bytes[0] === 0x7B || bytes[0] === 0x22)) {
          let decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
          let raw: string = decoder.decodeToString(bytes);
          this.handleMessage(raw);
          return;
        }
        if (this._e2eeReady) {
          this.channel.decrypt(data).then((plainStr) => {
            this.handleMessage(plainStr);
          }).catch((err: Error) => {
            hilog.error(DOMAIN, TAG, 'decrypt failed: ' + JSON.stringify(err));
          });
        } else {
          // Before E2EE handshake, relay sends all frames as binary (opcode 0x02)
          // Convert ArrayBuffer to string for plaintext JSON handling
          let decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
          let raw: string = decoder.decodeToString(bytes);
          this.handleMessage(raw);
        }
      }
    });


    this.ws.on('close', () => {
      if (gen !== this.wsGen) return;
      if (!this.everConnected) {
        this.cancelWaitingHostTimer();
        ChatStore.connected = false;
        ChatStore.currentDeviceId = '';
        this.notifyState(false, 'Connection closed before host confirmation');
        if (!this.intentionalClose && this.hostEverOnline) {
          this.scheduleReconnect('Connection closed before host confirmation');
        } else {
          ChatStore.reconnectPhase = '';
          HostRuntimeStore.markOffline(this.targetHostKey, 'Connection closed before host confirmation');
        }
        return;
      }
      this.everConnected = false;
      hilog.info(DOMAIN, TAG, 'disconnected: ' + url);
      ChatStore.connected = false;
      ChatStore.currentDeviceId = '';
      this.cancelWaitingHostTimer();
      this.cancelBgTask();
      this.notifyState(false, '');
      if (!this.intentionalClose) {
        if (this.hostEverOnline) {
          if (ChatStore.bridgeSessionId.length > 0) {
            ChatStore.reconnectPhase = 'disconnected';
          }
          this.scheduleReconnect('WebSocket closed');
        } else {
          ChatStore.reconnectPhase = '';
          HostRuntimeStore.markOffline(this.targetHostKey, 'WebSocket closed before host confirmation');
        }
      }
    });

    this.ws.on('error', (err: BusinessError) => {
      if (gen !== this.wsGen) return;
      if (this.everConnected) {
        hilog.error(DOMAIN, TAG, 'post-connect error: ' + JSON.stringify(err));
        return;
      }
      if (connectNotified) {
        let detail: string = 'Connection error before host confirmation: ' + JSON.stringify(err);
        this.cancelWaitingHostTimer();
        ChatStore.connected = false;
        ChatStore.currentDeviceId = '';
        this.notifyState(false, detail);
        if (!this.intentionalClose && this.hostEverOnline) {
          this.scheduleReconnect(detail);
        } else {
          ChatStore.reconnectPhase = '';
          HostRuntimeStore.markOffline(this.targetHostKey, detail);
        }
        return;
      }
      onConnectFailure('Connection error: ' + JSON.stringify(err));
    });

    this.ws.connect(url, (err: BusinessError) => {
      if (gen !== this.wsGen) return;
      if (err) {
        onConnectFailure('Connect failed: ' + JSON.stringify(err));
      }
    });
  }

  private scheduleReconnect(reason: string = ''): void {
    if (this.intentionalClose || !this.lastUrl) return;
    this.cancelReconnect();
    this.reconnectAttempts++;
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts - 1), 30000);
    hilog.info(DOMAIN, TAG, 'reconnect in ' + delay.toString() + 'ms (attempt ' + this.reconnectAttempts.toString() + ')');
    if (ChatStore.bridgeSessionId.length > 0) {
      ChatStore.reconnectPhase = 'reconnecting';
    }
    ChatStore.reconnectAttempt = this.reconnectAttempts;
    HostRuntimeStore.markReconnecting(this.targetHostKey, this.reconnectAttempts, reason);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.reconnectUsingBestCandidate();
    }, delay);
  }

  private async reconnectUsingBestCandidate(): Promise<void> {
    if (this.intentionalClose || this.lastUrl.length === 0) return;
    let candidates: string[] = this.reconnectCandidates.length > 0 ? this.reconnectCandidates : [this.lastUrl];
    let bestUrl: string = await this.pickBestCandidate(candidates, this.targetHostKey, 'reconnect');
    if (this.intentionalClose) return;
    this.lastUrl = bestUrl;
    this.doConnect(bestUrl);
  }

  private cancelReconnect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private startWaitingHostTimer(): void {
    this.cancelWaitingHostTimer();
    this.waitingHostTimer = setTimeout(() => {
      this.waitingHostTimer = null;
      if (!this.everConnected && !ChatStore.connected) {
        hilog.info(DOMAIN, TAG, 'target host did not respond');
        ChatStore.reconnectPhase = '';
        HostRuntimeStore.markOffline(this.targetHostKey, 'target host did not respond');
        this.notifyState(false, 'target host did not respond');
      }
    }, 10000);
  }

  private cancelWaitingHostTimer(): void {
    if (this.waitingHostTimer !== null) {
      clearTimeout(this.waitingHostTimer);
      this.waitingHostTimer = null;
    }
  }

  private requestBgTask(): void {
    try {
      const info = backgroundTaskManager.requestSuspendDelay('Keep WebSocket alive', () => {
        hilog.info(DOMAIN, TAG, 'bg task about to expire');
      });
      this.suspendRequestId = info.requestId;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'bg task failed: ' + JSON.stringify(err));
    }
  }

  private cancelBgTask(): void {
    if (this.suspendRequestId !== null) {
      try {
        backgroundTaskManager.cancelSuspendDelay(this.suspendRequestId);
      } catch {}
      this.suspendRequestId = null;
    }
  }

  send(msg: ClientMessage): void {
    if (!this.ws) {
      return;
    }
    try {
      if (this._e2eeReady && this.channel.isReady()) {
        this.channel.encrypt(JSON.stringify(msg)).then((frame) => {
          this.ws?.send(frame);
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'encrypt failed: ' + JSON.stringify(err));
        });
      } else {
        this.ws.send(JSON.stringify(msg));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'send failed: ' + JSON.stringify(err));
    }

  }
  /** 发送控制消息（E2EE 握手/心跳等 text frame） */
  sendControl(type: string, payload: Record<string, Object>): void {
    if (!this.ws) return;
    try {
      let data: Record<string, Object> = {};
      data['type'] = type;
      if (type === 'e2ee_hello' && payload['ephemeralKey']) {
        data['channelId'] = String(payload['ephemeralKey']).slice(0, 16);
      }
      let keys: string[] = Object.keys(payload);
      for (let i: number = 0; i < keys.length; i++) {
        data[keys[i]] = payload[keys[i]] as Object;
      }
      this.ws.send(JSON.stringify(data));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'sendControl failed: ' + JSON.stringify(err));
    }
  }
  private async initiateE2EE(url: string, gen: number): Promise<void> {
    try {
      const hostEd25519PubKey: string = AppStorage.get<string>('hostEd25519PublicKey') || '';
      const hostId: string = AppStorage.get<string>('hostId') || '';
      if (!hostEd25519PubKey || !hostId) {
        hilog.error(DOMAIN, TAG, 'E2EE credentials missing, scan host QR again');
        return;
      }

      let ephKeyPair = await generateEphemeralKeyPair();
      let clientKeyPair = await getOrCreateClientKeyPair();
      let clientId: string = hostId + '_client_' + Date.now();
      this._e2eeClientId = clientId;

      let signPayload: string = hostId + ephKeyPair.publicKeyHex + clientId;
      let signature: string = await signWithClientKey(signPayload);

      let helloPayload: Record<string, Object> = {};
      helloPayload['protocolVersion'] = 1;
      helloPayload['clientId'] = clientId;
      helloPayload['clientPublicKey'] = clientKeyPair.publicKeyHex;
      helloPayload['ephemeralKey'] = ephKeyPair.publicKeyHex;
      helloPayload['hostId'] = hostId;
      helloPayload['signature'] = signature;
      this.sendControl('e2ee_hello', helloPayload);
      hilog.info(DOMAIN, TAG, 'E2EEHello sent');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'initiateE2EE failed: ' + JSON.stringify(err));
    }
  }

  disconnect(): void {
    this.intentionalClose = true;
    this.everConnected = false;
    this.hostEverOnline = false;
    this.cancelReconnect();
    this.cancelWaitingHostTimer();
    this.cancelBgTask();
    HostRuntimeStore.markOffline(this.targetHostKey, 'manual disconnect');
    ChatStore.reconnectPhase = '';
    this.disconnectInternal();
  }

  private disconnectInternal(): void {
    if (this.ws) {
      try {
        this.ws.close();
      } catch {}
      this.ws = null;
    }
    ChatStore.connected = false;
    ChatStore.currentDeviceId = '';
    this.cancelWaitingHostTimer();
    this.stopHeartbeatWatchdog();
  }

  onStateChange(cb: StateChangeCallback): void {
    this.stateListeners.push(cb);
  }
  onModelList(cb: ModelListCallback): void {
    this.modelListeners.push(cb);
  }
  onSessionList(cb: SessionListCallback): void {
    this.sessionListeners.push(cb);
  }
  onAcpUpdate(cb: AcpUpdateCallback): void {
    this.updateListeners.push(cb);
  }
  onAgentList(cb: AgentListCallback): void {
    this.agentListListeners.push(cb);
  }
  onError(cb: ErrorCallback): void {
    this.errorListeners.push(cb);
  }
  onSessionStarted(cb: EmptyCallback): void {
    this.sessionStartedListeners.push(cb);
  }

  onServerInfo(cb: EmptyCallback): void {
    this.serverInfoListeners.push(cb);
  }

  clearListeners(): void {
    this.stateListeners = [];
    this.modelListeners = [];
    this.sessionListeners = [];
    this.agentListListeners = [];
    this.errorListeners = [];
    this.sessionStartedListeners = [];
    this.serverInfoListeners = [];
  }

  sendPermissionResponse(optionId: string): void {
    if (!ChatStore.pendingPermission) return;
    let reqId: string = ChatStore.pendingPermission.requestId;
    let sessionId: string = ChatStore.bridgeSessionId;
    this.send({
      type: 'permission_response',
      sessionId: sessionId,
      requestId: reqId,
      outcome: 'selected',
      optionId: optionId,
    } as ClientMessage);
    ChatStore.pendingPermission = null;
  }

  private parsePermissionOptions(raw: Object | undefined): import('../model/ChatState').PermissionOption[] {
    if (!raw) return [];
    let arr: Array<Record<string, Object>> = raw as Array<Record<string, Object>>;
    let result: import('../model/ChatState').PermissionOption[] = [];
    for (let i = 0; i < arr.length; i++) {
      result.push({
        optionId: String(arr[i]['optionId']) || '',
        name: String(arr[i]['name']) || '',
        kind: String(arr[i]['kind']) || '',
      });
    }
    return result;
  }

  private notifyState(connected: boolean, detail: string = ''): void {
    for (let cb of this.stateListeners) {
      cb(connected, detail);
    }
  }

  private handleServerInfo(info: ServerInfoMessage): void {
    let hostname: string = info.hostname;
    let connectedUrl: string = this.lastUrl;
    if (connectedUrl.length === 0) return;
    this.persistHostIdentity(
      info.hostId || '',
      info.ecdhPublicKeyHex || '',
      info.ed25519PublicKeyHex || ''
    );
    let isRelayPairUrl: boolean = isRelayClientUrl(connectedUrl);
    let primaryUrl: string = toPrimaryConnectionUrl(connectedUrl);
    // Dedup: remove all existing devices with same hostId or same hostname
    let mergedUrls: string[] = [];
    for (let i: number = HostStore.devices.length - 1; i >= 0; i--) {
      let d = HostStore.devices[i];
      let match: boolean = false;
      if (info.hostId && d.hostId === info.hostId) {
        match = true;
      } else if (d.name === hostname) {
        // Same hostname = same device (regardless of hostId)
        match = true;
      }
      if (match) {
        for (let j: number = 0; j < d.urls.length; j++) {
          if (mergedUrls.indexOf(d.urls[j]) < 0) mergedUrls.push(d.urls[j]);
        }
        HostStore.removeDevice(i);
      }
    }
    addUniqueUrl(mergedUrls, primaryUrl);
    if (!isRelayPairUrl && info.ips) {
      let port: string = getUrlPort(connectedUrl);
      let scheme: string = getUrlScheme(connectedUrl);
      for (let i: number = 0; i < info.ips.length; i++) {
        addUniqueUrl(mergedUrls, buildWsUrlFromIp(info.ips[i], port, scheme));
      }
    }
    HostStore.addOrUpdateDevice({
      name: hostname,
      urls: mergedUrls,
      hostId: info.hostId,
      relayPin: info.relayPin,
      relayUrl: info.relayUrl,
    } as DeviceEntry);

    let actualHostKey: string = info.hostId || hostname;
    if (this.targetHostKey.length > 0 && this.targetHostKey !== actualHostKey) {
      HostRuntimeStore.mergeHostKey(this.targetHostKey, actualHostKey);
    }
    this.targetHostKey = actualHostKey;
    this.everConnected = true;
    this.hostEverOnline = true;
    this.cancelWaitingHostTimer();
    HostRuntimeStore.markOnline(actualHostKey, primaryUrl);

    ChatStore.connected = true;
    ChatStore.currentDeviceId = actualHostKey;
    ChatStore.reconnectAttempt = 0;
    this.reconnectAttempts = 0;
    this.notifyState(true, connectedUrl);
    this.cancelBgTask();
    this.requestBgTask();
    this.startHeartbeatWatchdog();
    ChatStore.pendingPermission = null;
    if (ChatStore.bridgeSessionId.length > 0 && ChatStore.lastMessageId.length > 0) {
      ChatStore.reconnectPhase = 'syncing';
      HostRuntimeStore.markSyncing(actualHostKey);
      this.send({
        type: 'sync_request',
        sessionId: ChatStore.bridgeSessionId,
        lastMessageId: ChatStore.lastMessageId,
      } as ClientMessage);
    } else {
      ChatStore.reconnectPhase = '';
    }
    saveHosts();
    for (let cb of this.serverInfoListeners) {
      cb();
    }
  }

  private persistHostIdentity(hostId: string, ecdhPublicKeyHex: string, ed25519PublicKeyHex: string): void {
    let storage = StorageService.getInstance();
    if (hostId.length > 0) {
      AppStorage.setOrCreate<string>('hostId', hostId);
      storage.putString(PrefsKeys.HOST_ID, hostId);
    }
    if (ecdhPublicKeyHex.length > 0) {
      AppStorage.setOrCreate<string>('serverHostPublicKey', ecdhPublicKeyHex);
      storage.putString(PrefsKeys.SERVER_HOST_PUBLIC_KEY, ecdhPublicKeyHex);
    }
    if (ed25519PublicKeyHex.length > 0) {
      AppStorage.setOrCreate<string>('hostEd25519PublicKey', ed25519PublicKeyHex);
      storage.putString(PrefsKeys.HOST_ED25519_PUBLIC_KEY, ed25519PublicKeyHex);
    }
  }

  private handleE2EEMessage(raw: string): void {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(raw);
    } catch { return; }
    let type: string = String(parsed['type'] || '');
    if (type === 'e2ee_ready') {
      let accepted: boolean = Boolean(parsed['accepted']);
      if (accepted) {
        hilog.info(DOMAIN, TAG, 'E2EE handshake completed');
        const ephHostHex = String(parsed['ephemeralKey'] || '');
        const hostSignature = String(parsed['signature'] || '');
        import('./CryptoHelper').then((module) => {
          module.finishE2EEHandshake(ephHostHex, hostSignature, this._e2eeClientId).then((res) => {
            if (res) {
              this._e2eeReady = true;
              this.setE2EEKey(res.aesKey, res.channelIdHex);
              hilog.info(DOMAIN, TAG, 'AES key established');
            }
          }).catch((err: Error) => hilog.error(DOMAIN, TAG, 'Handshake error: ' + JSON.stringify(err)));
        });
      } else {
        let error: string = String(parsed['error'] || 'unknown');
        hilog.error(DOMAIN, TAG, 'E2EE handshake rejected: ' + error);
        // Q6 grill: propagate specific failure reason to UI
        HostRuntimeStore.markError(this.targetHostKey, 'E2EE握手拒绝: ' + error);
        ChatStore.connected = false;
        this.notifyState(false, 'E2EE握手拒绝: ' + error);
      }
    }
  }

  // Set the AES key when handshake completes
  public setE2EEKey(key: Uint8Array, channelIdHex: string) {
    this.channel.setAesKey(key, channelIdHex);
  }

  // ── Heartbeat (Phase 2b) ─────────────────────────────────────────

  private startHeartbeatWatchdog(): void {
    this.lastHeartbeatReceived = Date.now();
    this.stopHeartbeatWatchdog();
    this.heartbeatWatchdog = setInterval(() => {
      if (Date.now() - this.lastHeartbeatReceived > this.HEARTBEAT_WATCHDOG_MS) {
        hilog.error(DOMAIN, TAG, 'Heartbeat timeout (45s), disconnecting');
        this.intentionalClose = false;
        this.disconnectInternal();
        if (ChatStore.bridgeSessionId.length > 0) {
          ChatStore.reconnectPhase = 'disconnected';
        }
        this.scheduleReconnect('Heartbeat timeout');
      }
    }, 15_000);

    // Active heartbeat sender (every 15s) - keep the connection alive
    this.heartbeatSender = setInterval(() => {
      if (ChatStore.connected) {
        let hbPayload: Record<string, Object> = {};
        hbPayload['ts'] = Date.now();
        this.sendControl('heartbeat', hbPayload);
      }
    }, 15_000);
  }

  private stopHeartbeatWatchdog(): void {
    if (this.heartbeatWatchdog !== null) {
      clearInterval(this.heartbeatWatchdog);
      this.heartbeatWatchdog = null;
    }
    if (this.heartbeatSender !== null) {
      clearInterval(this.heartbeatSender);
      this.heartbeatSender = null;
    }
  }

  private handleHeartbeat(payload: Record<string, Object>): void {
    this.lastHeartbeatReceived = Date.now();
    let channelId: string = String(payload['channelId'] || '');
    if (channelId.length > 0) {
      // E2EE channel heartbeat: server expects a pong to keep the channel alive.
      let hbPayload: Record<string, Object> = {};
      hbPayload['ts'] = payload['ts'];
      hbPayload['channelId'] = channelId;
      this.sendControl('heartbeat', hbPayload);
    }
  }


  private handleMessage(raw: string): void {
    raw = repairRelayJson(raw);
    this.lastHeartbeatReceived = Date.now();

    // Intercept heartbeat control messages before E2EE handling
    let isHeartbeat = (raw.indexOf('"heartbeat"') >= 0 && raw.indexOf('"ts"') >= 0) ||
                      (raw.indexOf('type:heartbeat') >= 0 && raw.indexOf('ts:') >= 0);
    if (isHeartbeat) {
      try {
        const hb: Record<string, Object> = JSON.parse(raw);
        if (hb['type'] === 'heartbeat') {
          this.handleHeartbeat(hb);
          return;
        }
      } catch {}
    }

    // E2EE handshake messages are intercepted at control level
    let isE2EE = (raw.indexOf('"e2ee_hello"') >= 0 || raw.indexOf('"e2ee_ready"') >= 0) ||
                 (raw.indexOf('type:e2ee_hello') >= 0 || raw.indexOf('type:e2ee_ready') >= 0);
    if (isE2EE) {
      this.handleE2EEMessage(raw);
      return;
    }


    let msg: ServerMessage;
    let rawSessions: Record<string, Object>[] | null = null;
    try {
      msg = JSON.parse(raw) as ServerMessage;
      // 从原始 JSON 提取 sessions 以访问 updatedAt（ServerMessage/sessions 类型不包含此字段）
      let rawStr: string = raw;
      let rawParsed: Record<string, Object> = JSON.parse(rawStr);
      let sessionsRaw = rawParsed['sessions'];
      if (sessionsRaw) {
        rawSessions = sessionsRaw as Record<string, Object>[];
      }
    } catch {
      return;
    }
    switch (msg.type) {
      case 'server_info':
        this.handleServerInfo(msg as ServerInfoMessage);
        break;
      case 'target_offline': {
        let offlineHostKey: string = msg.hostId || this.targetHostKey;
        hilog.info(DOMAIN, TAG, 'target_offline: ' + offlineHostKey);
        this.cancelWaitingHostTimer();
        ChatStore.connected = false;
        ChatStore.currentDeviceId = '';
        ChatStore.reconnectPhase = '';
        HostRuntimeStore.markOffline(offlineHostKey, 'target host offline');
        this.notifyState(false, 'target host offline');
        break;
      }
      case 'session_started':
        if (msg.sessionId !== undefined && msg.sessionId !== ChatStore.bridgeSessionId) {
          clearMessageId();
        }
        ChatStore.bridgeSessionId = msg.sessionId || '';
        if (msg.loadedSessionId) {
          ChatStore.acpSessionId = msg.loadedSessionId;
        } else {
          ChatStore.acpSessionId = '';
        }
        if (msg.model) {
          ChatStore.sessionCurrentModelId = msg.model;
          ChatStore.lastModelId = msg.model;
          StorageService.getInstance().putString(PrefsKeys.LAST_MODEL_ID, msg.model);
          if (ChatStore.agentType.length > 0 && WorkspaceStore.currentIndex >= 0 &&
              WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
            saveLastModelSelection(
              ChatStore.currentDeviceId || this.lastUrl,
              WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path,
              ChatStore.agentType,
              msg.model
            );
          }
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === msg.model) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
        if (msg.title) {
          ChatStore.sessionTitle = msg.title;
        }
        {
          let id = msg.loadedSessionId || msg.sessionId || '';
          let found = false;
          for (let i = 0; i < ChatStore.sessions.length; i++) {
            if (ChatStore.sessions[i].sessionId === id) {
              ChatStore.sessions[i].title = String(msg.title || ChatStore.sessions[i].title);
              found = true;
              break;
            }
          }
          if (!found) {
            let s = new ServerSession();
            s.sessionId = id;
            s.title = String(msg.title || '');
            ChatStore.sessions = [...ChatStore.sessions, s];
          }
        }
        ChatStore.loadingSession = false;
        for (let cb of this.sessionStartedListeners) {
          cb();
        }
        break;
      case 'agent_event':
        if (msg.event) {
          let messageId: string = msg.messageId || msg.event.messageId || '';
          if (messageId.length > 0 && hasProcessedMessage(messageId)) break;
          if (messageId.length > 0) {
            msg.event.messageId = messageId;
          }
          for (let cb of this.updateListeners) {
            cb(msg.event);
          }
          if (messageId.length > 0) {
            rememberMessageId(messageId);
          }
        }
        break;
      case 'turn_ended':
        ChatStore.turnActive = false;
        {
          let u: AcpUpdate = { sessionUpdate: 'turn_ended' };
          for (let cb of this.updateListeners) {
            cb(u);
          }
        }
        break;
      case 'model_list':
        ChatStore.loadingModels = false;
        ChatStore.models = msg.models || [];
        ChatStore.modes = msg.modes || [];
        if (ChatStore.sessionCurrentModelId) {
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === ChatStore.sessionCurrentModelId) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
        let hostId: string = ChatStore.currentDeviceId || this.lastUrl;
        let workspacePath: string = WorkspaceStore.currentIndex >= 0 &&
          WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length
          ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path
          : '';
        if (!ChatStore.sessionCurrentModelId && workspacePath.length > 0 &&
            (ChatStore.agentType || ChatStore.selectedAgentName).length > 0) {
          loadLastModelSelection(hostId, workspacePath, ChatStore.agentType || ChatStore.selectedAgentName)
            .then((lastModelId: string) => {
              if (lastModelId.length === 0) {
                return;
              }
              ChatStore.lastModelId = lastModelId;
              for (let i = 0; i < ChatStore.models.length; i++) {
                if (ChatStore.models[i].modelId === lastModelId) {
                  ChatStore.modelIndex = i;
                  break;
                }
              }
            });
        } else if (!ChatStore.sessionCurrentModelId && ChatStore.lastModelId.length > 0) {
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === ChatStore.lastModelId) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
        if (hostId.length > 0 && workspacePath.length > 0 && (ChatStore.agentType || ChatStore.selectedAgentName).length > 0) {
          saveWorkspaceModelCache(
            hostId,
            workspacePath,
            ChatStore.agentType || ChatStore.selectedAgentName,
            msg.models || [],
            msg.modes || []
          );
        }
        for (let cb of this.modelListeners) {
          cb(msg.models || [], msg.modes || []);
        }
        break;
      case 'session_list':
        let sessions: ServerSession[] = msg.sessions || [];
        let now: number = Date.now();
        if (rawSessions) {
          for (let i = 0; i < sessions.length && i < rawSessions.length; i++) {
            // opencode 返回 updatedAt (ISO 8601) 作为最后活跃时间
            let updatedAtStr: string = String(rawSessions[i]['updatedAt'] || '');
            if (updatedAtStr.length > 0) {
              let parsed: number = Date.parse(updatedAtStr);
              if (!isNaN(parsed)) {
                sessions[i].createdAt = parsed;
              }
            }
            if (!sessions[i].createdAt || sessions[i].createdAt <= 0) {
              sessions[i].createdAt = now;
            }
          }
        } else {
          for (let i = 0; i < sessions.length; i++) {
            if (!sessions[i].createdAt || sessions[i].createdAt <= 0) {
              sessions[i].createdAt = now;
            }
          }
        }
        ChatStore.sessions = sessions;
        ChatStore.loadingSession = false;
        if (ChatStore.agentType.length > 0 && WorkspaceStore.currentIndex >= 0 &&
            WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
          let cwd: string = WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path;
          saveWorkspaceSessionCache(ChatStore.currentDeviceId || this.lastUrl, cwd, sessions);
        }
        for (let cb of this.sessionListeners) {
          cb(sessions);
        }
        break;
      case 'agent_list':
        if (ChatStore.currentDeviceId.length > 0 && msg.agents) {
          DeviceAgentStore.saveAgents(ChatStore.currentDeviceId, msg.agents);
          saveAgentCache(ChatStore.currentDeviceId, msg.agents);
        }
        for (let cb of this.agentListListeners) {
          cb(msg.agents || []);
        }
        break;
      case 'error':
        for (let cb of this.errorListeners) {
          cb(String(msg.text || 'Unknown error'));
        }
        break;
      case 'permission_request':
        if (msg.requestId && msg.toolCall) {
          let toolCall: Record<string, Object> = msg.toolCall as Record<string, Object>;
          ChatStore.pendingPermission = {
            requestId: msg.requestId,
            toolCall: {
              toolCallId: String(toolCall['toolCallId']) || '',
              title: String(toolCall['title']) || '',
              kind: String(toolCall['kind']) || '',
            },
            options: this.parsePermissionOptions(msg.options),
          };
        }
        break;
      case 'config_option_updated':
        if (msg.configOptions) {
          ChatStore.configOptions = msg.configOptions;
        }
        break;
      case 'session_closed':
        if (msg.sessionId && msg.sessionId !== ChatStore.bridgeSessionId) {
          break;
        }
        ChatStore.bridgeSessionId = '';
        ChatStore.messages = [];
        ChatStore.planEntries = [];
        ChatStore.sessionTitle = '';
        ChatStore.configOptions = [];
        break;
      // Phase 3b: Cursor sync response (reconnect recovery)
      case 'sync_response': {
        let syncMsg: SyncResponseMessage = msg as SyncResponseMessage;
        let entries: Array<SyncResponseEntry> | undefined = syncMsg.entries;
        hilog.info(DOMAIN, TAG, 'sync_response: ' + (entries !== undefined ? String(entries.length) : '0') + ' entries');
        if (syncMsg.overflow === true) {
          for (let cb of this.errorListeners) {
            cb('部分断线输出已超出缓存，请重新加载会话查看完整历史');
          }
        }
        if (entries !== undefined) {
          for (let i = 0; i < entries.length; i++) {
            let entry: SyncResponseEntry = entries[i];
            let payload: AcpUpdate | undefined = entry.payload;
            let messageId: string = entry.messageId || payload?.messageId || '';
            if (messageId.length > 0 && hasProcessedMessage(messageId)) continue;
            if (payload !== undefined && payload.sessionUpdate !== undefined) {
              if (messageId.length > 0) {
                payload.messageId = messageId;
              }
              for (let cb of this.updateListeners) {
                cb(payload);
              }
              if (messageId.length > 0) {
                rememberMessageId(messageId);
              }
            }
          }
          // Phase transition: syncing → normal (complete)
          hilog.info(DOMAIN, TAG, 'sync_response: processed ' + String(entries.length) + ' entries');
        }
        ChatStore.reconnectPhase = '';
        if (this.targetHostKey.length > 0) {
          HostRuntimeStore.markOnline(this.targetHostKey, toPrimaryConnectionUrl(this.lastUrl));
        }
        break;
      }
      default:
        hilog.info(DOMAIN, TAG, 'unhandled: ' + msg.type);
        break;
    }
  }
}
