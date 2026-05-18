import { Colors, FontSize, Spacing, Radius, Duration, Shadow } from '../../constants/DesignTokens';
import { ChatStore, ModelItem, ModeItem } from '../../common/model/ChatState';
import { WorkspaceStore } from '../../common/model/WorkspaceInfo';
import { WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { WSClient } from '../../common/websocket/WSClient';
import { ClientMessage, AcpUpdate, AgentInfo } from '../../common/websocket/WSProtocol';
import { MessageData } from '../../common/model/MessageData';
import { StorageService, PrefsKeys } from '../../services/StorageService';

interface OnboardingCallbacks {
  onNavigateToWorkspaceSelect: () => void;
  onWsClientReady: (ws: WSClient) => void;
}

@Component
export struct OnboardingView {
  @State connecting: boolean = false;
  @State connectError: string = '';
  @State discoveredAgents: AgentInfo[] = [];
  @StorageLink('serverUrl') serverUrl: string = 'ws://100.111.77.50:12138';
  @State iconScale: number = 1.0;

  private ws: WSClient = new WSClient();
  callbacks: OnboardingCallbacks = { onNavigateToWorkspaceSelect: () => {}, onWsClientReady: () => {} };

  aboutToAppear() {
    setTimeout(() => {
      this.iconScale = 1.08;
    }, 100);
  }

  getFirstLetter(agent: AgentInfo): string {
    return (agent.title || agent.name).substring(0, 1).toUpperCase();
  }

  getAgentIconUrl(agent: AgentInfo): string {
    let name = (agent.name || '').toLowerCase();
    let src = (agent.source || '').toLowerCase();

    // Map agents to their official website favicons via Google
    if (name.includes('opencode')) return 'https://www.google.com/s2/favicons?domain=opencode.ai&sz=64';
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

  tryConnect(): void {
    AppStorage.setOrCreate<string>('serverUrl', this.serverUrl);
    StorageService.getInstance().putString(PrefsKeys.SERVER_URL, this.serverUrl);
    this.ws.clearListeners();
    this.connecting = true;
    this.connectError = '';
    this.discoveredAgents = [];
    ChatStore.selectedAgentName = '';
    this.ws.onStateChange((v: boolean) => {
      ChatStore.connected = v;
      if (!v) {
        if (!this.connecting && this.connectError.length === 0) {
          if (ChatStore.selectedAgentName.length > 0 && ChatStore.messages.length > 0) {
          } else {
            this.connectError = 'Could not connect. Bridge server unavailable.';
          }
        }
        this.connecting = false;
      } else {
        this.connectError = '';
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
    this.ws.onAcpUpdate((update: AcpUpdate) => { this.handleUpdate(update); });
    this.ws.onError((text: string) => {
      ChatStore.turnActive = false;
      let m = new MessageData('assistant', 'Error: ' + text, 'text');
      ChatStore.messages = [...ChatStore.messages, m];
    });
    this.ws.connect(this.serverUrl);
    this.callbacks.onWsClientReady(this.ws);
  }

  selectAgent(agent: AgentInfo): void {
    ChatStore.selectedAgentName = agent.name;
    ChatStore.agentType = agent.name;
    AppStorage.setOrCreate<string>('lastAgent', agent.name);
    StorageService.getInstance().putString(PrefsKeys.LAST_AGENT, agent.name);
    ChatStore.messages = [];
    ChatStore.planEntries = [];
    ChatStore.sessionId = '';
    this.ws.send({ type: 'list_models' } as ClientMessage);
    this.callbacks.onNavigateToWorkspaceSelect();
  }

  handleUpdate(u: AcpUpdate): void {
    if (ChatStore.loadingSession) {
      ChatStore.loadingSession = false;
    }
    let t: string = u.sessionUpdate;
    if (t === 'agent_message_chunk' && u.content?.text) {
      ChatStore.messages = this.appendText(ChatStore.messages, u.content.text);
    } else if (t === 'agent_thought_chunk' && u.content?.text) {
      ChatStore.messages = this.appendThinking(ChatStore.messages, u.content.text);
    } else if (t === 'tool_call' && u.toolCallId) {
      let m = new MessageData('assistant', u.title || '', 'tool_call');
      m.toolCallId = u.toolCallId; m.toolName = u.title || ''; m.toolStatus = 'pending'; m.toolKind = u.kind || '';
      ChatStore.messages = [...ChatStore.messages, m];
    } else if (t === 'tool_call_update' && u.toolCallId && u.status) {
      let contentText = '';
      if (u.toolCallContent) {
        for (let i = 0; i < u.toolCallContent.length; i++) {
          if (u.toolCallContent[i].content?.text) {
            contentText += u.toolCallContent[i].content!.text!;
          }
        }
      }
      ChatStore.messages = this.updateToolStatus(ChatStore.messages, u.toolCallId, u.status, contentText);
    } else if (t === 'plan' && u.entries) {
      ChatStore.planEntries = u.entries;
    } else if (t === 'user_message_chunk' && u.content?.text) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('user', u.content.text, 'text')];
    } else if (t === 'session_info_update' && u.title) {
      ChatStore.sessionTitle = u.title;
      for (let i = 0; i < ChatStore.sessions.length; i++) {
        if (ChatStore.sessions[i].sessionId === ChatStore.loadedSessionId) {
          ChatStore.sessions[i].title = u.title;
          break;
        }
      }
    } else if (t === 'config_option_update' && u.configOptions) {
      ChatStore.configOptions = u.configOptions;
    } else if (t === 'available_commands_update' && u.availableCommands) {
      ChatStore.availableCommands = u.availableCommands;
    } else if (t === 'usage_update' && u.usage) {
      ChatStore.lastUsage = u.usage;
    } else if (t === 'turn_ended') {
      ChatStore.turnActive = false;
    }
  }

  appendText(msgs: MessageData[], t: string): MessageData[] {
    if (msgs.length > 0) {
      let last = msgs[msgs.length - 1];
      if (last.role === 'assistant' && last.type === 'text') {
        let u = new MessageData('assistant', last.content + t, 'text');
        u.id = last.id; u.timestamp = last.timestamp;
        let r = [...msgs]; r[r.length - 1] = u; return r;
      }
    }
    let cleaned = t.replace(/^\n+/, '');
    return [...msgs, new MessageData('assistant', cleaned, 'text')];
  }

  appendThinking(msgs: MessageData[], t: string): MessageData[] {
    if (msgs.length > 0) {
      let last = msgs[msgs.length - 1];
      if (last.role === 'assistant' && last.type === 'thinking') {
        let u = new MessageData('assistant', last.content + t, 'thinking');
        u.id = last.id; u.timestamp = last.timestamp;
        let r = [...msgs]; r[r.length - 1] = u; return r;
      }
    }
    return [...msgs, new MessageData('assistant', t, 'thinking')];
  }

  updateToolStatus(msgs: MessageData[], id: string, s: string, c: string): MessageData[] {
    let r = [...msgs];
    for (let i = 0; i < r.length; i++) {
      if (r[i].toolCallId === id) {
        let u = new MessageData(r[i].role, r[i].content, r[i].type);
        u.id = r[i].id; u.timestamp = r[i].timestamp;
        u.toolName = r[i].toolName; u.toolStatus = s; u.toolCallId = r[i].toolCallId;
        u.toolContent = c.length > 0 ? c : r[i].toolContent;
        r[i] = u; break;
      }
    }
    return r;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Scroll() {
          Column() {
            // HERO
            Column() {
              Image($r('app.media.anywhere_logo'))
                .width(48).height(48)
                .fillColor(Colors.accent)
                .margin({ bottom: Spacing.lg })
                .scale({ x: this.iconScale, y: this.iconScale })
                .animation({ duration: 2500, curve: Curve.EaseInOut, playMode: PlayMode.Alternate, iterations: -1 })

              Text('Anywhere.')
                .fontSize(36)
                .fontWeight(FontWeight.Bolder)
                .fontColor(Colors.foreground)
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
              if (!ChatStore.connected) {
                Row() {
                  TextInput({ text: this.serverUrl, placeholder: 'Bridge URL (ws://ip:port)' })
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
                    if (this.connecting) {
                      LoadingProgress().width(22).height(22).color(Color.White)
                    } else {
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(22).fontWeight(FontWeight.Bold).fontColor([Color.White])
                    }
                  }
                  .type(ButtonType.Circle)
                  .width(44).height(44)
                  .backgroundColor(this.serverUrl.length > 0 ? Colors.accent : Colors.border)
                  .margin({ right: 4 })
                  .enabled(!this.connecting && this.serverUrl.length > 0)
                  .onClick(() => { this.tryConnect() })
                  .animation({ duration: Duration.normal })
                }
                .width('100%').height(52)
                .backgroundColor(Colors.surface0)
                .borderRadius(26)
                .shadow(Shadow.md)
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))

                if (this.connectError.length > 0) {
                  Text(this.connectError)
                    .fontSize(13).fontColor(Colors.error)
                    .margin({ top: Spacing.md })
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
                }
              } else {
                Row() {
                  Circle().width(8).height(8).fill(Colors.success).margin({ left: 16, right: 10 })
                  Text(this.serverUrl)
                    .fontSize(14).fontColor(Colors.foreground)
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                  Button('Disconnect')
                    .fontSize(13).fontColor(Colors.foregroundMuted).backgroundColor(Color.Transparent)
                    .fontWeight(FontWeight.Medium)
                    .margin({ right: 8 })
                    .onClick(() => {
                      ChatStore.connected = false;
                      this.ws.disconnect();
                    })
                }
                .width('100%').height(52)
                .backgroundColor(Colors.surface0)
                .borderRadius(26)
                .shadow(Shadow.sm)
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
              }
            }
            .width('100%')
            .padding({ left: Spacing.xxl, right: Spacing.xxl })

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
