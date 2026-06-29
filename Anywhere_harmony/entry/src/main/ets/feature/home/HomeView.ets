import { Colors, FontSize, Spacing, Radius, Shadow, Layout, Duration, getLocalizedString } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { HostStore, DeviceEntry, WorkspaceStore, WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { HostRuntimeStore } from '../../common/model/HostState';

@Component
export struct HomeView {
  onNavigateToAgentDetail?: (index: number) => void;
  onNavigateToSession?: (session: ServerSession) => void;
  onOpenWorkspace?: (index: number) => void;
  onOpenChat?: (workspaceIndex: number) => void;
  onNewChat?: () => void;
  onConnectHost?: (url: string) => void;
  onRefreshHostsAgents?: () => void;
  onNavigateToWorkspaceList?: () => void;

  @StorageLink('homeShowManualHost') showManualHostForm: boolean = false;
  @StorageLink('serverUrl') currentServerUrl: string = '';
  @StorageLink('loadingWorkspaces') loadingWorkspaces: boolean = false;
  @State manualHostUrl: string = '';
  @State entered: boolean = false;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  aboutToAppear(): void {
    DeviceAgentStore.loadFromDisk();
    if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
    }
    setTimeout(() => {
      (this.getUIContext())?.animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.entered = true;
      });
    }, 30);
  }

  isConnectedToHost(): boolean {
    return HostRuntimeStore.isOnline(HostRuntimeStore.activeHostKey);
  }

  getCurrentDeviceName(): string {
    if (!this.isConnectedToHost()) return this.text($r('app.string.home_no_host'));
    let currentHostKey: string = HostRuntimeStore.activeHostKey;
    for (let i: number = 0; i < HostStore.devices.length; i++) {
      let device: DeviceEntry = HostStore.devices[i];
      if (device.hostId === currentHostKey || device.name === currentHostKey) {
        return device.name;
      }
    }
    return currentHostKey;
  }

  getCurrentWorkspaceName(): string {
    if (WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
      return WorkspaceStore.workspaces[WorkspaceStore.currentIndex].name;
    }
    return this.text($r('app.string.home_select_workspace'));
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
    if (!epoch || epoch <= 0) return this.text($r('app.string.common_now'));
    let diff: number = Date.now() - epoch;
    let mins: number = Math.floor(diff / 60000);
    if (mins < 1) return this.text($r('app.string.common_now'));
    if (mins < 60) return this.text($r('app.string.common_minutes_ago'), mins);
    let hours: number = Math.floor(mins / 60);
    if (hours < 24) return this.text($r('app.string.common_hours_ago'), hours);
    return this.text($r('app.string.common_days_ago'), Math.floor(hours / 24));
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
      return latest.title || this.text($r('app.string.common_untitled'));
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
    return latest ? this.formatRelativeTime(latest.createdAt) : this.text($r('app.string.common_ready'));
  }

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  isHostOnline(device: DeviceEntry): boolean {
    return HostRuntimeStore.isDeviceOnline(device);
  }

  getHostLabel(device: DeviceEntry): string {
    if (device.name.length > 16) {
      return device.name.substring(0, 16);
    }
    return device.name;
  }

  getWorkspaceAgentCount(): number {
    let currentHostKey: string = HostRuntimeStore.activeHostKey;
    if (!HostRuntimeStore.isOnline(currentHostKey)) {
      return 0;
    }
    return DeviceAgentStore.getAgents(currentHostKey).length;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          this.WorkspaceSection()
          this.RecentSection()
          Column().height(100) // Space for floating bar
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surface0)
      .scrollBar(BarState.Off)

      Column() {
        this.BottomActionBar()
      }
      .width('100%')
      .padding({ bottom: Spacing.xl })
      .hitTestBehavior(HitTestMode.Transparent)

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
      Row() {
        Text($r('app.string.home_projects'))
          .fontSize(FontSize.xl)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button($r('app.string.home_view_all'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.accent)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(Colors.transparent)
          .borderRadius(Radius.md)
          .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xs, bottom: Spacing.xs })
          .onClick(() => { this.onNavigateToWorkspaceList?.(); })
      }
      .width('100%')
      .margin({ bottom: Spacing.xl })

      if (this.loadingWorkspaces) {
        Column() {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(Colors.foregroundMuted)
          Text($r('app.string.chat_loading_session'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .margin({ top: Spacing.sm })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: Spacing.xl, bottom: Spacing.xl })
      } else if (WorkspaceStore.workspaces.length === 0) {
        Text($r('app.string.home_no_projects'))
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
    .padding({ top: 0, bottom: Spacing.xxl })
    .opacity(this.entered ? 1 : 0)
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

@Builder
  WorkspaceCard(workspace: WorkspaceInfo, index: number) {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(22)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.lg, left: Spacing.xs })

        Column() {
          Text(workspace.name)
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.text($r('app.string.home_workspace_updated'), this.getWorkspaceTime(workspace)))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .maxLines(1)
            .margin({ top: Spacing.xxs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row() {
          Circle({ width: 6, height: 6 })
            .fill(this.isWorkspaceRunning(workspace) ? Colors.success : Colors.foregroundMuted)
            .margin({ right: Spacing.xs })
          Text(this.isWorkspaceRunning(workspace) ? this.text($r('app.string.common_running')) : this.text($r('app.string.common_idle')))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xs, bottom: Spacing.xs })
        .backgroundColor(Colors.surface1)
        .borderRadius(Radius.full)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.lg, bottom: Spacing.lg })
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .border({ width: 0 })
    .borderRadius(Radius.md)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onClick(() => { this.onOpenWorkspace?.(index); })
  }

