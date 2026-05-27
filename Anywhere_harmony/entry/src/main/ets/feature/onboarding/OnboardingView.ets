import { Colors, FontSize, Spacing, Radius, Duration, Shadow } from '../../constants/DesignTokens';
import { ChatStore, ModelItem, ModeItem } from '../../common/model/ChatState';
import { WorkspaceStore, HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { WSClient } from '../../common/websocket/WSClient';
import { ClientMessage, AgentInfo } from '../../common/websocket/WSProtocol';
import { MessageData } from '../../common/model/MessageData';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { StorageService, PrefsKeys, loadWorkspaces, saveHosts, loadModelCache } from '../../services/StorageService';
import { getOrCreateClientKeyPair, signWithClientKey } from '../../common/websocket/CryptoHelper';

interface OnboardingCallbacks {
  onNavigateToWorkspaceSelect: () => void;
}

@Component
export struct OnboardingView {
  @State connecting: boolean = false;
  @State connectingDeviceName: string = '';
  @State connectError: string = '';
  @State discoveredAgents: AgentInfo[] = [];
  @StorageLink('serverUrl') serverUrl: string = 'ws://192.168.137.1:12138';
  @State iconScale: number = 1.0;
  @State connectedViaSavedDevice: boolean = false;

  ws: WSClient = new WSClient();
  callbacks: OnboardingCallbacks = { onNavigateToWorkspaceSelect: () => {} };

  @State showSavedServers: boolean = true;

  aboutToAppear() {
    setTimeout(() => {
      this.iconScale = 1.08;
    }, 100);
  }

  aboutToDisappear(): void {
    this.iconScale = 1.0;
  }

  getDeviceForUrl(url: string): DeviceEntry | null {
    for (let i = 0; i < HostStore.devices.length; i++) {
      let urls: string[] = HostStore.devices[i].urls;
      for (let j = 0; j < urls.length; j++) {
        if (urls[j] === url) return HostStore.devices[i];
      }
    }
    return null;
  }

  getCurrentServerName(): string {
    // Try to find device by URL (strips query params for QR relay URLs)
    let lookupUrl: string = this.serverUrl;
    let qIdx: number = lookupUrl.indexOf('?');
    if (qIdx >= 0) {
      lookupUrl = lookupUrl.substring(0, qIdx);
    }
    let device: DeviceEntry | null = this.getDeviceForUrl(lookupUrl);
    if (device !== null && device.name.length > 0) {
      return device.name;
    }
    return this.extractIpPort(this.serverUrl);
  }

  extractIpPort(url: string): string {
    let schemeEnd: number = url.indexOf('://');
    if (schemeEnd >= 0) {
      return url.substring(schemeEnd + 3);
    }
    return url;
  }

  deleteHost(index: number): void {
    HostStore.removeDevice(index);
    saveHosts();
  }

  selectHost(device: DeviceEntry): void {
    if (device.urls.length > 0) {
      this.serverUrl = device.urls[0];
    }
  }

  getFirstLetter(agent: AgentInfo): string {
    return (agent.title || agent.name).substring(0, 1).toUpperCase();
  }

  getAgentIconUrl(agent: AgentInfo): string {
    let name = (agent.name || '').toLowerCase();
    let src = (agent.source || '').toLowerCase();

    // Map agents to their official website favicons via Google
    if (name.includes('codex')) return 'https://www.google.com/s2/favicons?domain=chatgpt.com&sz=64';
    if (name.includes('opencode')) return 'https://www.google.com/s2/favicons?domain=opencode.ai&sz=64';
    if (name.includes('omp') || name.includes('oh-my-pi')) return 'https://www.google.com/s2/favicons?domain=omp.sh&sz=64';
    if (name.includes('hermes') || name.includes('nous')) return 'https://www.google.com/s2/favicons?domain=nousresearch.com&sz=64';
    if (name.includes('kiro')) return 'https://www.google.com/s2/favicons?domain=kiro.dev&sz=64';
    if (name.includes('claude') || name.includes('anthropic')) return 'https://www.google.com/s2/favicons?domain=claude.ai&sz=64';
    if (name.includes('gemini')) return 'https://www.google.com/s2/favicons?domain=geminicli.com&sz=64';
    if (name.includes('gpt') || name.includes('openai') || name.includes('chatgpt')) return 'https://www.google.com/s2/favicons?domain=openai.com&sz=64';
    if (name.includes('deepseek')) return 'https://www.google.com/s2/favicons?domain=deepseek.com&sz=64';
    if (name.includes('copilot') || name.includes('github')) return 'https://www.google.com/s2/favicons?domain=github.com&sz=64';
    if (name.includes('cursor')) return 'https://www.google.com/s2/favicons?domain=cursor.com&sz=64';
    if (name.includes('bolt') || name.includes('bolt.new')) return 'https://www.google.com/s2/favicons?domain=bolt.new&sz=64';

    // Try to extract domain from source path for unknown agents
    let match = src.match(/github\.com\/([^\/]+)/);
    if (match !== null && match.length > 1) {
      return 'https://www.google.com/s2/favicons?domain=github.com&sz=64&url=https://github.com/' + match[1];
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
    // Preserve query parameters through port/IPv6 normalization
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

  tryConnect(device?: DeviceEntry): void {
    let url: string = this.normalizeServerUrl(this.serverUrl);
    if (!device && url.length === 0) {
      this.connectError = '请输入服务器地址';
      return;
    }
    if (!device) {
      this.serverUrl = url;
      AppStorage.setOrCreate<string>('serverUrl', url);
      StorageService.getInstance().putString(PrefsKeys.SERVER_URL, url);
    }
    // 连接中先显示主机名（探测阶段），非设备场景显示 IP
    if (device && device.name.length > 0) {
      this.connectedViaSavedDevice = true;
      this.connectingDeviceName = device.name;
    } else {
      this.connectedViaSavedDevice = false;
      this.connectingDeviceName = this.extractIpPort(url);
    }
    // Defer workspace loading until server_info arrives so hostId/url merge is available
    this.ws.clearListeners();
    this.connecting = true;
    this.connectError = '';
    this.discoveredAgents = [];
    ChatStore.selectedAgentName = '';
    this.ws.onStateChange((v: boolean, detail: string) => {
      ChatStore.connected = v;
      if (!v) {
        if (detail.length === 0) {
          this.connecting = false;
          this.connectingDeviceName = '';
          return;
        }
        this.connectError = detail;
        this.connecting = false;
        this.connectingDeviceName = '';
      } else {
        this.connectError = '';
        this.connectingDeviceName = '';
        if (device && detail.length > 0) {
          // connectBest found a responsive URL, persist it
          this.serverUrl = detail;
          AppStorage.setOrCreate<string>('serverUrl', detail);
          StorageService.getInstance().putString(PrefsKeys.SERVER_URL, detail);
        }
        if (ChatStore.selectedAgentName.length > 0 && ChatStore.messages.length > 0) {
          this.connecting = false;
          this.ws.send({ type: 'start', agent: ChatStore.selectedAgentName } as ClientMessage);
        } else if (ChatStore.selectedAgentName.length === 0) {
          this.ws.send({ type: 'list_agents' } as ClientMessage);
        }
      }
    });
    this.ws.onAgentList((agents: AgentInfo[]) => {
      this.connecting = false;
      if (agents.length > 0) {
        this.connectError = '';
        animateTo({ duration: 100 }, () => {
          this.discoveredAgents = agents;
        });
      } else {
        this.discoveredAgents = [];
        this.connectError = 'No ACP agents discovered.';
      }
    });
    this.ws.onModelList((models: ModelItem[], modes: ModeItem[]) => {
      ChatStore.models = models;
      ChatStore.modes = modes;
      if (ChatStore.sessionCurrentModelId) {
        for (let i = 0; i < models.length; i++) {
          if (models[i].modelId === ChatStore.sessionCurrentModelId) {
            ChatStore.modelIndex = i;
            break;
          }
        }
      }
    });
    this.ws.onSessionList((sessions: ServerSession[]) => { ChatStore.sessions = sessions; });
    this.ws.onError((text: string) => {
      ChatStore.turnActive = false;
      let m = new MessageData('assistant', 'Error: ' + text, 'text');
      ChatStore.messages = [...ChatStore.messages, m];
    });
    if (device) {
      this.ws.connectBest(device.urls);
    } else {
      this.ws.connect(url);
    }
  }

  selectAgent(agent: AgentInfo): void {
    ChatStore.selectedAgentName = agent.name;
    ChatStore.agentType = agent.name;
    AppStorage.setOrCreate<string>('lastAgent', agent.name);
    StorageService.getInstance().putString(PrefsKeys.LAST_AGENT, agent.name);
    ChatStore.messages = [];
    ChatStore.planEntries = [];
    ChatStore.sessionId = '';
    // Load cached models immediately for instant display
    loadModelCache(agent.name).then((cached) => {
      if (cached !== null) {
        ChatStore.models = cached.models;
        ChatStore.modes = cached.modes;
        if (ChatStore.lastModelId.length > 0) {
          for (let i = 0; i < cached.models.length; i++) {
            if (cached.models[i].modelId === ChatStore.lastModelId) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
      }
    });
    // Refresh model list once from server — server caches this per agent to avoid temp sessions
    this.ws.send({ type: 'list_models' } as ClientMessage);
    this.callbacks.onNavigateToWorkspaceSelect();
  }


  async startScan(): Promise<void> {
    try {
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };

      let context = getContext() as common.UIAbilityContext;
      let result = await scanBarcode.startScanForResult(context, options);
      if (result.originalValue) {
        let val: string = result.originalValue;

        // New format: anywhere://pair/#offer=<base64url>
        let offerIdx: number = val.indexOf('#offer=');
        if (offerIdx >= 0) {
          let encoded: string = val.substring(offerIdx + 7);
          // Decode base64url -> base64
          let b64: string = '';
          for (let i: number = 0; i < encoded.length; i++) {
            let c: string = encoded[i];
            if (c === '-') b64 += '+';
            else if (c === '_') b64 += '/';
            else b64 += c;
          }
          while (b64.length % 4 !== 0) b64 += '=';
          // Decode base64 to bytes
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
          let jsonStr: string = '';
          for (let i: number = 0; i < out.length; i++) {
            jsonStr += String.fromCharCode(out[i]);
          }
          try {
            let offer = JSON.parse(jsonStr) as Record<string, string>;
            if (offer.v && offer.hostId && offer.ecdhPublicKeyHex && offer.ed25519PublicKeyHex && offer.relayUrl) {
              let keyPair = await getOrCreateClientKeyPair();
              AppStorage.setOrCreate<string>('serverHostPublicKey', offer.ecdhPublicKeyHex);
              AppStorage.setOrCreate<string>('hostEd25519PublicKey', offer.ed25519PublicKeyHex);
              AppStorage.setOrCreate<string>('hostId', offer.hostId);
              this.serverUrl = offer.relayUrl + '?role=client&targetHostId=' + offer.hostId;
              this.tryConnect();
            } else {
              this.serverUrl = val;
              this.tryConnect();
            }
          } catch {
            this.serverUrl = val;
            this.tryConnect();
          }
        } else {
          this.serverUrl = val;
          this.tryConnect();
        }
      }
    } catch (e) {
      this.connectError = 'Scan failed: ' + JSON.stringify(e);
    }
  }

  getErrorBg(message: string): string {
    if (message.indexOf('限流') >= 0 || message.indexOf('rate') >= 0) return '#FEF3C7';
    if (message.indexOf('超时') >= 0 || message.indexOf('timeout') >= 0) return '#F3F4F6';
    return '#FEE2E2';
  }

  getErrorFg(message: string): string {
    if (message.indexOf('限流') >= 0 || message.indexOf('rate') >= 0) return '#92400E';
    if (message.indexOf('超时') >= 0 || message.indexOf('timeout') >= 0) return '#4B5563';
    return '#991B1B';
  }

  getErrorIcon(message: string): Resource {
    if (message.indexOf('限流') >= 0 || message.indexOf('rate') >= 0 ||
        message.indexOf('超时') >= 0 || message.indexOf('timeout') >= 0) {
      return $r('sys.symbol.clock');
    }
    return $r('sys.symbol.xmark_circle');
  }

  @Builder ClassifiedErrorBox(message: string) {
    Row() {
      SymbolGlyph(this.getErrorIcon(message))
        .fontSize(14).fontColor([this.getErrorFg(message)])
        .margin({ right: Spacing.sm })
      Text(message)
        .fontSize(13).fontColor(this.getErrorFg(message))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
    .backgroundColor(this.getErrorBg(message))
    .borderRadius(Radius.md)
    .margin({ top: Spacing.md })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Scroll() {
          Column() {
            // HERO
            Column() {
              Image($r('app.media.anywhere_logo'))
                .width(60).height(60)
                .fillColor(Colors.accent)
                .margin({ bottom: Spacing.lg })
                .scale({ x: this.iconScale, y: this.iconScale })
                .animation({ duration: 2500, curve: Curve.EaseInOut, playMode: PlayMode.Alternate, iterations: -1 })

Text('Anywhere')
  .fontSize(36)
  .fontWeight(FontWeight.Bolder)
  .fontColor(Colors.foreground)
  .fontFamily('serif')
  .letterSpacing(-1.2)
  .margin({ bottom: Spacing.xxs })

              Text('Seamlessly connected AI workspace.')
                .fontSize(15)
                .fontColor(Colors.foregroundMuted)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .margin({ top: ChatStore.connected ? 30 : 100, bottom: ChatStore.connected ? 30 : 50 })
            .animation({ duration: Duration.slow, curve: Curve.FastOutSlowIn })

            // CONNECTION
            Column() {
                if (ChatStore.connected) {
                  // 连上后的连接栏 — 显示主机名 — IP:端口
                  Row() {
                    Circle().width(8).height(8).fill(Colors.success).margin({ left: 16, right: 10 })
                    Text(this.getCurrentServerName())
                      .fontSize(14).fontColor(Colors.foreground)
                      .fontWeight(FontWeight.Medium)
                      .layoutWeight(1)
                    Button('断开')
                      .fontSize(13).fontColor(Colors.foregroundMuted).backgroundColor(Color.Transparent)
                      .fontWeight(FontWeight.Medium)
                      .margin({ right: 8 })
                      .onClick(() => {
                        ChatStore.connected = false;
                        this.connectedViaSavedDevice = false;
                        this.ws.disconnect();
                      })
                  }
                  .width('100%').height(52)
                  .backgroundColor(Colors.surface0)
                  .borderRadius(26)
                  .shadow(Shadow.sm)
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
                } else if (this.connecting) {
                  // 连接中 — 显示主机名 + 加载动画，无红字
                  Row() {
                    LoadingProgress().width(22).height(22).color(Colors.accent).margin({ left: 16, right: 10 })
                    Text(this.connectingDeviceName.length > 0 ? '正在连接 ' + this.connectingDeviceName + '…' : '正在连接…')
                      .fontSize(14).fontColor(Colors.foregroundMuted)
                      .fontWeight(FontWeight.Medium)
                      .layoutWeight(1)
                  }
                  .width('100%').height(52)
                  .backgroundColor(Colors.surface0)
                  .borderRadius(26)
                  .shadow(Shadow.sm)
                  .transition(TransitionEffect.OPACITY)
                } else {
                  Row() {
                    TextInput({ text: this.serverUrl, placeholder: 'Bridge WS URL or IP:Port' })
                      .layoutWeight(1)
                      .height(52)
                      .backgroundColor(Color.Transparent)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .padding({ left: 20 })
                      .onChange((val: string) => { this.serverUrl = val })
                      .enabled(!this.connecting)
                      .onSubmit(() => { this.tryConnect() })

                    Button() {
                      Text('扫码')
                        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(Colors.accent)
                    }
                    .type(ButtonType.Circle)
                    .width(44).height(44)
                    .backgroundColor(Colors.surface1)
                    .margin({ right: 4 })
                    .onClick(() => { this.startScan() })


                    Button() {
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(22).fontWeight(FontWeight.Bold).fontColor([Color.White])
                    }
                    .type(ButtonType.Circle)
                    .width(44).height(44)
                    .backgroundColor(this.serverUrl.length > 0 ? Colors.accent : Colors.border)
                    .margin({ right: 4 })
                    .enabled(this.serverUrl.length > 0)
                    .onClick(() => { this.tryConnect() })
                    .animation({ duration: Duration.normal })
                  }
                  .width('100%').height(52)
                  .backgroundColor(Colors.surface0)
                  .borderRadius(26)
                  .shadow(Shadow.md)
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
                }

                if (this.connectError.length > 0) {
                  this.ClassifiedErrorBox(this.connectError)
                }
            }
            .width('100%')
            .padding({ left: Spacing.xxl, right: Spacing.xxl })

            // SAVED SERVERS
            Column() {
              Row() {
                Text('SAVED SERVERS')
                  .fontSize(11).fontColor(Colors.foregroundLight)
                  .fontWeight(FontWeight.Bold)
                  .letterSpacing(2)
                Blank()
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(16).fontColor([Colors.foregroundLight])
                  .margin({ left: Spacing.sm })
                  .rotate({ angle: this.showSavedServers ? 180 : 0 })
                  .animation({ duration: Duration.normal })
                  .onClick(() => { this.showSavedServers = !this.showSavedServers })
              }
              .width('100%').margin({ bottom: Spacing.md })
              .padding({ left: Spacing.md })

              if (this.showSavedServers) {
                if (HostStore.devices.length === 0) {
                  Row() {
                    Text('No saved servers yet')
                      .fontSize(13).fontColor(Colors.foregroundLight)
                      .padding({ left: Spacing.md })
                  }
                  .width('100%')
                  .transition(TransitionEffect.OPACITY)
                } else {
                  ForEach(HostStore.devices, (device: DeviceEntry, index: number) => {
                    Row() {
                      SymbolGlyph($r('sys.symbol.ohos_wifi'))
                        .fontSize(18).fontColor([device.urls.indexOf(this.serverUrl) >= 0 ? Colors.accent : Colors.foregroundMuted])
                        .margin({ right: Spacing.md })
                      Column() {
                        Row() {
                          Text(device.name)
                            .fontSize(14).fontColor(device.urls.indexOf(this.serverUrl) >= 0 ? Colors.accent : Colors.foreground)
                            .fontWeight(device.urls.indexOf(this.serverUrl) >= 0 ? FontWeight.Medium : FontWeight.Normal)
                            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          if (device.urls.indexOf(this.serverUrl) >= 0) {
                            SymbolGlyph($r('sys.symbol.checkmark'))
                              .fontSize(14).fontColor([Colors.accent])
                              .margin({ left: Spacing.sm })
                          }
                        }
                        .onClick(() => {
                          this.selectHost(device);
                          if (!ChatStore.connected) {
                            this.connecting = true;
                            this.tryConnect(device);
                          }
                        })
                        if (device.urls.length > 1) {
                          Text(device.urls.length + ' addresses')
                            .fontSize(11).fontColor(Colors.foregroundMuted)
                        }
                      }
                      .alignItems(HorizontalAlign.Start).layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
                    .backgroundColor(Colors.surface0)
                    .borderRadius(Radius.md)
                    .margin({ bottom: Spacing.xs })
                    .gesture(
                      LongPressGesture({ repeat: false, duration: 600 })
                        .onAction(() => { this.deleteHost(index) })
                    )
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
                    .animation({ duration: Duration.normal, curve: Curve.EaseOut, delay: index * 30 })
                  }, (device: DeviceEntry) => device.name)
                }

              }
            }
            .width('100%')
            .padding({ left: Spacing.xl, right: Spacing.xl })
            .margin({ top: Spacing.lg })
            .transition(TransitionEffect.OPACITY)

            // AGENTS
            if (ChatStore.connected) {
              if (this.connecting && this.discoveredAgents.length === 0) {
                Column() {
                  LoadingProgress().width(32).height(32).color(Colors.foregroundMuted)
                  Text('Discovering agents...')
                    .fontSize(14).fontColor(Colors.foregroundMuted)
                    .margin({ top: Spacing.md })
                }
                .width('100%').height(120)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .transition(TransitionEffect.OPACITY)
              } else if (this.discoveredAgents.length > 0) {
                Column() {
                  Text('AVAILABLE AGENTS')
                    .fontSize(11).fontColor(Colors.foregroundLight)
                    .fontWeight(FontWeight.Bold)
                    .letterSpacing(2)
                    .width('100%').margin({ bottom: Spacing.md })
                    .padding({ left: Spacing.md })

                  ForEach(this.discoveredAgents, (agent: AgentInfo, index: number) => {
                    Row() {
                      Stack() {
                        Circle().width(44).height(44).fill(Colors.surface1)
                        Text(this.getFirstLetter(agent))
                          .fontSize(18).fontWeight(FontWeight.Bolder).fontColor(Colors.accent)
                        Image(this.getAgentIconUrl(agent))
                          .width(44).height(44)
                          .borderRadius(22)
                          .objectFit(ImageFit.Cover)
                          .visibility(this.getAgentIconUrl(agent).length > 0 ? Visibility.Visible : Visibility.None)
                      }
                      .margin({ right: Spacing.lg })

                      Column() {
                        Text(agent.title || agent.name)
                          .fontSize(16).fontColor(Colors.foreground)
                          .fontWeight(FontWeight.Medium)
                        if (agent.title && agent.title !== agent.name) {
                          Text(agent.name)
                            .fontSize(12).fontColor(Colors.foregroundMuted)
                            .margin({ top: 2 })
                        }
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(16).fontColor([Colors.foregroundLight])
                    }
                    .width('100%')
                    .padding(Spacing.lg)
                    .backgroundColor(Colors.surface0)
                    .borderRadius(Radius.xl)
                    .shadow(Shadow.sm)
                    .margin({ bottom: Spacing.md })
                    .onClick(() => { this.selectAgent(agent) })
                    .transition(
                      TransitionEffect.OPACITY
                        .combine(TransitionEffect.translate({ y: 20 }))
                        .animation({ duration: 400, curve: Curve.EaseOut, delay: index * 60 })
                    )
                  }, (agent: AgentInfo) => agent.name)
                }
                .width('100%')
                .padding({ left: Spacing.xl, right: Spacing.xl })
                .margin({ top: Spacing.xxl })
                .transition(TransitionEffect.OPACITY)
              }
            }
          }
          .width('100%')
          .padding({ bottom: Spacing.xxxl * 2 })
        }
        .width('100%').height('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%').height('100%')
      .backgroundColor('#FAFAFA')
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
