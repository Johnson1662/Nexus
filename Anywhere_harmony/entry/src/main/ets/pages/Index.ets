import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { HomeView } from '../feature/home/HomeView';
import { HostFilterBar } from '../feature/home/HostFilterBar';
import { AgentDetailView } from '../feature/agent/AgentDetailView';
import { SessionDetailView } from '../feature/session/SessionDetailView';
import { WorkspaceDetailView } from '../feature/workspace/WorkspaceDetailView';
import { WorkspaceListView } from '../feature/workspace/WorkspaceListView';
import { Colors, FontSize, Spacing, Radius, Duration } from '../constants/DesignTokens';
import { ChatStore, trimMessages } from '../common/model/ChatState';
import { WorkspaceStore, ServerSession, HostStore, DeviceEntry, WorkspaceInfo } from '../common/model/WorkspaceInfo';
import { HostRuntimeStore } from '../common/model/HostState';
import { MessageData } from '../common/model/MessageData';
import { WSClient, ProbeCandidateResult } from '../common/websocket/WSClient';
import { ClientMessage, AcpUpdate } from '../common/websocket/WSProtocol';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import {
  StorageService,
  PrefsKeys,
  loadWorkspaces,
  loadWorkspaceSessionCache,
  loadWorkspaceModelCache,
  loadLastAgentSelection,
  loadLastModelSelection,
  saveLastAgentSelection,
  saveHosts
} from '../services/StorageService';
import { ChatView } from '../feature/chat/ChatView';
import { SettingsPage } from '../feature/settings/SettingsView';
import { handleAcpUpdate } from '../common/model/MessageHandler';
import { DeviceAgentStore } from '../common/model/DeviceAgentStore';
import { getOrCreateClientKeyPair } from '../common/websocket/CryptoHelper';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'Index';
const DOMAIN: number = 0x0000;
const DEFAULT_RELAY_URL: string = 'ws://relay.anywhere12138.lat:12138';

@Entry
@Component
struct Index {
  private navStack: NavPathStack = new NavPathStack();
  private ws: WSClient = new WSClient();
  private wsCallbacksBound: boolean = false;
  private homeRouteReady: boolean = false;
  private serverInfoGen: number = 0;

  @State selectedWorkspaceIndex: number = 0;
  @State selectedSession: ServerSession = new ServerSession();
  @State selectedHostFilter: string = '';
  @State autoConnectAttempted: boolean = false;
  @State autoConnectRetryCount: number = 0;
  @State hostStatusRevision: number = 0;

  aboutToAppear(): void {
    AppStorage.setOrCreate('pref_thinking_expanded', true);
    AppStorage.setOrCreate('pref_toolcall_expanded', true);
    AppStorage.setOrCreate('selectedDeviceIndex', 0);
    this.ws.onAcpUpdate((update: AcpUpdate) => { handleAcpUpdate(update); });
    this.bindWsCallbacks();
    this.ensureHomeRoute();
    this.scheduleAutoConnect();
  }

