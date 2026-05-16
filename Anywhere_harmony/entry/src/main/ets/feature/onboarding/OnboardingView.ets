import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { ChatStore, ModelItem, ModeItem } from '../../common/model/ChatState';
import { WorkspaceStore } from '../../common/model/WorkspaceInfo';
import { WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { WSClient } from '../../common/websocket/WSClient';
import { ClientMessage, AcpUpdate, AgentInfo } from '../../common/websocket/WSProtocol';
import { MessageData } from '../../common/model/MessageData';
import { StorageService, PrefsKeys } from '../../services/StorageService';

interface OnboardingCallbacks {
  onNavigateToChat: () => void;
  onWsClientReady: (ws: WSClient) => void;
}

@Component
export struct OnboardingView {
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State connectError: string = '';
  @State discoveredAgents: AgentInfo[] = [];
  @State showAgentSheet: boolean = false;
  @State awaitingAgents: boolean = false;
  @StorageLink('serverUrl') serverUrl: string = 'ws://100.111.77.50:12138';

  private ws: WSClient = new WSClient();
  callbacks: OnboardingCallbacks = { onNavigateToChat: () => {}, onWsClientReady: () => {} };

  tryConnect(): void {
    AppStorage.setOrCreate<string>('serverUrl', this.serverUrl);
    StorageService.getInstance().putString(PrefsKeys.SERVER_URL, this.serverUrl);
    this.ws.clearListeners();
    this.connecting = true;
    this.connectError = '';
    this.discoveredAgents = [];
    this.showAgentSheet = false;
    this.awaitingAgents = false;
    ChatStore.selectedAgentName = '';
    this.ws.onStateChange((v: boolean) => {
      ChatStore.connected = v;
      this.connected = v;
      if (!v) {
        if (!this.connecting && this.connectError.length === 0) {
          if (ChatStore.selectedAgentName.length > 0 && ChatStore.messages.length > 0) {
          } else {
            this.connectError = 'Could not connect. Make sure the bridge server is running.';
          }
        }
        this.connecting = false;
      } else {
        this.connecting = false;
        this.connectError = '';
        if (ChatStore.selectedAgentName.length > 0 && ChatStore.messages.length > 0) {
          this.ws.send({ type: 'start', agent: ChatStore.selectedAgentName } as ClientMessage);
        } else if (ChatStore.selectedAgentName.length === 0) {
          this.awaitingAgents = true;
          this.ws.send({ type: 'list_agents' } as ClientMessage);
        }
      }
    });
    this.ws.onAgentList((agents: AgentInfo[]) => {
      this.awaitingAgents = false;
      this.discoveredAgents = agents;
      if (agents.length > 0) {
        this.connectError = '';
        this.showAgentSheet = true;
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
    this.showAgentSheet = false;
    ChatStore.messages = [];
    ChatStore.planEntries = [];
    let cwd = WorkspaceStore.currentIndex >= 0 ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path : '';
    this.ws.send({ type: 'start', agent: agent.name, cwd: cwd } as ClientMessage);
    this.callbacks.onNavigateToChat();
  }

  handleUpdate(u: AcpUpdate): void {
    let t: string = u.sessionUpdate;
    if (t === 'agent_message_chunk' && u.content?.text) {
      ChatStore.messages = this.appendText(ChatStore.messages, u.content.text);
    } else if (t === 'agent_thought_chunk' && u.content?.text) {
      ChatStore.messages = this.appendThinking(ChatStore.messages, u.content.text);
    } else if (t === 'tool_call' && u.toolCallId) {
      let m = new MessageData('assistant', u.title || '', 'tool_call');
      m.toolCallId = u.toolCallId; m.toolName = u.title || ''; m.toolStatus = 'pending';
      ChatStore.messages = [...ChatStore.messages, m];
    } else if (t === 'tool_call_update' && u.toolCallId && u.status) {
      ChatStore.messages = this.updateStatus(ChatStore.messages, u.toolCallId, u.status);
    } else if (t === 'plan' && u.entries) {
      ChatStore.planEntries = u.entries;
    } else if (t === 'user_message_chunk' && u.content?.text) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('user', u.content.text, 'text')];
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
      Stack() {
        if (!this.connected && this.connecting) {
          Column() {
            LoadingProgress().width(28).height(28).color(Colors.accent)
            Text('Connecting')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ top: Spacing.lg })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
          .animation({ duration: Duration.normal, curve: Curve.EaseOut })

        } else if (this.connected && this.awaitingAgents) {
          Column() {
            LoadingProgress().width(28).height(28).color(Colors.accent)
            Text('Discovering Agents')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ top: Spacing.lg })
            Text('Scanning the remote machine for installed ACP agents...')
              .fontSize(FontSize.xs).fontColor(Colors.foregroundLight).margin({ top: Spacing.sm })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
          .animation({ duration: Duration.normal, curve: Curve.EaseOut })

        } else if (this.connected && this.showAgentSheet) {
          Column() {
            SymbolGlyph($r('sys.symbol.ohos_wifi'))
              .fontSize(36)
              .fontColor([Colors.accent])
              .margin({ bottom: Spacing.md })
              Text('Select ACP Agent')
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              Text('Discovered agents on the remote machine')
                .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ bottom: 24 })

            List() {
              ForEach(this.discoveredAgents, (agent: AgentInfo, index: number) => {
                ListItem() {
                  Row() {
                    Circle().width(8).height(8).fill(Colors.success).margin({ right: Spacing.md })
                    Column() {
                      Text(agent.title || agent.name)
                        .fontSize(FontSize.base).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
                      Text(agent.name)
                        .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
                    }
                    .layoutWeight(1)
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
          .width('100%').height('100%').padding({ top: Spacing.xl })
          .transition(TransitionEffect.OPACITY)
          .animation({ duration: Duration.normal, curve: Curve.EaseOut })
        } else {
          Column() {
            Column() {
          SymbolGlyph($r('sys.symbol.ohos_wifi'))
                .fontSize(48)
                .fontColor([Colors.accent])
                .margin({ bottom: Spacing.xxl })

              Text('ACP Bridge Configuration')
                .fontSize(FontSize.xxl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              Text('Connect to a remote agent via IP and Port')
                .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ top: Spacing.sm, bottom: Spacing.xxxl })

              Column() {
                Text('Server Address')
                  .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
                  .width('100%').margin({ bottom: Spacing.xs })
                TextInput({ text: this.serverUrl, placeholder: 'ws://ip:port' })
                  .height(48).backgroundColor(Colors.surface1).borderRadius(Radius.md)
                  .fontSize(FontSize.base)
                  .onChange((val: string) => { this.serverUrl = val })
                  .margin({ bottom: Spacing.lg })

                Text('The server will auto-discover installed ACP agents')
                  .fontSize(FontSize.xs).fontColor(Colors.foregroundLight)
                  .width('100%').margin({ bottom: Spacing.xxl })

                Button('Connect')
                  .width('100%').height(48)
                  .backgroundColor(Colors.accent).fontColor(Color.White)
                  .fontSize(FontSize.base).fontWeight(FontWeight.Medium).borderRadius(Radius.md)
                  .onClick(() => { this.tryConnect() })
              }

              if (this.connectError.length > 0) {
                Text(this.connectError)
                  .fontSize(FontSize.xs).fontColor(Colors.error)
                  .textAlign(TextAlign.Center).margin({ top: Spacing.lg })
                  .transition(TransitionEffect.OPACITY)
                  .animation({ duration: Duration.fast, curve: Curve.EaseOut })
              }
            }
            .width('100%').layoutWeight(1)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .padding({ left: 32, right: 32 })
          }
          .width('100%').height('100%')
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
          .animation({ duration: Duration.slow, curve: Curve.EaseOut })
        }
      }
      .width('100%').height('100%').backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }
}
