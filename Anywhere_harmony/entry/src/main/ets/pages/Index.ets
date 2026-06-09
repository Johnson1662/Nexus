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
import { MessageData } from '../common/model/MessageData';
import { WSClient } from '../common/websocket/WSClient';
import { ClientMessage, AcpUpdate } from '../common/websocket/WSProtocol';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import {
  StorageService,
  PrefsKeys,
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

const DEFAULT_RELAY_URL: string = 'ws://relay.anywhere12138.lat:12138';

@Entry
@Component
struct Index {
  private navStack: NavPathStack = new NavPathStack();
  private ws: WSClient = new WSClient();
  private wsCallbacksBound: boolean = false;
  private homeRouteReady: boolean = false;

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
                this.selectedHostFilter = key;
                this.refreshAgents(false);
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
            onOpenWorkspace: (index: number) => {
              this.openWorkspaceDetail(index);
            },
            onOpenChat: (workspaceIndex: number) => {
              this.openChat(workspaceIndex);
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
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
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
      SessionDetailView({ session: this.selectedSession })
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
        onRefreshAgents: () => { this.refreshAgents(true); },
        onRefreshModels: () => { this.refreshModels(true); },
        onRefreshSessions: () => { this.refreshSessionsForWorkspace(WorkspaceStore.currentIndex, true); },
        onPermissionResponse: (optionId: string) => { this.ws.sendPermissionResponse(optionId); },
        onNavigateToSettings: () => { this.navStack.pushPath({ name: 'settings' }); }
      })
    } else if (name === 'settings') {
      SettingsPage({
        onConnect: (url: string) => { this.connectToHostUrl(url); },
        onDeleteHost: (index: number) => {
          HostStore.removeDevice(index);
          saveHosts();
        },
        onScan: () => { this.scanAndConnectHost(); }
      })
    }
  }
  @Builder
  HostFilterChips() {
    HostFilterBar({
      devices: HostStore.devices,
      selectedKey: this.selectedHostFilter,
      statusRevision: this.hostStatusRevision,
      onSelect: (key: string) => { this.selectedHostFilter = key; }
    })
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
      }
    });
    this.ws.onServerInfo(() => {
      this.bumpHostStatusRevision();
      this.refreshAgents(false);
      if (WorkspaceStore.currentIndex >= 0) {
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

  scheduleAutoConnect(): void {
    if (this.autoConnectAttempted || ChatStore.connected) {
      return;
    }
    this.autoConnectAttempted = true;
    this.tryAutoConnect();
  }

  tryAutoConnect(): void {
    if (ChatStore.connected) {
      return;
    }
    if (HostStore.devices.length === 0) {
      if (this.autoConnectRetryCount < 6) {
        this.autoConnectRetryCount += 1;
        setTimeout(() => { this.tryAutoConnect(); }, 400);
      }
      return;
    }
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
    if (targetDevice === null) {
      return;
    }
    let candidates: string[] = this.getConnectCandidates(targetDevice, serverUrl);
    let hostKey: string = targetDevice.hostId || targetDevice.name;
    if (candidates.length > 1) {
      this.ws.connectBest(candidates, hostKey);
    } else if (candidates.length === 1) {
      this.ws.connect(candidates[0], hostKey);
    }
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
    this.addCandidateUrl(result, 'ws://192.168.137.1:12138');
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

  async scanAndConnectHost(): Promise<void> {
    try {
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      let context = (this.getUIContext() as UIContext).getHostContext() as common.UIAbilityContext;
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
    loadWorkspaceSessionCache(hostKey, workspacePath).then((cached) => {
      if (!forceNetwork && cached !== null && cached.sessions.length > 0) {
        ChatStore.sessions = this.normalizeSessionTimes(cached.sessions);
      }
    });
    loadLastAgentSelection(hostKey, workspacePath).then((agentName: string) => {
      if (agentName.length > 0) {
        this.selectAgent(agentName, false);
      }
    });
    this.refreshSessionsForWorkspace(workspaceIndex, forceNetwork);
  }

  selectAgent(agentName: string, forceRefreshModels: boolean): void {
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
      this.refreshSessionsForWorkspace(WorkspaceStore.currentIndex, false);
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
    let hostKey: string = this.getCurrentHostKey();
    let workspacePath: string = this.getWorkspacePath(WorkspaceStore.currentIndex);
    if (!force) {
      loadWorkspaceModelCache(hostKey, workspacePath, ChatStore.agentType).then((cached) => {
        if (cached !== null) {
          ChatStore.models = cached.models;
          ChatStore.modes = cached.modes;
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
          ChatStore.sessions = this.normalizeSessionTimes(cached.sessions);
        } else if (ChatStore.connected && ChatStore.agentType.length > 0) {
          this.ws.send({
            type: 'list_sessions',
            cwd: workspacePath,
            agent: ChatStore.agentType
          } as ClientMessage);
        }
      });
      return;
    }
    if (ChatStore.connected && ChatStore.agentType.length > 0) {
      this.ws.send({
        type: 'list_sessions',
        cwd: workspacePath,
        agent: ChatStore.agentType
      } as ClientMessage);
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
