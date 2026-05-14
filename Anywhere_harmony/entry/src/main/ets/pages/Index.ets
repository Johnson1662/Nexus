import { Colors, FontSize, Spacing, Radius } from '../constants/Colors';
import { ChatStore } from '../common/model/ChatState';
import { WorkspaceStore } from '../common/model/WorkspaceInfo';
import { PlanEntry } from '../common/model/ChatState';
import { MessageData } from '../common/model/MessageData';
import { WorkspaceInfo, ServerSession } from '../common/model/WorkspaceInfo';
import { WSClient } from '../common/websocket/WSClient';
import { ClientMessage, ModelItem, ModeItem, AcpUpdate, AgentInfo } from '../common/websocket/WSProtocol';
import { ChatPage } from '../feature/chat/ChatPage';
import { WorkspaceDrawer } from '../feature/workspace/WorkspaceDrawer';

interface SO { value: string }

@Entry
@Component
struct Index {
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State connectError: string = '';
  @State showDrawer: boolean = false;
  @State allModels: ModelItem[] = [];
  @State allModes: ModeItem[] = [];
  @State sessions: ServerSession[] = [];
  @State discoveredAgents: AgentInfo[] = [];
  @State showAgentPicker: boolean = false;
  @State awaitingAgents: boolean = false;
  @State selectedAgentName: string = '';
  @State agentType: string = '';
  @State serverUrl: string = 'ws://100.111.77.50:6767';
  @State messages: MessageData[] = [];
  @State planEntries: PlanEntry[] = [];
  @State turnActive: boolean = false;

  private ws: WSClient = new WSClient();

  aboutToAppear(): void {
    // Don't auto-connect — let user tap Connect
  }

  tryConnect(): void {
    this.ws.clearListeners();
    this.connecting = true;
    this.connectError = '';
    this.discoveredAgents = [];
    this.showAgentPicker = false;
    this.awaitingAgents = false;
    this.selectedAgentName = '';
    this.ws.onStateChange((v) => {
      ChatStore.connected = v; 
      this.connected = v; 
      if (!v) {
        if (!this.connecting && this.connectError.length === 0) {
          if (this.selectedAgentName.length > 0 && this.messages.length > 0) {
            // Silent reconnect - don't show error, will auto-reconnect
          } else {
            this.connectError = 'Could not connect. Make sure the bridge server is running.';
          }
        }
        this.connecting = false;
      } else {
        this.connecting = false;
        this.connectError = '';
        if (this.selectedAgentName.length > 0 && this.messages.length > 0) {
          // Auto-reconnected, restore session
          this.ws.send({ type: 'start', agent: this.selectedAgentName } as ClientMessage);
        } else if (this.selectedAgentName.length === 0) {
          this.awaitingAgents = true;
          this.ws.send({ type: 'list_agents' } as ClientMessage);
        }
      }
    });
    this.ws.onAgentList((agents) => {
      this.awaitingAgents = false;
      this.discoveredAgents = agents;
      if (agents.length > 0) {
        this.connectError = '';
        this.showAgentPicker = true;
      } else {
        this.connectError = 'No ACP agents discovered on the server. Install one (e.g., opencode) and try again.';
      }
    });
    this.ws.onModelList((models, modes) => { this.allModels = models; this.allModes = modes; });
    this.ws.onSessionList((s) => { this.sessions = s; });
    this.ws.onAcpUpdate((u) => { this.handleUpdate(u); });
    this.ws.onSessionStarted(() => {
      this.ws.send({ type: 'list_models' } as ClientMessage);
    });
    this.ws.connect(this.serverUrl);
  }

  selectAgent(agent: AgentInfo): void {
    this.selectedAgentName = agent.name;
    this.agentType = agent.name;
    this.showAgentPicker = false;
    this.messages = [];
    this.planEntries = [];
    this.ws.send({ type: 'start', agent: agent.name } as ClientMessage);
  }

