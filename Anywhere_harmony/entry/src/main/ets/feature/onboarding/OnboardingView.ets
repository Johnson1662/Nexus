import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
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

  private ws: WSClient = new WSClient();
  callbacks: OnboardingCallbacks = { onNavigateToWorkspaceSelect: () => {}, onWsClientReady: () => {} };

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
            this.connectError = 'Could not connect. Make sure the bridge server is running.';
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
      this.discoveredAgents = agents;
      this.connecting = false;
      if (agents.length > 0) {
        this.connectError = '';
      } else {
        this.connectError = 'No ACP agents discovered on the server. Install one (e.g., opencode) and try again.';
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
    this.ws.onSessionStarted(() => {
      this.ws.send({ type: 'list_models' } as ClientMessage);
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
      ChatStore.messages = this.updateStatus(ChatStore.messages, u.toolCallId, u.status);
    } else if (t === 'plan' && u.entries) {
      ChatStore.planEntries = u.entries;
    } else if (t === 'user_message_chunk' && u.content?.text) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('user', u.content.text, 'text')];
    } else if (t === 'session_info_update' && u.title) {
      ChatStore.sessionTitle = u.title;
    } else if (t === 'config_option_update' && u.configOptions) {
      ChatStore.configOptions = u.configOptions;
    } else if (t === 'available_commands_update' && u.availableCommands) {
      ChatStore.availableCommands = u.availableCommands;
    } else if (t === 'usage_update' && u.usage) {
      ChatStore.lastUsage = u.usage;
    } else if (t === 'turn_ended') {
      ChatStore.turnActive = false;
      if (WorkspaceStore.currentIndex >= 0) {
        this.ws.send({ type: 'list_sessions', cwd: WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path } as ClientMessage);
      }
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

  updateStatus(msgs: MessageData[], id: string, s: string): MessageData[] {
    let r = [...msgs];
    for (let i = 0; i < r.length; i++) {
      if (r[i].toolCallId === id) {
        let u = new MessageData(r[i].role, r[i].content, r[i].type);
        u.id = r[i].id; u.timestamp = r[i].timestamp;
        u.toolName = r[i].toolName; u.toolStatus = s; u.toolCallId = r[i].toolCallId;
        r[i] = u; break;
      }
    }
    return r;
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // Title
            Column() {
              SymbolGlyph($r('sys.symbol.ohos_wifi'))
                .fontSize(36).fontColor([Colors.accent]).margin({ bottom: Spacing.md })
              Text('Bridge Configuration')
                .fontSize(FontSize.xxl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              Text('Connect to a remote AI coding agent')
                .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            }
            .width('100%').alignItems(HorizontalAlign.Center)
            .padding({ top: Spacing.xxxl * 2, bottom: Spacing.xxxl })

            // Form
            Column() {
              TextInput({ text: this.serverUrl, placeholder: 'ws://ip:port' })
                .height(48).width('100%')
                .backgroundColor(Colors.surface1).borderRadius(Radius.md)
                .fontSize(FontSize.base).padding({ left: Spacing.md })
                .onChange((val: string) => { this.serverUrl = val })

              Button() {
                Row() {
                  if (this.connecting) {
                    LoadingProgress().width(20).height(20).color(Color.White)
                      .margin({ right: Spacing.sm })
                  }
                  Text(this.connecting ? 'Connecting...' : 'Connect')
                    .fontColor(Color.White).fontSize(FontSize.base)
                }
                .alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
              }
              .width('100%').height(48)
              .backgroundColor(Colors.accent).borderRadius(Radius.md)
              .margin({ top: Spacing.lg })
              .enabled(!this.connecting)
              .onClick(() => { this.tryConnect() })
            }
            .width('100%')

            // Error
            if (this.connectError.length > 0) {
              Text(this.connectError)
                .fontSize(FontSize.xs).fontColor(Colors.error)
                .width('100%').margin({ top: Spacing.md })
                .transition(TransitionEffect.OPACITY)
            }

            // Agent list
            if (this.discoveredAgents.length > 0) {
              Text('Select Agent')
                .fontSize(FontSize.base).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
                .width('100%').margin({ top: Spacing.xxl, bottom: Spacing.md })

              List() {
                ForEach(this.discoveredAgents, (agent: AgentInfo, index: number) => {
                  ListItem() {
                    Row() {
                      Circle().width(8).height(8).fill(Colors.success).margin({ right: Spacing.md })
                      Column() {
                        Text(agent.title || agent.name)
                          .fontSize(FontSize.base).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
                        Text(agent.name)
                          .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
                      }
                      .layoutWeight(1)
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(FontSize.sm).fontColor([Colors.foregroundLight])
                    }
                    .width('100%').padding(Spacing.lg)
                    .backgroundColor(Colors.surface1).borderRadius(Radius.md)
                    .onClick(() => { this.selectAgent(agent) })
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 30 })))
                    .animation({ duration: Duration.normal, curve: Curve.EaseOut, delay: index * 50 })
                  }
                  .padding({ bottom: Spacing.sm })
                }, (agent: AgentInfo) => agent.name)
              }
              .width('100%').layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ bottom: Spacing.xxxl })
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
      .padding({ left: Spacing.xxxl, right: Spacing.xxxl })
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -30 })))
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }
}
