import { Colors, FontSize, Spacing, Radius, Shadow, Layout } from '../../constants/DesignTokens';
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

  @State showMenu: boolean = false;
  @State showAddHostMenu: boolean = false;
  @State showManualHostForm: boolean = false;
  @State manualHostUrl: string = '';
  @State pressedWorkspaceId: string = '';
  @State pressedHostKey: string = '';
  @State pressedAction: string = '';
  @State entered: boolean = false;
  @State selectedHostFilter: string = 'all';

  aboutToAppear(): void {
    DeviceAgentStore.loadFromDisk();
    if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
    }
    setTimeout(() => {
      (this.getUIContext() as UIContext)?.animateTo({ duration: 240, curve: Curve.Friction }, () => {
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
    if (epoch <= 0) return '刚刚';
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
          this.Header()
          this.BrandHeader()
          this.HostFilterChips()
          this.WorkspaceSection()
          this.RecentSection()
          Column().height(104)
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surface0)
      .scrollBar(BarState.Off)

      Stack({ alignContent: Alignment.Bottom }) {
        this.BottomActionBar()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.showMenu) {
        this.MenuOverlay()
      }

      if (this.showAddHostMenu) {
        this.AddHostOverlay()
      }

      if (this.showManualHostForm) {
        this.ManualHostOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }

  @Builder
  Header() {
    Row() {
      Button() {
        CustomIcon({ name: 'menu', iconSize: 20, color: Colors.foreground })
      }
      .width(36)
      .height(36)
      .backgroundColor(Colors.transparent)
      .borderRadius(Radius.full)
      .scale({ x: this.pressedAction === 'menu' ? 0.94 : 1, y: this.pressedAction === 'menu' ? 0.94 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        this.pressedAction = event.type === TouchType.Down ? 'menu' : '';
      })
      .onClick(() => { this.showMenu = true; })
      Blank()
      Button() {
        CustomIcon({ name: 'more', iconSize: 15, color: Colors.foreground })
      }
      .width(36)
      .height(36)
      .backgroundColor(Colors.surface0)
      .border({ width: 1, color: Colors.borderLight })
      .borderRadius(Radius.full)
      .scale({ x: this.pressedAction === 'more' ? 0.94 : 1, y: this.pressedAction === 'more' ? 0.94 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        this.pressedAction = event.type === TouchType.Down ? 'more' : '';
      })
      .onClick(() => { this.showMenu = true; })
    }
    .width(Layout.contentWidth)
    .padding({ top: Spacing.sm, bottom: Spacing.xs })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : -8 })
  }

  @Builder
  BrandHeader() {
    Column() {
      Text('Anywhere')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
    }
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.lg })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 8 })
  }

  @Builder
  HostFilterChips() {
    Scroll() {
      Row({ space: Spacing.sm }) {
        this.HostChip('All', 'all', true)
        ForEach(HostStore.devices, (device: DeviceEntry) => {
          this.HostChip(this.getHostLabel(device), this.getHostKey(device), this.isHostOnline(device))
        }, (device: DeviceEntry) => this.getHostKey(device))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width(Layout.contentWidth)
    .height(42)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .padding({ top: Spacing.xs, bottom: Spacing.xxl })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 10 })
  }

  @Builder
  HostChip(label: string, key: string, online: boolean) {
    Button() {
      Row() {
        if (key !== 'all') {
          Circle({ width: 6, height: 6 })
            .fill(online ? Colors.success : Colors.foregroundMuted)
            .margin({ right: Spacing.xs })
          CustomIcon({
            name: 'model',
            iconSize: 12,
            color: this.selectedHostFilter === key ? Colors.surface0 : Colors.foreground
          })
            .margin({ right: Spacing.xs })
        }
        Text(label)
          .fontSize(FontSize.xs)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedHostFilter === key ? Colors.surface0 : Colors.foreground)
          .maxLines(1)
      }
    }
    .height(32)
    .padding({ left: key === 'all' ? Spacing.lg : Spacing.md, right: key === 'all' ? Spacing.lg : Spacing.md })
    .backgroundColor(this.selectedHostFilter === key ? Colors.foreground : Colors.surface0)
    .border({ width: this.selectedHostFilter === key ? 0 : 1, color: Colors.borderLight })
    .borderRadius(Radius.full)
    .scale({
      x: this.pressedHostKey === key ? 0.96 : 1,
      y: this.pressedHostKey === key ? 0.96 : 1
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      this.pressedHostKey = event.type === TouchType.Down ? key : '';
    })
    .onClick(() => { this.selectedHostFilter = key; })
  }

  @Builder
  StatusHero() {
    Column() {
      Column() {
        Row() {
          Circle({ width: 8, height: 8 })
            .fill(this.isConnectedToHost() ? Colors.success : Colors.foregroundMuted)
            .margin({ right: Spacing.sm })
          Text(this.isConnectedToHost() ? this.getCurrentDeviceName() : '还没有连接主机')
            .fontSize(FontSize.lg)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
        }
        .width('100%')
        .margin({ bottom: Spacing.md })

        Text(this.getCurrentWorkspaceName())
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .margin({ bottom: Spacing.lg })

        Row() {
          this.MetricCard('Hosts', HostStore.devices.length.toString())
          this.MetricCard('Agents', this.getWorkspaceAgentCount().toString())
          this.MetricCard('Sessions', ChatStore.sessions.length.toString())
        }
        .width('100%')
      }
      .width('100%')
      .padding(Spacing.lg)
      .backgroundColor(Colors.surface1)
      .borderRadius(Radius.lg)
    }
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.xl })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  MetricCard(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(FontSize.xxl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
      Text(label)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
        .margin({ top: Spacing.xxs })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  WorkspaceSection() {
    Column() {
      Text('Projects')
        .fontSize(FontSize.md)
        .fontColor(Colors.foreground)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: Spacing.md })

      if (WorkspaceStore.workspaces.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(36)
            .fontColor([Colors.foregroundMuted])
            .opacity(0.55)
            .margin({ bottom: Spacing.md })
          Text('还没有项目')
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
            .margin({ bottom: Spacing.xs })
          Text('从菜单添加主机或进入聊天后添加工作区。')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .padding({ top: Spacing.xl, bottom: Spacing.xl })
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(WorkspaceStore.workspaces, (workspace: WorkspaceInfo, index: number) => {
          this.WorkspaceCard(workspace, index)
        }, (workspace: WorkspaceInfo) => workspace.id)
      }
    }
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.xl })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 12 })
    .animation({ duration: 220, curve: Curve.Friction })
  }

  @Builder
  WorkspaceCard(workspace: WorkspaceInfo, index: number) {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(20)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.lg })

        Column() {
          Text(workspace.name)
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Text(this.getWorkspaceBranch(workspace))
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundMuted)
            if (this.getWorkspaceLatestTitle(workspace).length > 0) {
              Text(' · ' + this.getWorkspaceLatestTitle(workspace))
                .fontSize(FontSize.xs)
                .fontColor(Colors.foregroundMuted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .margin({ top: Spacing.xxs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.getWorkspaceTime(workspace))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .margin({ right: Spacing.sm })
        Circle({ width: 5, height: 5 })
          .fill(this.isWorkspaceRunning(workspace) ? Colors.success : Colors.foregroundMuted)
          .margin({ right: Spacing.sm })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([Colors.foregroundMuted])
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: Spacing.md, bottom: Spacing.md })
    .backgroundColor(Colors.transparent)
    .border({ width: { bottom: 1 }, color: Colors.borderLight })
    .borderRadius(0)
    .scale({
      x: this.pressedWorkspaceId === workspace.id ? 0.98 : 1.0,
      y: this.pressedWorkspaceId === workspace.id ? 0.98 : 1.0
    })
    .animation({ duration: 100, curve: Curve.EaseOut })
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
  RecentSection() {
    Column() {
      Text('Recent chats')
        .fontSize(FontSize.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.md })

      if (this.getRecentSessions().length === 0) {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_message'))
              .fontSize(18)
              .fontColor([Colors.foregroundMuted])
          }
          .width(42)
          .height(42)
          .borderRadius(Radius.lg)
          .backgroundColor(Colors.surface0)
          .border({ width: 1, color: Colors.borderLight })
          .justifyContent(FlexAlign.Center)
          .margin({ right: Spacing.md })
          Column() {
            Text('新会话会直接出现在这里')
              .fontSize(FontSize.xs)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.foreground)
            Text('选择 Agent 后开始第一条消息')
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundMuted)
              .margin({ top: Spacing.xxs })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: Spacing.md, bottom: Spacing.md })
      } else {
        ForEach(this.getRecentSessions(), (session: ServerSession) => {
          this.RecentChatRow(session)
        }, (session: ServerSession) => session.sessionId)
      }
    }
    .width(Layout.contentWidth)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 14 })
    .animation({ duration: 240, curve: Curve.Friction, delay: 40 })
  }

  @Builder
  RecentChatRow(session: ServerSession) {
    Button() {
      Row() {
        Row() {
          CustomIcon({ name: 'model', iconSize: 15, color: Colors.foreground })
        }
        .width(42)
        .height(42)
        .backgroundColor(Colors.surface0)
        .border({ width: 1, color: Colors.borderLight })
        .borderRadius(Radius.lg)
        .justifyContent(FlexAlign.Center)
        .margin({ right: Spacing.md })

        Column() {
          Text(session.title || 'Untitled')
            .fontSize(FontSize.xs)
            .fontWeight(FontWeight.Medium)
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
          .fontSize(13)
          .fontColor([Colors.foregroundMuted])
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: Spacing.md, bottom: Spacing.md })
    .backgroundColor(Colors.transparent)
    .border({ width: { bottom: 1 }, color: Colors.borderLight })
    .borderRadius(0)
  }

  @Builder
  BottomActionBar() {
    Row({ space: Spacing.md }) {
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([Colors.foregroundMuted])
            .margin({ right: Spacing.sm })
          Text('Search projects or chats')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(52)
      .backgroundColor(Colors.surface0)
      .border({ width: 1, color: Colors.borderLight })
      .borderRadius(Radius.full)
      .scale({ x: this.pressedAction === 'search' ? 0.98 : 1, y: this.pressedAction === 'search' ? 0.98 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        this.pressedAction = event.type === TouchType.Down ? 'search' : '';
      })
      .onClick(() => {
        this.onOpenChat?.(WorkspaceStore.currentIndex);
      })

      Button() {
        Row() {
          CustomIcon({ name: 'new_chat', iconSize: 18, color: Colors.surface0 })
            .margin({ right: Spacing.sm })
          Text('New chat')
            .fontSize(FontSize.sm)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.surface0)
        }
      }
      .height(52)
      .padding({ left: Spacing.lg, right: Spacing.lg })
      .backgroundColor(Colors.foreground)
      .borderRadius(Radius.full)
      .scale({ x: this.pressedAction === 'new-chat' ? 0.98 : 1, y: this.pressedAction === 'new-chat' ? 0.98 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        this.pressedAction = event.type === TouchType.Down ? 'new-chat' : '';
      })
      .onClick(() => {
        this.onOpenChat?.(WorkspaceStore.currentIndex);
      })
    }
    .width(Layout.contentWidth)
    .margin({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 16 })
    .animation({ duration: 240, curve: Curve.Friction, delay: 80 })
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
    .animation({ duration: 100, curve: Curve.EaseOut })
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
  MenuSheet() {
    Column() {
      this.MenuRow('Add host', 'plus', () => {
        this.showMenu = false;
        this.showAddHostMenu = true;
      })
      this.MenuRow('Refresh agents', 'refresh', () => {
        this.showMenu = false;
        this.onRefreshHostsAgents?.();
      })
      this.MenuRow('Settings', 'settings', () => {
        this.showMenu = false;
        this.onOpenSettings?.();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(Spacing.xs)
    .backgroundColor(Colors.surface0)
    .borderRadius(Radius.xl)
    .shadow(Shadow.md)
  }

  @Builder
  MenuRow(label: string, icon: string, action: () => void) {
    Button() {
      Row() {
        if (icon === 'plus') {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(14).fontColor([Colors.foreground]).margin({ right: Spacing.sm })
        } else if (icon === 'refresh') {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(14).fontColor([Colors.foreground]).margin({ right: Spacing.sm })
        } else if (icon === 'settings') {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(14).fontColor([Colors.foreground]).margin({ right: Spacing.sm })
        } else if (icon === 'scan') {
          SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(14).fontColor([Colors.foreground]).margin({ right: Spacing.sm })
        } else {
          SymbolGlyph($r('sys.symbol.vpn_key')).fontSize(14).fontColor([Colors.foreground]).margin({ right: Spacing.sm })
        }
        Text(label)
          .fontSize(FontSize.xs)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Medium)
        Blank()
        if (icon === 'plus') {
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor([Colors.foregroundMuted])
        }
      }
      .width('100%')
    }
    .width('100%')
    .height(34)
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.sm)
    .padding({ left: Spacing.xs, right: Spacing.xs })
    .onClick(action)
  }

  @Builder
  MenuOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.transparent)
        .onClick(() => { this.showMenu = false; })
      Column() {
        this.MenuSheet()
      }
      .width(148)
      .margin({ top: 56, right: Spacing.xl })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddHostOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.transparent)
        .onClick(() => { this.showAddHostMenu = false; })
      Column() {
        this.AddHostSheet()
      }
      .width(148)
      .margin({ top: 56, right: Spacing.xl })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddHostSheet() {
    Column() {
      Text('Add host')
        .fontSize(FontSize.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.xs })
      this.MenuRow('Scan QR', 'scan', () => {
        this.showAddHostMenu = false;
        this.onOpenAddHostScan?.();
      })
      this.MenuRow('Link manually', 'manual', () => {
        this.showAddHostMenu = false;
        this.showManualHostForm = true;
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(Spacing.sm)
    .backgroundColor(Colors.surface0)
    .borderRadius(Radius.xl)
    .shadow(Shadow.md)
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
      .margin({ top: 56, right: Spacing.xl })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
    }
    .width('100%')
    .height('100%')
  }
}