  handleUpdate(u: AcpUpdate): void {
    let t: string = u.sessionUpdate;
    if (t === 'agent_message_chunk' && u.content?.text) {
      this.messages = this.appendText(this.messages, u.content.text);
    } else if (t === 'agent_thought_chunk' && u.content?.text) {
      this.messages = this.appendThinking(this.messages, u.content.text);
    } else if (t === 'tool_call' && u.toolCallId) {
      let m = new MessageData('assistant', u.title || '', 'tool_call');
      m.toolCallId = u.toolCallId; m.toolName = u.title || ''; m.toolStatus = 'pending';
      this.messages = [...this.messages, m];
    } else if (t === 'tool_call_update' && u.toolCallId && u.status) {
      this.messages = this.updateStatus(this.messages, u.toolCallId, u.status);
    } else if (t === 'plan' && u.entries) {
      this.planEntries = u.entries;
    } else if (t === 'user_message_chunk' && u.content?.text) {
      this.messages = [...this.messages, new MessageData('user', u.content.text, 'text')];
    } else if (t === 'turn_ended') {
      this.turnActive = false;
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
    // Trim leading newlines from first chunk — agents often prepend \n
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

  sendMessage(text: string): void {
    this.messages = [...this.messages, new MessageData('user', text, 'text')];
    this.turnActive = true;
    if (ChatStore.sessionId) {
      this.ws.send({ type: 'input', sessionId: ChatStore.sessionId, text } as ClientMessage);
    } else {
      this.ws.send({ type: 'start', agent: this.agentType, prompt: text } as ClientMessage);
    }
  }

  getSessionOpts(): SO[] {
    let o: SO[] = [{ value: 'Sessions (' + this.sessions.length + ')' }];
    let max = this.sessions.length > 15 ? 15 : this.sessions.length;
    let start = this.sessions.length - max;
    for (let i = start; i < this.sessions.length; i++) {
      let title = this.sessions[i].title || this.sessions[i].sessionId.substring(0, 8);
      if (title.length > 20) title = title.substring(0, 20) + '…';
      o.push({ value: title });
    }
    return o;
  }

  getWsName(): string {
    return (WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length)
      ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].name : '';
  }

  build() {
    Stack() {
      // ── Connecting ──
      if (!this.connected && this.connecting) {
        Column() {
          LoadingProgress().width(28).height(28).color(Colors.accent)
          Text('Connecting')
            .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ top: Spacing.lg })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(Colors.surface0)

      // ── Awaiting Agent Discovery ──
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
        .backgroundColor(Colors.surface0)

      // ── Disconnected (onboarding) ──
      } else if (!this.connected && !this.connecting) {
        Column() {
          Column() {
            Image($r('app.media.ic_terminal'))
              .fillColor(Colors.foreground).width(64).height(64)
              .margin({ bottom: Spacing.xl })

            Text('ACP Bridge Configuration')
              .fontFamily('monospace')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
            Text('Connect to a remote agent via IP and Port')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ top: Spacing.sm, bottom: 40 })

            Column() {
              Text('SERVER ADDRESS')
                .fontFamily('monospace').fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
                .width('100%').margin({ bottom: Spacing.xs })
              TextInput({ text: this.serverUrl, placeholder: 'ws://ip:port' })
                .height(48).backgroundColor(Colors.surface1).borderRadius(Radius.md)
                .fontSize(FontSize.base).fontFamily('monospace')
                .onChange((val: string) => { this.serverUrl = val })
                .margin({ bottom: Spacing.lg })

              Text('The server will auto-discover installed ACP agents')
                .fontFamily('monospace').fontSize(FontSize.xs).fontColor(Colors.foregroundLight)
                .width('100%').margin({ bottom: 40 })

              Button('Connect')
                .width('100%').height(54)
                .backgroundColor(Colors.accent)
                .fontColor(Color.White)
                .fontFamily('monospace')
                .fontSize(FontSize.md).fontWeight(FontWeight.Bold)
                .borderRadius(Radius.md)
                .onClick(() => { this.tryConnect() })
            }

            if (this.connectError.length > 0) {
              Text(this.connectError)
                .fontFamily('monospace')
                .fontSize(FontSize.xs).fontColor(Colors.error)
                .textAlign(TextAlign.Center)
                .margin({ top: Spacing.lg })
            }
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .padding({ left: 32, right: 32 })
        }
        .width('100%').height('100%').backgroundColor(Colors.surface0)

      // ── Agent Selection ──
      } else if (this.connected && this.showAgentPicker) {
        Column() {
          Column() {
            Image($r('app.media.ic_terminal'))
              .fillColor(Colors.foreground).width(48).height(48)
              .margin({ bottom: Spacing.md })

            Text('Select ACP Agent')
              .fontFamily('monospace')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
            Text('Discovered agents on the remote machine')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).margin({ bottom: 24 })

            List() {
              ForEach(this.discoveredAgents, (agent: AgentInfo, index: number) => {
                ListItem() {
                  Row() {
                    Column() {
                      Circle()
                        .width(8).height(8)
                        .fill(Colors.success)
                        .margin({ bottom: Spacing.xs })
                    }

                    Column() {
                      Row() {
                        Text(agent.title || agent.name)
                          .fontFamily('monospace').fontSize(FontSize.base).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
                        Text('v' + agent.version)
                          .fontFamily('monospace').fontSize(FontSize.xs).fontColor(Colors.foregroundLight).margin({ left: Spacing.sm })
                      }
                      Row() {
                        Text(agent.name)
                          .fontFamily('monospace').fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
                        if (agent.source) {
                          Text('(' + agent.source + ')')
                            .fontFamily('monospace').fontSize(FontSize.xs).fontColor(Colors.foregroundLight).margin({ left: Spacing.xs })
                        }
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (agent.binaryPath) {
                      Text('PATH')
                        .fontFamily('monospace').fontSize(FontSize.xs).fontColor(Colors.accent)
                        .margin({ right: Spacing.sm })
                    }
                  }
                  .width('100%').padding(Spacing.lg)
                  .backgroundColor(Colors.surface1)
                  .borderRadius(Radius.md)
                  .onClick(() => { this.selectAgent(agent) })
                }
                .padding({ bottom: Spacing.sm })
              }, (agent: AgentInfo) => agent.name)
            }
            .width('100%').layoutWeight(1)
          }
          .width('100%').layoutWeight(1)
          .padding({ left: 32, right: 32, top: Spacing.xl })
        }
        .width('100%').height('100%').backgroundColor(Colors.surface0)

      // ── No workspace selected ──
      } else if (WorkspaceStore.currentIndex < 0) {
        Column() {
          Row() {
            Column() {
              Image($r('app.media.ic_menu')).fillColor(Colors.foreground).width(24).height(24)
                .width(18).height(18)
            }
            .width(28).height(28)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .onClick(() => { this.showDrawer = true })
            
            Text('Choose workspace')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              .margin({ left: Spacing.sm })
          }
          .width('100%')
          .height(48)
          .padding({ left: Spacing.md, right: Spacing.md })
          .backgroundColor(Colors.surfaceElevated)
          .border({ width: { bottom: 1 }, color: Colors.borderLight })

          Column() {
            Text('Select a workspace to start').fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%').backgroundColor(Colors.surface0)

      // ── Chat ──
      } else {
        Column() {
          // Top Bar
          Row() {
            Image($r('app.media.ic_menu')).fillColor(Colors.foreground).width(24).height(24)
              .onClick(() => { this.showDrawer = true })
            
            Text('WS:')
              .fontSize(FontSize.md).fontFamily('monospace').fontWeight(FontWeight.Bold).fontColor(Colors.accent)
              .margin({ left: Spacing.md })
            Text(this.selectedAgentName.length > 0 ? this.selectedAgentName : this.agentType)
              .fontSize(FontSize.sm).fontFamily('monospace').fontColor(Colors.accentDark)
              .fontWeight(FontWeight.Medium)
              .margin({ left: Spacing.xs })
            Text(this.getWsName())
              .fontSize(FontSize.md).fontFamily('monospace').fontColor(Colors.foreground)
              .margin({ left: Spacing.sm }).layoutWeight(1)
              
            Image($r('app.media.ic_clear')).fillColor(Colors.foreground).width(24).height(24).margin({ right: Spacing.lg })
              .onClick(() => { 
                this.getUIContext().getPromptAction().openToast({ message: 'Session Cleared' });
                this.messages = []; 
                this.planEntries = [];
              })
            Image($r('app.media.ic_terminal')).fillColor(Colors.foregroundMuted).width(24).height(24)
              .onClick(() => {
                this.getUIContext().getPromptAction().openToast({ message: 'ACP Bridge Online' });
              })
          }
          .width('100%').height(56)
          .padding({ left: Spacing.lg, right: Spacing.lg })
          .border({ width: { bottom: 1 }, color: { bottom: Colors.borderLight } })

          // Empty state
          if (this.messages.length === 0) {
            Column() {
              Image($r('app.media.ic_terminal')).fillColor(Colors.foregroundMuted).width(48).height(48).margin({ bottom: Spacing.md })
              Text('Anywhere Workspace')
                .fontSize(FontSize.lg).fontFamily('monospace').fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              Text('Agent Client Protocol (ACP) Active')
                .fontSize(FontSize.sm).fontFamily('monospace').fontColor(Colors.accent).margin({ top: Spacing.sm })
              Text('Awaiting command execution...')
                .fontSize(FontSize.sm).fontFamily('monospace').fontColor(Colors.foregroundLight).margin({ top: Spacing.xs })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            ChatPage({
              messages: this.messages,
              planEntries: this.planEntries,
              turnActive: this.turnActive,
              models: this.allModels,
              modes: this.allModes,
              onSendMessage: (t: string) => { this.sendMessage(t) },
              onSwitchModel: (i: number) => { 
                if (ChatStore.sessionId && i > 0 && i - 1 < this.allModels.length) {
                  this.ws.send({ type: 'switch_model', sessionId: ChatStore.sessionId, model: this.allModels[i-1].modelId } as ClientMessage)
                }
              },
              onSwitchMode: (i: number) => {
                if (ChatStore.sessionId && i > 0 && i - 1 < this.allModes.length) {
                  this.ws.send({ type: 'set_mode', sessionId: ChatStore.sessionId, modeId: this.allModes[i-1].value } as ClientMessage)
                }
              }
            }).layoutWeight(1)
          }

          Row() {
            Image($r('app.media.ic_panel')).fillColor(Colors.foreground).width(20).height(20).margin({ right: Spacing.sm })
            Select(this.getSessionOpts()).selected(0).value('Loading...')
              .font({ size: FontSize.base }).fontColor(Colors.foreground).layoutWeight(1).backgroundColor('transparent')
              .onSelect((i) => {
                if (i > 0 && i - 1 < this.sessions.length) {
                  ChatStore.sessionId = this.sessions[i - 1].sessionId;
                  this.messages = []; this.planEntries = []; this.turnActive = false;
                  let p = WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path;
                  this.ws.send({ type: 'load_session', sessionId: this.sessions[i - 1].sessionId, cwd: p } as ClientMessage);
                }
              })
            Image($r('app.media.ic_chevron_down')).fillColor(Colors.foregroundMuted).width(20).height(20)
          }
          .width('100%').height(40)
          .padding({ left: Spacing.lg, right: Spacing.lg })
          .backgroundColor(Colors.surfaceElevated)
          .border({ width: { bottom: 1 }, color: Colors.borderLight })

          ChatPage({
            messages: this.messages,
            planEntries: this.planEntries,
            turnActive: this.turnActive,
            models: this.allModels,
            modes: this.allModes,
            onSendMessage: (t) => { this.sendMessage(t) },
            onSwitchModel: () => {},
            onSwitchMode: () => {}
          })
        }
        .width('100%').height('100%')
      }

      // ── Workspace drawer overlay ──
      if (this.showDrawer) {
        Row() {
          WorkspaceDrawer({
            workspaces: WorkspaceStore.workspaces,
            currentIndex: WorkspaceStore.currentIndex,
            hostName: 'host', hostUrl: 'ws://...', agentType: this.agentType,
            onSelect: (i) => {
              WorkspaceStore.currentIndex = i; this.showDrawer = false;
              this.ws.send({ type: 'list_sessions', cwd: WorkspaceStore.workspaces[i].path } as ClientMessage);
            },
            onDelete: (i) => { WorkspaceStore.workspaces.splice(i, 1); },
            onClose: () => { this.showDrawer = false; },
            onSwitchHost: () => {},
            onAddWorkspace: (p) => {
              let ws = new WorkspaceInfo();
              ws.id = Date.now().toString();
              ws.name = p.split('\\').pop() || p.split('/').pop() || 'Project';
              ws.path = p;
              WorkspaceStore.workspaces.push(ws);
              if (WorkspaceStore.currentIndex < 0) WorkspaceStore.currentIndex = 0;
            }
          })
        }
        .width('75%').height('100%').backgroundColor(Colors.surface0)
        .position({ x: 0, y: 0 }).zIndex(100)
        Column().width('25%').height('100%').position({ x: '75%', y: 0 }).zIndex(100)
          .backgroundColor(Colors.shadowColorStrong).onClick(() => { this.showDrawer = false })
      }
    }
    .width('100%').height('100%').backgroundColor(Colors.surface0)

  }
}
