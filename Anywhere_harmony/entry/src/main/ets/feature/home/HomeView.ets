import { Colors, FontSize, Spacing, Radius, Shadow, Layout, Duration } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { HostStore, DeviceEntry, WorkspaceStore, WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { CustomIcon } from '../../common/ui/CustomIcon';

@Component
export struct HomeView {
  onNavigateToAgentDetail?: (index: number) => void;
  onOpenWorkspace?: (index: number) => void;
  onOpenChat?: (workspaceIndex: number) => void;
  onOpenSettings?: () => void;
  onOpenAddHostScan?: () => void;
  onConnectHost?: (url: string) => void;
  onRefreshHostsAgents?: () => void;

  @StorageLink('homeShowManualHost') showManualHostForm: boolean = false;
  @State manualHostUrl: string = '';
  @State pressedWorkspaceId: string = '';
  @State pressedSessionId: string = '';
  @State pressedAction: string = '';
  @State entered: boolean = false;

  aboutToAppear(): void {
    DeviceAgentStore.loadFromDisk();
    if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
    }
    setTimeout(() => {
      (this.getUIContext() as UIContext)?.animateTo({ duration: Duration.fast, curve: Curve.EaseOut }, () => {
        this.entered = true;
      });
    }, 30);
  }

  isConnectedToHost(): boolean {
    return ChatStore.connected && ChatStore.currentDeviceId.length > 0;
  }

  getCurrentDeviceName(): string {
    if (!this.isConnectedToHost()) return '未连接主机';
    for (let i: number = 0; i < HostStore.devices.length; i++) {
      let device: DeviceEntry = HostStore.devices[i];
      if (device.hostId === ChatStore.currentDeviceId || device.name === ChatStore.currentDeviceId) {
        return device.name;
      }
    }
    return ChatStore.currentDeviceId;
  }

  getCurrentWorkspaceName(): string {
    if (WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
      return WorkspaceStore.workspaces[WorkspaceStore.currentIndex].name;
    }
    return '选择一个工作区开始';
  }

  getRecentSessions(): ServerSession[] {
    let sorted: ServerSession[] = [];
    for (let i: number = 0; i < ChatStore.sessions.length; i++) {
      sorted.push(ChatStore.sessions[i]);
    }
    sorted.sort((a: ServerSession, b: ServerSession) => b.createdAt - a.createdAt);
    if (sorted.length > 4) {
      return sorted.slice(0, 4);
    }
    return sorted;
  }

  formatRelativeTime(epoch: number): string {
    if (!epoch || epoch <= 0) return '刚刚';
    let diff: number = Date.now() - epoch;
    let mins: number = Math.floor(diff / 60000);
    if (mins < 1) return '刚刚';
    if (mins < 60) return mins.toString() + ' 分钟前';
    let hours: number = Math.floor(mins / 60);
    if (hours < 24) return hours.toString() + ' 小时前';
    return Math.floor(hours / 24).toString() + ' 天前';
  }

  getWorkspaceSessions(workspace: WorkspaceInfo): ServerSession[] {
    let result: ServerSession[] = [];
    for (let i: number = 0; i < ChatStore.sessions.length; i++) {
      let session: ServerSession = ChatStore.sessions[i];
      if (session.cwd === workspace.path) {
        result.push(session);
      }
    }
    result.sort((a: ServerSession, b: ServerSession) => b.createdAt - a.createdAt);
    return result;
  }

  getWorkspaceLatestSession(workspace: WorkspaceInfo): ServerSession | null {
    let sessions: ServerSession[] = this.getWorkspaceSessions(workspace);
    return sessions.length > 0 ? sessions[0] : null;
  }

  getWorkspaceSessionCount(workspace: WorkspaceInfo): number {
    return this.getWorkspaceSessions(workspace).length;
  }

  getWorkspaceLatestTitle(workspace: WorkspaceInfo): string {
    let latest: ServerSession | null = this.getWorkspaceLatestSession(workspace);
    if (latest) {
      return latest.title || 'Untitled';
    }
    return '';
  }

  getWorkspaceBranch(_: WorkspaceInfo): string {
    return 'main';
  }

  isWorkspaceRunning(workspace: WorkspaceInfo): boolean {
    let latest: ServerSession | null = this.getWorkspaceLatestSession(workspace);
    return ChatStore.turnActive && latest !== null && latest.sessionId === ChatStore.acpSessionId;
  }

  getWorkspaceTime(workspace: WorkspaceInfo): string {
    let latest: ServerSession | null = this.getWorkspaceLatestSession(workspace);
    return latest ? this.formatRelativeTime(latest.createdAt) : 'Ready';
  }

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  isHostOnline(device: DeviceEntry): boolean {
    if (!this.isConnectedToHost()) {
      return false;
    }
    return device.hostId === ChatStore.currentDeviceId || device.name === ChatStore.currentDeviceId;
  }

  getHostLabel(device: DeviceEntry): string {
    if (device.name.length > 16) {
      return device.name.substring(0, 16);
    }
    return device.name;
  }

  getWorkspaceAgentCount(): number {
    if (ChatStore.currentDeviceId.length === 0) {
      return 0;
    }
    return DeviceAgentStore.getAgents(ChatStore.currentDeviceId).length;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.WorkspaceSection()
          this.RecentSection()
          this.BottomActionBar()
          Column().height(32)
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surface0)
      .scrollBar(BarState.Off)

      if (this.showManualHostForm) {
        this.ManualHostOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }

  @Builder
  WorkspaceSection() {
    Column() {
      Text('Projects')
        .fontSize(FontSize.xl)
        .fontColor(Colors.foreground)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: Spacing.lg })

      if (WorkspaceStore.workspaces.length === 0) {
        Text('还没有项目。从菜单添加主机或进入聊天后添加工作区。')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .margin({ bottom: Spacing.md })
      } else {
        ForEach(WorkspaceStore.workspaces, (workspace: WorkspaceInfo, index: number) => {
          this.WorkspaceCard(workspace, index)
        }, (workspace: WorkspaceInfo) => workspace.id)
      }
    }
    .width(Layout.contentWidth)
    .padding({ top: Spacing.xxl, bottom: Spacing.xxl })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 12 })
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
  }

  @Builder
  WorkspaceCard(workspace: WorkspaceInfo, index: number) {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(24)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.lg, left: Spacing.xs })

        Column() {
          Text(workspace.name)
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Text('main · Updated ' + this.getWorkspaceTime(workspace))
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundMuted)
          }
          .width('100%')
          .margin({ top: Spacing.xxs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row() {
          Circle({ width: 6, height: 6 })
            .fill(this.isWorkspaceRunning(workspace) ? Colors.success : Colors.foregroundMuted)
            .margin({ right: Spacing.xs })
          Text(this.isWorkspaceRunning(workspace) ? 'Running' : 'Idle')
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .margin({ right: Spacing.sm })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([Colors.foregroundMuted])
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.lg, bottom: Spacing.lg })
    .backgroundColor(this.pressedWorkspaceId === workspace.id ? Colors.surface1 : Colors.transparent)
    .border({ width: 0 })
    .borderRadius(Radius.md)
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedWorkspaceId = workspace.id;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedWorkspaceId = '';
      }
    })
    .onClick(() => { this.onOpenWorkspace?.(index); })
  }

  @Builder
  RecentSection() {
    Column() {
      Text('Recent chats')
        .fontSize(FontSize.xl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.lg })

      if (this.getRecentSessions().length > 0) {
        ForEach(this.getRecentSessions(), (session: ServerSession) => {
          this.RecentChatRow(session)
        }, (session: ServerSession) => session.sessionId)
      }
    }
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.xxl })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 14 })
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
  }

  @Builder
  RecentChatRow(session: ServerSession) {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(24)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.lg, left: Spacing.xs })

        Column() {
          Text(session.title || 'Untitled')
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(session.cwd || session.agent || 'Agent')
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .margin({ top: Spacing.xxs })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.formatRelativeTime(session.createdAt))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .margin({ right: Spacing.sm })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([Colors.foregroundMuted])
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.lg, bottom: Spacing.lg })
    .backgroundColor(this.pressedSessionId === session.sessionId ? Colors.surface1 : Colors.transparent)
    .border({ width: 0 })
    .borderRadius(Radius.md)
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedSessionId = session.sessionId;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedSessionId = '';
      }
    })
    .onClick(() => {})
  }

  @Builder
  BottomActionBar() {
    Row({ space: Spacing.sm }) {
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(18)
            .fontColor([Colors.foregroundMuted])
            .margin({ right: Spacing.sm })
          Text('Search chats')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: Spacing.md })
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(Colors.surface1)
      .border({ width: 0 })
      .borderRadius(Radius.full)
      .animation({ duration: Duration.fast, curve: Curve.EaseOut })
      .onClick(() => {
        this.onOpenChat?.(WorkspaceStore.currentIndex);
      })

      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(16)
            .fontColor([Colors.surface0])
            .margin({ right: Spacing.sm })
          Text('Chat')
            .fontSize(FontSize.sm)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.surface0)
        }
      }
      .height(48)
      .padding({ left: Spacing.xl, right: Spacing.xl })
      .backgroundColor(Colors.foreground)
      .borderRadius(Radius.full)
      .animation({ duration: Duration.fast, curve: Curve.EaseOut })
      .onClick(() => {
        this.onOpenChat?.(WorkspaceStore.currentIndex);
      })
    }
    .width(Layout.contentWidth)
    .margin({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.xl })
    .opacity(1)
    .translate({ y: 0 })
  }

  /*
   * Legacy dashboard builders are intentionally kept unused for now so the
   * ongoing prototype migration stays easy to compare and roll forward.
   */
  @Builder
  LegacyWorkspaceSection() {
    Column() {
      Row() {
        Text('Workspaces')
          .fontSize(FontSize.lg)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('Open chat')
          .fontSize(FontSize.xs)
          .fontColor(Colors.foreground)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.full)
          .onClick(() => { this.onOpenChat?.(WorkspaceStore.currentIndex); })
      }
      .width('100%')
      .margin({ bottom: Spacing.md })

      if (WorkspaceStore.workspaces.length === 0) {
        Column() {
          Text('还没有工作区')
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
            .margin({ bottom: Spacing.xs })
          Text('进入聊天页后可以直接从侧边栏添加项目路径。')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .padding(Spacing.lg)
        .backgroundColor(Colors.surface1)
        .borderRadius(Radius.xl)
      } else {
        List({ space: Spacing.sm }) {
          ForEach(WorkspaceStore.workspaces, (workspace: WorkspaceInfo, index: number) => {
            ListItem() {
              this.WorkspaceCard(workspace, index)
            }
          }, (workspace: WorkspaceInfo) => workspace.id)
        }
        .width('100%')
      }
    }
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.xl })
  }

  @Builder
  LegacyWorkspaceCard(workspace: WorkspaceInfo, index: number) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(18)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.md })
        Column() {
          Text(workspace.name)
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
          Text(workspace.path)
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: Spacing.xxs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.getWorkspaceSessionCount(workspace).toString() + ' sessions')
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
      }
      .width('100%')

      if (this.getWorkspaceSessionCount(workspace) > 0) {
        Text(this.getWorkspaceLatestTitle(workspace))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foreground)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: Spacing.md })
      }
    }
    .width('100%')
    .padding(Spacing.lg)
    .backgroundColor(Colors.surface1)
    .borderRadius(Radius.lg)
    .scale({
      x: this.pressedWorkspaceId === workspace.id ? 0.97 : 1.0,
      y: this.pressedWorkspaceId === workspace.id ? 0.97 : 1.0
    })
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedWorkspaceId = workspace.id;
      } else {
        this.pressedWorkspaceId = '';
      }
    })
    .onClick(() => { this.onOpenWorkspace?.(index); })
  }

  @Builder
  LegacyRecentSection() {
    Column() {
      Text('Recent chats')
        .fontSize(FontSize.lg)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.md })

      if (this.getRecentSessions().length === 0) {
        Text('新会话会直接出现在这里。')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .padding(Spacing.lg)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.lg)
      } else {
        List({ space: Spacing.sm }) {
          ForEach(this.getRecentSessions(), (session: ServerSession) => {
            ListItem() {
              Row() {
                CustomIcon({ name: 'model', iconSize: 18, color: Colors.foregroundMuted })
                  .margin({ right: Spacing.md })
                Column() {
                  Text(session.title || 'Untitled')
                    .fontSize(FontSize.sm)
                    .fontColor(Colors.foreground)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text((session.agent || 'Agent') + ' · ' + this.formatRelativeTime(session.createdAt))
                    .fontSize(FontSize.xs)
                    .fontColor(Colors.foregroundMuted)
                    .margin({ top: Spacing.xxs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(Spacing.lg)
              .backgroundColor(Colors.surface1)
              .borderRadius(Radius.lg)
            }
          }, (session: ServerSession) => session.sessionId)
        }
        .width('100%')
      }
    }
    .width(Layout.contentWidth)
  }

  @Builder
  ManualHostOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.transparent)
        .onClick(() => { this.showManualHostForm = false; })
      Column() {
        Text('Link manually')
          .fontSize(FontSize.xs)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .width('100%')
          .margin({ bottom: Spacing.md })
        TextInput({ placeholder: 'ws://192.168.1.2:12138', text: this.manualHostUrl })
          .width('100%')
          .height(44)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foreground)
          .placeholderColor(Colors.foregroundMuted)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.md)
          .padding({ left: Spacing.md, right: Spacing.md })
          .onChange((value: string) => { this.manualHostUrl = value; })
        Button('Connect')
          .width('100%')
          .height(44)
          .fontSize(FontSize.sm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.surface0)
          .backgroundColor(this.manualHostUrl.trim().length > 0 ? Colors.foreground : Colors.border)
          .borderRadius(Radius.md)
          .margin({ top: Spacing.sm })
          .enabled(this.manualHostUrl.trim().length > 0)
          .onClick(() => {
            let url: string = this.manualHostUrl.trim();
            this.showManualHostForm = false;
            this.manualHostUrl = '';
            this.onConnectHost?.(url);
          })
      }
      .width(196)
      .padding(Spacing.md)
      .backgroundColor(Colors.surface0)
      .borderRadius(Radius.xl)
      .shadow(Shadow.md)
      .margin({ top: 4, right: Spacing.xl })
      .transition(TransitionEffect.OPACITY)
    }
    .width('100%')
    .height('100%')
  }
}