@Builder
  RecentSection() {
    Column() {
      Text($r('app.string.home_recent_chats'))
        .fontSize(FontSize.xl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.xl })

      if (this.getRecentSessions().length > 0) {
        ForEach(this.getRecentSessions(), (session: ServerSession) => {
          this.RecentChatRow(session)
        }, (session: ServerSession) => session.sessionId)
      } else {
        Column() {
          Text($r('app.string.home_no_recent'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .width('100%')
            .padding({ top: Spacing.md, bottom: Spacing.md })
        }
        .width('100%')
      }
    }
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.xxl })
    .opacity(this.entered ? 1 : 0)
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

@Builder
  RecentChatRow(session: ServerSession) {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(22)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.lg, left: Spacing.xs })

        Column() {
          Text(session.title || this.text($r('app.string.common_untitled')))
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text((session.agent ? session.agent + ' · ' : '') + (session.cwd || ''))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .margin({ top: Spacing.xxs })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.formatRelativeTime(session.createdAt))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ right: Spacing.sm })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.lg, bottom: Spacing.lg })
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .border({ width: 0 })
    .borderRadius(Radius.md)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onClick(() => { this.onNavigateToSession?.(session); })
  }

@Builder
  BottomActionBar() {
    Row({ space: Spacing.md }) {
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(18)
            .fontColor([Colors.foregroundMuted])
            .margin({ right: Spacing.sm })
          Text($r('app.string.home_search_chats'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: Spacing.lg })
      }
      .layoutWeight(1)
      .height(50)
      .backgroundColor(Colors.surface1)
      .border({ width: 0 })
      .borderRadius(Radius.full)
      .stateStyles({
        pressed: { .backgroundColor(Colors.surface2) },
        normal: { .backgroundColor(Colors.surface1) }
      })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .onClick(() => {
        this.onOpenChat?.(WorkspaceStore.currentIndex);
      })

      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(16)
            .fontColor([Colors.surface0])
            .margin({ right: Spacing.sm })
          Text($r('app.string.home_chat'))
            .fontSize(FontSize.sm)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.surface0)
        }
      }
      .height(50)
      .padding({ left: Spacing.xl, right: Spacing.xl })
      .backgroundColor(Colors.foreground)
      .borderRadius(Radius.full)
      .shadow(Shadow.md)
      .stateStyles({
        pressed: { .backgroundColor(Colors.accentDark) },
        normal: { .backgroundColor(Colors.foreground) }
      })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .onClick(() => {
        this.onNewChat?.();
      })
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
        Text($r('app.string.home_link_manually'))
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
        Button($r('app.string.home_connect'))
          .width('100%')
          .height(44)
          .fontSize(FontSize.sm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.surface0)
          .backgroundColor(this.manualHostUrl.trim().length > 0 ? Colors.foreground : Colors.border)
          .borderRadius(Radius.md)
          .margin({ top: Spacing.sm })
          .enabled(this.manualHostUrl.trim().length > 0)
          .stateStyles({
            pressed: { .opacity(0.8) },
            normal: { .opacity(1.0) }
          })
          .animation({ duration: 150, curve: Curve.EaseOut })
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
      .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }
}