  @Builder
  PagesMap(name: string) {
    if (name === 'home') {
      HdsNavDestination() {
        Column() {
          Column() {
            HostFilterBar({
              devices: HostStore.devices,
              selectedKey: this.selectedHostFilter,
              statusRevision: this.hostStatusRevision,
              onSelect: (key: string) => {
                hilog.info(DOMAIN, TAG, 'onSelect: key=' + key + ' currentDeviceId=' + ChatStore.currentDeviceId);
                this.selectedHostFilter = key;
                // Guard against reconnecting to the same host
                for (let i: number = 0; i < HostStore.devices.length; i++) {
                  let d: DeviceEntry = HostStore.devices[i];
                  if ((d.hostId && d.hostId === key) || d.name === key) {
                    let hostKey: string = d.hostId || d.name;
                    if (hostKey === ChatStore.currentDeviceId && ChatStore.connected) return;
                    this.connectSavedHost(i);
                    break;
                  }
                }
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(Colors.surface0)
          .padding({ top: 15, bottom: 18 })
          HomeView({
            onNavigateToAgentDetail: (index: number) => {
              AppStorage.setOrCreate('selectedDeviceIndex', index);
              this.navStack.pushPath({ name: 'agentDetail' });
            },
            onNavigateToSession: (session: ServerSession) => {
              this.loadSessionDetail(session);
            },
            onOpenWorkspace: (index: number) => {
              this.openWorkspaceDetail(index);
            },
            onOpenChat: (workspaceIndex: number) => {
              this.openChat(workspaceIndex);
            },
            onNewChat: () => {
              this.newChat();
            },
            onConnectHost: (url: string) => {
              this.connectToHostUrl(url);
            },
            onRefreshHostsAgents: () => {
              this.refreshAgents(true);
            },
            onNavigateToWorkspaceList: () => {
              this.navStack.pushPath({ name: 'workspaceList' });
            }
          }).layoutWeight(1)
        }
          .width('100%')
          .height('100%')
          .padding({ top: 42 })
      }
      .hideBackButton(true)
      .titleBar({
        content: {
          title: { mainTitle: 'Anywhere' },
          menu: {
            value: [
              {
                content: {
                  icon: $r('sys.symbol.plus'),
                  action: () => { this.scanAndConnectHost(); }
                }
              },
              {
                content: {
                  icon: $r('sys.symbol.gearshape'),
                  action: () => { this.navStack.pushPath({ name: 'settings' }); }
                }
              }
            ]
          }
        },
        style: {
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .mode(NavDestinationMode.STANDARD)
      .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
    } else if (name === 'workspaceDetail') {
      WorkspaceDetailView({
        workspaceIndex: this.selectedWorkspaceIndex,
        onBack: () => { this.navStack.pop(); },
        onSelectSession: (session: ServerSession) => {
          this.loadSessionDetail(session);
        },
        onNewSession: (workspaceIndex: number) => {
          this.openChat(workspaceIndex);
        }
      })
    } else if (name === 'workspaceList') {
      WorkspaceListView({
        onSelectWorkspace: (index: number) => {
          WorkspaceStore.currentIndex = index;
          this.selectedWorkspaceIndex = index;
          this.navStack.pushPath({ name: 'workspaceDetail' });
        },
        onNewSession: (workspaceIndex: number) => {
          this.openChat(workspaceIndex);
        }
      })
    } else if (name === 'agentDetail') {
      AgentDetailView({ deviceIndex: this.getSelectedDeviceIndex(), onBack: () => { this.navStack.pop(); } })
    } else if (name === 'sessionDetail') {
      SessionDetailView({
        session: this.selectedSession,
        onOpenChat: () => { this.navStack.replacePath({ name: 'chat' }); }
      })
    } else if (name === 'chat') {
      ChatView({
        onSendMessage: (t: string) => { this.sendMessage(t); },
        onRetry: (id: string, content: string) => { this.retryMessage(id, content); },
        onSelectAgent: (i: number) => { this.handleAgentSelection(i); },
        onSwitchModel: (i: number) => { this.handleModelSelection(i); },
        onSwitchMode: (i: number) => { this.handleModeSelection(i); },
        onSelectSession: (i: number) => { this.handleSessionPickerSelection(i); },
        onNewSession: () => { this.resetForNewChat(); },
        onWorkspaceSelect: (index: number) => { this.prepareWorkspace(index, false); },
        onPrefetchModels: () => { this.refreshModels(false); },
        onRefreshAgents: () => { this.refreshAgents(true); },
        onRefreshSessions: () => { this.refreshSessionsForWorkspace(WorkspaceStore.currentIndex, true); },
        onPermissionResponse: (optionId: string) => { this.ws.sendPermissionResponse(optionId); },
        onNavigateToSettings: () => { this.navStack.pushPath({ name: 'settings' }); }
      })
    } else if (name === 'settings') {
      SettingsPage({
        onConnect: (url: string) => { this.connectToHostUrl(url); },
        onConnectHost: (index: number) => { this.connectSavedHost(index); },
        onDeleteHost: (index: number) => {
          HostStore.removeDevice(index);
          saveHosts();
        },
        onScan: () => { this.scanAndConnectHost(); }
      })
    }
  }


  ensureHomeRoute(): void {
    if (this.homeRouteReady || this.navStack.size() > 0) {
      return;
    }
    this.homeRouteReady = true;
    this.navStack.pushPath({ name: 'home' }, false);
  }

  bindWsCallbacks(forceRebind: boolean = false): void {
    if (this.wsCallbacksBound && !forceRebind) {
      return;
    }
    if (forceRebind) {
      this.ws.clearListeners();
      this.ws.onAcpUpdate((update: AcpUpdate) => { handleAcpUpdate(update); });
    }
    this.ws.onStateChange((connected: boolean, detail: string) => {
      ChatStore.connected = connected;
      this.bumpHostStatusRevision();
      if (connected) {
        if (detail.length > 0) {
          AppStorage.setOrCreate<string>('serverUrl', detail);
          StorageService.getInstance().putString(PrefsKeys.SERVER_URL, detail);
        }
      } else {
        // Connection lost — clear loading state so UI doesn't freeze
        AppStorage.setOrCreate('loadingWorkspaces', false);
      }
    });
    this.ws.onServerInfo(async () => {
      const gen = ++this.serverInfoGen;
      this.bumpHostStatusRevision();
      // Sync selectedHostFilter to the actually connected host
      let connectedHostKey: string = ChatStore.currentDeviceId;
      hilog.info(DOMAIN, TAG, 'onServerInfo: connectedHostKey=' + connectedHostKey +
        ' selectedHostFilter_before=' + this.selectedHostFilter);
      if (connectedHostKey.length > 0) {
        this.selectedHostFilter = connectedHostKey;
      }
      // Ensure workspace list is loaded for this host before preparing
      let url: string = AppStorage.get<string>('serverUrl') || '';
      hilog.info(DOMAIN, TAG, 'onServerInfo: hostKey=' + connectedHostKey + ' url=' + url +
        ' workspaces_before=' + WorkspaceStore.workspaces.length);
      if (url.length > 0) {
        await loadWorkspaces(url, connectedHostKey);
      }
      if (gen !== this.serverInfoGen) return; // stale — a newer onServerInfo already fired
      AppStorage.setOrCreate('loadingWorkspaces', false);
      hilog.info(DOMAIN, TAG, 'onServerInfo: workspaces_after=' + WorkspaceStore.workspaces.length);
      this.refreshAgents(false);
      if (WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
        this.prepareWorkspace(WorkspaceStore.currentIndex, false);
      }
    });
    this.ws.onAgentList((_agents) => {
      let workspacePath: string = this.getWorkspacePath(WorkspaceStore.currentIndex);
      if ((ChatStore.selectedAgentName || ChatStore.agentType).length === 0 && workspacePath.length > 0) {
        loadLastAgentSelection(this.getCurrentHostKey(), workspacePath).then((agentName: string) => {
          if (agentName.length > 0) {
            this.selectAgent(agentName, false);
          }
        });
      }
    });
    this.ws.onError((text: string) => {
      ChatStore.turnActive = false;
      let m = new MessageData('assistant', 'Error: ' + text, 'text');
      ChatStore.messages = [...ChatStore.messages, m];
    });
    this.wsCallbacksBound = true;
  }

  bumpHostStatusRevision(): void {
    this.hostStatusRevision += 1;
  }

  /** probe 结果缓存：hostKey → bestUrl，避免 connectBest 重复 probe */
  private probeResults: Map<string, string> = new Map();
  private hostsLoaded: boolean = false;

  scheduleAutoConnect(): void {
    if (this.autoConnectAttempted || ChatStore.connected) {
      return;
    }
    this.autoConnectAttempted = true;
    // 等 HostStore.devices 加载完成（避免启动竞态）
    this.warmupAndConnect();
  }

  private async warmupAndConnect(): Promise<void> {
    // 等待设备列表加载
    for (let retry: number = 0; retry < 10; retry++) {
      if (HostStore.devices.length > 0) break;
      hilog.info(DOMAIN, TAG, `warmup: waiting for devices (${retry + 1}/10), count=${HostStore.devices.length}`);
      await new Promise<void>((resolve) => setTimeout(resolve, 300));
    }
    if (HostStore.devices.length === 0) {
      hilog.error(DOMAIN, TAG, 'warmup: no devices loaded after 3s, abort');
      return;
    }
    hilog.info(DOMAIN, TAG, `warmup: ${HostStore.devices.length} devices loaded, probing...`);

    // Step 1: 并发探测所有设备 → 缓存最佳 URL + 更新 HostRuntimeStore
    await this.probeAllHosts();

    // Step 2: 连接目标设备（用 probe 结果，不重复探测）
    this.tryAutoConnect();
  }

  private async probeAllHosts(): Promise<void> {
    let probes: Promise<void>[] = [];
    for (let i: number = 0; i < HostStore.devices.length; i++) {
      probes.push(this.probeOneDevice(HostStore.devices[i]));
    }
    await Promise.all(probes);
    this.bumpHostStatusRevision();
  }

  private async probeOneDevice(device: DeviceEntry): Promise<void> {
    let hostKey: string = device.hostId || device.name;
    if (hostKey.length === 0) return;
    let candidates: string[] = this.getConnectCandidates(device, '');
    if (candidates.length === 0) return;
    // 并发探测所有候选地址，取最快成功的
    let bestResult: ProbeCandidateResult | null = null;
    let results: Promise<ProbeCandidateResult>[] = [];
    for (let j: number = 0; j < candidates.length; j++) {
      results.push(this.ws.probeCandidate(candidates[j], hostKey));
    }
    let settled: ProbeCandidateResult[] = await Promise.all(results);
    for (let j: number = 0; j < settled.length; j++) {
      if (settled[j].ok && (bestResult === null || settled[j].latencyMs < bestResult.latencyMs)) {
        bestResult = settled[j];
      }
    }
    if (bestResult !== null) {
      // 只缓存 probe 结果，不标 CONNECTING
      // CONNECTING 由实际连接操作（connectSelected/doConnect）设置
      // 非目标设备保持 UNKNOWN（灰色），避免卡在橙色
      this.probeResults.set(hostKey, bestResult.url);
    } else {
      // probe 全失败 → 标离线
      HostRuntimeStore.markOffline(hostKey, 'startup probe failed');
    }
  }

  tryAutoConnect(): void {
    if (ChatStore.connected) return;
    if (HostStore.devices.length === 0) return;

    let serverUrl: string = AppStorage.get<string>('serverUrl') || '';
    let targetDevice: DeviceEntry | null = null;
    if (serverUrl.length > 0) {
      for (let i: number = 0; i < HostStore.devices.length; i++) {
        if (HostStore.devices[i].urls.indexOf(serverUrl) >= 0) {
          targetDevice = HostStore.devices[i];
          break;
        }
      }
    }
    if (targetDevice === null && HostStore.devices.length > 0) {
      targetDevice = HostStore.devices[0];
    }
    if (targetDevice === null) return;

    let hostKey: string = targetDevice.hostId || targetDevice.name;
    // 只用 probe 成功的 URL；probe 失败的候选不再尝试（probeAllHosts 已标 offline）
    let bestUrl: string | undefined = this.probeResults.get(hostKey);
    if (bestUrl && bestUrl.length > 0) {
      this.ws.connectWithCandidates(bestUrl, [bestUrl], hostKey);
    }
    // else: probeAllHosts 已 markOffline，不再调 connectBest 重复探测
  }

  getConnectCandidates(device: DeviceEntry, preferredUrl: string): string[] {
    let result: string[] = [];
    this.addCandidateUrl(result, preferredUrl);
    for (let i: number = 0; i < device.urls.length; i++) {
      let url: string = device.urls[i];
      this.addCandidateUrl(result, this.repairSavedRelayUrl(url, device.hostId || ''));
      this.addCandidateUrl(result, url);
    }
    this.addRelayCandidate(result, device.relayUrl || DEFAULT_RELAY_URL, device.hostId || '');
    return result;
  }

  addCandidateUrl(urls: string[], url: string): void {
    if (this.isAutoDirectIpv6Url(url)) {
      return;
    }
    if (url.length > 0 && urls.indexOf(url) < 0) {
      urls.push(url);
    }
  }

  isAutoDirectIpv6Url(url: string): boolean {
    return url.startsWith('ws://[') || url.startsWith('wss://[');
  }

  addRelayCandidate(urls: string[], relayUrl: string, hostId: string): void {
    if (relayUrl.length === 0 || hostId.length === 0) {
      return;
    }
    this.addCandidateUrl(urls, this.buildRelayClientUrl(relayUrl, hostId));
  }

  buildRelayClientUrl(relayUrl: string, hostId: string): string {
    if (relayUrl.indexOf('targetHostId=') >= 0) {
      return relayUrl;
    }
    let separator: string = relayUrl.indexOf('?') >= 0 ? '&' : '?';
    return relayUrl + separator + 'role=client&targetHostId=' + hostId;
  }

  getTargetHostIdFromUrl(url: string): string {
    let marker: string = 'targetHostId=';
    let start: number = url.indexOf(marker);
    if (start < 0) return '';
    start += marker.length;
    let end: number = url.indexOf('&', start);
    if (end < 0) end = url.length;
    return url.substring(start, end);
  }

  getHostKeyForUrl(url: string): string {
    let targetHostId: string = this.getTargetHostIdFromUrl(url);
    if (targetHostId.length > 0) return targetHostId;
    for (let i: number = 0; i < HostStore.devices.length; i++) {
      let device: DeviceEntry = HostStore.devices[i];
      for (let j: number = 0; j < device.urls.length; j++) {
        if (device.urls[j] === url || url.indexOf(device.urls[j]) >= 0 || device.urls[j].indexOf(url) >= 0) {
          return device.hostId || device.name;
        }
      }
    }
    return url;
  }

  repairSavedRelayUrl(url: string, hostId: string): string {
    if (url.length === 0 || hostId.length === 0) {
      return url;
    }
    if (url.indexOf('targetHostId=') >= 0) {
      return this.isKnownRelayUrl(url) ? url : '';
    }
    if (!this.isKnownRelayUrl(url)) {
      return url;
    }
    return this.buildRelayClientUrl(url, hostId);
  }

  isKnownRelayUrl(url: string): boolean {
    return url.indexOf('relay.anywhere12138.lat') >= 0 || url.indexOf('35.212.155.17') >= 0;
  }

  getSelectedDeviceIndex(): number {
    let v = AppStorage.get<number>('selectedDeviceIndex');
    return v !== undefined && v !== null ? v : 0;
  }

  getCurrentHostKey(): string {
    if (ChatStore.currentDeviceId.length > 0) {
      return ChatStore.currentDeviceId;
    }
    let serverUrl: string = AppStorage.get<string>('serverUrl') || '';
    if (serverUrl.length > 0) {
      for (let i: number = 0; i < HostStore.devices.length; i++) {
        if (HostStore.devices[i].urls.indexOf(serverUrl) >= 0) {
          return HostStore.devices[i].hostId || HostStore.devices[i].name;
        }
      }
      return serverUrl;
    }
    return '';
  }

  normalizeServerUrl(raw: string): string {
    let url: string = raw.trim();
    if (url.length === 0) return '';
    if (url.startsWith('http://') && url.length > 7) {
      url = 'ws://' + url.substring(7);
    } else if (url.startsWith('https://') && url.length > 8) {
      url = 'wss://' + url.substring(8);
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'ws://' + url;
    }
    if (url.endsWith('/') && url.length > 6) {
      url = url.substring(0, url.length - 1);
    }
    let queryStart: number = url.indexOf('?');
    let query: string = '';
    if (queryStart >= 0) {
      query = url.substring(queryStart);
      url = url.substring(0, queryStart);
    }
    let schemeEnd: number = url.indexOf('://');
    if (schemeEnd >= 0) {
      let scheme: string = url.substring(0, schemeEnd + 3);
      let rest: string = url.substring(schemeEnd + 3);
      if (rest.length > 0) {
        let portSep: number = rest.lastIndexOf(':');
        if (portSep >= 0) {
          let host: string = rest.substring(0, portSep);
          let port: string = rest.substring(portSep + 1);
          if (host.indexOf(':') >= 0 && !host.startsWith('[') && port.length > 0) {
            url = scheme + '[' + host + ']:' + port;
          }
        } else if (rest.indexOf(':') >= 0 && !rest.startsWith('[')) {
          url = scheme + '[' + rest + ']';
        }
      }
    }
    return url + query;
  }

  decodeBase64Url(encoded: string): string {
    let b64: string = '';
    for (let i: number = 0; i < encoded.length; i++) {
      let c: string = encoded[i];
      if (c === '-') b64 += '+';
      else if (c === '_') b64 += '/';
      else b64 += c;
    }
    while (b64.length % 4 !== 0) b64 += '=';
    let chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out: number[] = [];
    for (let i: number = 0; i + 3 < b64.length; i += 4) {
      let a: number = chars.indexOf(b64[i]);
      let b: number = chars.indexOf(b64[i + 1]);
      let c: number = chars.indexOf(b64[i + 2]);
      let d: number = chars.indexOf(b64[i + 3]);
      if (a < 0 || b < 0) break;
      out.push((a << 2) | (b >> 4));
      if (c >= 0) {
        out.push(((b & 0x0F) << 4) | (c >> 2));
        if (d >= 0) {
          out.push(((c & 0x03) << 6) | d);
        }
      }
    }
    let result: string = '';
    for (let i: number = 0; i < out.length; i++) {
      result += String.fromCharCode(out[i]);
    }
    return result;
  }

  async parsePairingPayload(value: string): Promise<string> {
    let offerIdx: number = value.indexOf('#offer=');
    if (offerIdx < 0) {
      return value;
    }
    let encoded: string = value.substring(offerIdx + 7);
    try {
      let jsonStr: string = this.decodeBase64Url(encoded);
      let offer = JSON.parse(jsonStr) as Record<string, Object>;
      let hostId: string = String(offer['hostId'] || '');
      let relayUrl: string = String(offer['relayUrl'] || '');
      let ecdhPublicKeyHex: string = String(offer['ecdhPublicKeyHex'] || '');
      let ed25519PublicKeyHex: string = String(offer['ed25519PublicKeyHex'] || '');
      if (hostId.length > 0 && relayUrl.length > 0 && ecdhPublicKeyHex.length > 0 && ed25519PublicKeyHex.length > 0) {
        await getOrCreateClientKeyPair();
        AppStorage.setOrCreate<string>('serverHostPublicKey', ecdhPublicKeyHex);
        AppStorage.setOrCreate<string>('hostEd25519PublicKey', ed25519PublicKeyHex);
        AppStorage.setOrCreate<string>('hostId', hostId);
        let storage = StorageService.getInstance();
        await storage.putString(PrefsKeys.HOST_ID, hostId);
        await storage.putString(PrefsKeys.SERVER_HOST_PUBLIC_KEY, ecdhPublicKeyHex);
        await storage.putString(PrefsKeys.HOST_ED25519_PUBLIC_KEY, ed25519PublicKeyHex);
        return relayUrl + '?role=client&targetHostId=' + hostId;
      }
    } catch {}
    return value;
  }

  connectToHostUrl(rawUrl: string): void {
    let url: string = this.normalizeServerUrl(rawUrl);
    if (url.length === 0) {
      return;
    }
    AppStorage.setOrCreate<string>('serverUrl', url);
    StorageService.getInstance().putString(PrefsKeys.SERVER_URL, url);
    ChatStore.selectedAgentName = '';
    ChatStore.agentType = '';
    ChatStore.models = [];
    ChatStore.modes = [];
    ChatStore.sessions = [];
    this.ws.connect(url, this.getHostKeyForUrl(url));
  }

  connectSavedHost(index: number): void {
    if (index < 0 || index >= HostStore.devices.length) {
      hilog.error(DOMAIN, TAG, 'connectSavedHost: invalid index ' + index);
      return;
    }
    let device: DeviceEntry = HostStore.devices[index];
    let serverUrl: string = AppStorage.get<string>('serverUrl') || '';
    let candidates: string[] = this.getConnectCandidates(device, serverUrl);
    let hostKey: string = device.hostId || device.name;
    hilog.info(DOMAIN, TAG, 'connectSavedHost: index=' + index + ' hostKey=' + hostKey +
      ' candidates=' + candidates.length + ' currentDeviceId=' + ChatStore.currentDeviceId);
    ChatStore.selectedAgentName = '';
    ChatStore.agentType = '';
    ChatStore.models = [];
    ChatStore.modes = [];
    ChatStore.sessions = [];
    AppStorage.setOrCreate('loadingWorkspaces', true);
    WorkspaceStore.workspaces = [];
    if (candidates.length > 0) {
      // 始终走 connectBest 确保 relay 连接前通过 probe 验证主机在线
      this.ws.connectBest(candidates, hostKey);
    } else {
      hilog.error(DOMAIN, TAG, 'connectSavedHost: no candidates for ' + hostKey);
    }
  }

  async scanAndConnectHost(): Promise<void> {
    try {
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      let context = (this.getUIContext()).getHostContext() as common.UIAbilityContext;
      let result = await scanBarcode.startScanForResult(context, options);
      if (result.originalValue) {
        let targetUrl: string = await this.parsePairingPayload(result.originalValue);
        this.connectToHostUrl(targetUrl);
      }
    } catch (err) {
      ChatStore.reconnectPhase = 'scan_failed';
    }
  }

  getWorkspacePath(index: number): string {
    if (index >= 0 && index < WorkspaceStore.workspaces.length) {
      return WorkspaceStore.workspaces[index].path;
    }
    return '';
  }

  openChat(workspaceIndex: number): void {
    if (workspaceIndex >= 0 && workspaceIndex < WorkspaceStore.workspaces.length) {
      WorkspaceStore.currentIndex = workspaceIndex;
      this.selectedWorkspaceIndex = workspaceIndex;
    } else if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
      this.selectedWorkspaceIndex = 0;
    }
    this.prepareWorkspace(WorkspaceStore.currentIndex, false);
    this.resetForNewChat();
    this.navStack.pushPath({ name: 'chat' });
  }

  newChat(): void {
    AppStorage.setOrCreate('chatShowWorkspacePicker', true);
    this.resetForNewChat();
    if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
    }
    if (WorkspaceStore.currentIndex >= 0) {
      this.prepareWorkspace(WorkspaceStore.currentIndex, false);
    }
    this.navStack.pushPath({ name: 'chat' });
  }

  openWorkspaceDetail(index: number): void {
    this.selectedWorkspaceIndex = index;
    WorkspaceStore.currentIndex = index;
    this.prepareWorkspace(index, false);
    this.navStack.pushPath({ name: 'workspaceDetail' });
  }

  resetForNewChat(): void {
    ChatStore.bridgeSessionId = '';
    ChatStore.acpSessionId = '';
    ChatStore.sessionTitle = '';
    ChatStore.loadingSession = false;
    ChatStore.turnActive = false;
    ChatStore.messages = [];
    ChatStore.planEntries = [];
    ChatStore.streamingThinking = '';
    ChatStore.streamingText = '';
    ChatStore.lastUsage = null;
  }

  prepareWorkspace(workspaceIndex: number, forceNetwork: boolean): void {
    if (workspaceIndex < 0 || workspaceIndex >= WorkspaceStore.workspaces.length) {
      return;
    }
    WorkspaceStore.currentIndex = workspaceIndex;
    this.selectedWorkspaceIndex = workspaceIndex;
    let hostKey: string = this.getCurrentHostKey();
    let workspacePath: string = this.getWorkspacePath(workspaceIndex);
    hilog.info(DOMAIN, TAG, 'prepareWorkspace: index=' + workspaceIndex + ' path=' + workspacePath + ' force=' + forceNetwork +
      ' connected=' + ChatStore.connected + ' agentType=' + ChatStore.agentType);
    loadWorkspaceSessionCache(hostKey, workspacePath).then((cached) => {
      hilog.info(DOMAIN, TAG, 'prepareWorkspace cache: present=' + (cached !== null) + ' count=' + ((cached !== null) ? cached.sessions.length : 0));
      if (!forceNetwork && cached !== null && cached.sessions.length > 0) {
        ChatStore.sessions = this.normalizeSessionTimes(cached.sessions);
      }
    });
    loadLastAgentSelection(hostKey, workspacePath).then((agentName: string) => {
      hilog.info(DOMAIN, TAG, 'loadLastAgentSelection: agent=' + (agentName.length > 0 ? agentName : '(empty)'));
      if (agentName.length > 0) {
        this.selectAgent(agentName, false);
      }
    });
    this.refreshSessionsForWorkspace(workspaceIndex, forceNetwork);
  }

  selectAgent(agentName: string, forceRefreshModels: boolean): void {
    hilog.info(DOMAIN, TAG, 'selectAgent: agent=' + agentName + ' forceModels=' + forceRefreshModels);
    ChatStore.selectedAgentName = agentName;
    ChatStore.agentType = agentName;
    AppStorage.setOrCreate<string>('lastAgent', agentName);
    StorageService.getInstance().putString(PrefsKeys.LAST_AGENT, agentName);
    let hostKey: string = this.getCurrentHostKey();
    let workspacePath: string = this.getWorkspacePath(WorkspaceStore.currentIndex);
    saveLastAgentSelection(hostKey, workspacePath, agentName);
    loadWorkspaceModelCache(hostKey, workspacePath, agentName).then((cached) => {
      if (!forceRefreshModels && cached !== null) {
        ChatStore.models = cached.models;
        ChatStore.modes = cached.modes;
        loadLastModelSelection(hostKey, workspacePath, agentName).then((lastModelId: string) => {
          if (lastModelId.length > 0) {
            ChatStore.lastModelId = lastModelId;
            for (let i: number = 0; i < ChatStore.models.length; i++) {
              if (ChatStore.models[i].modelId === lastModelId) {
                ChatStore.modelIndex = i;
                break;
              }
            }
          }
        });
      }
      this.refreshModels(forceRefreshModels);
      // Agent 切换后始终从服务端拉取最新 session，不依赖缓存
      this.refreshSessionsForWorkspace(WorkspaceStore.currentIndex, true);
    });
  }

  refreshAgents(force: boolean): void {
    if (!ChatStore.connected) {
      return;
    }
    let hostKey: string = this.getCurrentHostKey();
    if (!force && DeviceAgentStore.getAgents(hostKey).length > 0) {
      return;
    }
    this.ws.send({ type: 'list_agents' } as ClientMessage);
  }

  refreshModels(force: boolean): void {
    if (!ChatStore.connected || ChatStore.agentType.length === 0) {
      return;
    }
    ChatStore.loadingModels = true;
    let hostKey: string = this.getCurrentHostKey();
    let workspacePath: string = this.getWorkspacePath(WorkspaceStore.currentIndex);
    if (!force) {
      loadWorkspaceModelCache(hostKey, workspacePath, ChatStore.agentType).then((cached) => {
        if (cached !== null) {
          ChatStore.models = cached.models;
          ChatStore.modes = cached.modes;
          ChatStore.loadingModels = false;
        } else {
          this.ws.send({ type: 'list_models', agent: ChatStore.agentType } as ClientMessage);
        }
      });
      return;
    }
    this.ws.send({ type: 'list_models', agent: ChatStore.agentType } as ClientMessage);
  }

  refreshSessionsForWorkspace(workspaceIndex: number, forceNetwork: boolean): void {
    let workspacePath: string = this.getWorkspacePath(workspaceIndex);
    if (workspacePath.length === 0) {
      return;
    }
    let hostKey: string = this.getCurrentHostKey();
    if (!forceNetwork) {
      loadWorkspaceSessionCache(hostKey, workspacePath).then((cached) => {
        if (cached !== null && cached.sessions.length > 0) {
          hilog.info(DOMAIN, TAG, 'refreshSessions: using cache count=' + cached.sessions.length);
          ChatStore.sessions = this.normalizeSessionTimes(cached.sessions);
        } else if (ChatStore.connected && ChatStore.agentType.length > 0) {
          hilog.info(DOMAIN, TAG, 'refreshSessions: sending list_sessions agent=' + ChatStore.agentType);
          this.ws.send({
            type: 'list_sessions',
            cwd: workspacePath,
            agent: ChatStore.agentType
          } as ClientMessage);
        } else {
          hilog.info(DOMAIN, TAG, 'refreshSessions: cache miss, cannot fetch connected=' + ChatStore.connected +
            ' agentType="' + ChatStore.agentType + '"');
        }
      });
      return;
    }
    if (ChatStore.connected && ChatStore.agentType.length > 0) {
      hilog.info(DOMAIN, TAG, 'refreshSessions(force): sending list_sessions agent=' + ChatStore.agentType);
      this.ws.send({
        type: 'list_sessions',
        cwd: workspacePath,
        agent: ChatStore.agentType
      } as ClientMessage);
    } else {
      hilog.info(DOMAIN, TAG, 'refreshSessions(force): cannot fetch connected=' + ChatStore.connected +
        ' agentType="' + ChatStore.agentType + '"');
    }
  }

  /** 确保会话时间戳有效，NaN/undefined/0→当前时间 */
  normalizeSessionTimes(sessions: ServerSession[]): ServerSession[] {
    let now: number = Date.now();
    for (let i: number = 0; i < sessions.length; i++) {
      if (!sessions[i].createdAt || sessions[i].createdAt <= 0) {
        sessions[i].createdAt = now;
      }
    }
    return sessions;
  }

  loadSessionDetail(session: ServerSession): void {
    this.selectedSession = session;
    this.loadSessionIntoStore(session);
    this.navStack.pushPath({ name: 'sessionDetail' });
  }

  loadSessionIntoStore(session: ServerSession): void {
    ChatStore.loadingSession = true;
    ChatStore.messages = [];
    ChatStore.planEntries = [];
    ChatStore.streamingThinking = '';
    ChatStore.streamingText = '';
    ChatStore.lastUsage = null;
    ChatStore.sessionTitle = session.title || '';
    if (ChatStore.connected && ChatStore.agentType.length > 0) {
      this.ws.send({
        type: 'load_session',
        sessionId: session.sessionId,
        cwd: session.cwd || this.getWorkspacePath(WorkspaceStore.currentIndex),
        agent: ChatStore.agentType
      } as ClientMessage);
    } else {
      ChatStore.loadingSession = false;
    }
  }

  handleSessionPickerSelection(index: number): void {
    let actualIndex: number = index - 1;
    if (actualIndex >= 0 && actualIndex < ChatStore.sessions.length) {
      this.loadSessionIntoStore(ChatStore.sessions[actualIndex]);
    }
  }

  handleAgentSelection(index: number): void {
    let actualIndex: number = index - 1;
    let agents = DeviceAgentStore.getAgents(this.getCurrentHostKey());
    if (actualIndex >= 0 && actualIndex < agents.length) {
      this.selectAgent(agents[actualIndex].name, false);
    }
  }

  handleModelSelection(index: number): void {
    let actualIndex: number = index - 1;
    if (actualIndex < 0 || actualIndex >= ChatStore.models.length) {
      return;
    }
    ChatStore.modelIndex = actualIndex;
    ChatStore.lastModelId = ChatStore.models[actualIndex].modelId;
    if (ChatStore.bridgeSessionId.length > 0) {
      this.ws.send({
        type: 'switch_model',
        sessionId: ChatStore.bridgeSessionId,
        model: ChatStore.models[actualIndex].modelId
      } as ClientMessage);
    }
  }

  handleModeSelection(index: number): void {
    let actualIndex: number = index - 1;
    if (actualIndex < 0 || actualIndex >= ChatStore.modes.length || ChatStore.bridgeSessionId.length === 0) {
      return;
    }
    ChatStore.modeIndex = actualIndex;
    this.ws.send({
      type: 'set_mode',
      sessionId: ChatStore.bridgeSessionId,
      modeId: ChatStore.modes[actualIndex].value
    } as ClientMessage);
  }

  sendMessage(text: string, retryId?: string): void {
    if (text === '__cancel__') {
      if (ChatStore.bridgeSessionId) {
        this.ws.send({ type: 'cancel', sessionId: ChatStore.bridgeSessionId } as ClientMessage);
      }
      ChatStore.turnActive = false;
      return;
    }
    if (!ChatStore.connected) {
      ChatStore.turnActive = false;
      let failedMessage = new MessageData('user', text, 'text');
      failedMessage.sendStatus = 'failed';
      ChatStore.messages = [...ChatStore.messages, failedMessage];
      return;
    }
    ChatStore.messages = [...ChatStore.messages, new MessageData('user', text, 'text')];
    trimMessages();
    ChatStore.turnActive = true;
    if (ChatStore.bridgeSessionId) {
      this.ws.send({ type: 'input', sessionId: ChatStore.bridgeSessionId, text: text } as ClientMessage);
    } else {
      this.ws.send({
        type: 'start',
        agent: ChatStore.agentType,
        prompt: text,
        cwd: this.getWorkspacePath(WorkspaceStore.currentIndex),
        model: ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length
          ? ChatStore.models[ChatStore.modelIndex].modelId : ''
      } as ClientMessage);
    }
  }

  retryMessage(id: string, content: string): void {
    this.sendMessage(content, id);
  }

  build() {
    Navigation(this.navStack) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.surface0)
    }
    .navDestination(this.PagesMap)
    .hideNavBar(true)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface1)
    .mode(NavigationMode.Stack)
  }
}
