import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { WorkspaceStore, WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';
import { HostRuntimeStore } from '../../common/model/HostState';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { saveWorkspaces } from '../../services/StorageService';

@Component
export struct WorkspaceListView {
  onSelectWorkspace?: (index: number) => void;
  onNewSession?: (workspaceIndex: number) => void;

  @State searchText: string = '';
  @State filterIndex: number = 0;
  @State showAddWorkspace: boolean = false;
  @State newWorkspacePath: string = '';

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  getBranch(_: WorkspaceInfo): string {
    return 'main';
  }

  getWorkspaceSessions(workspace: WorkspaceInfo): ServerSession[] {
    let result: ServerSession[] = [];
    for (let i: number = 0; i < ChatStore.sessions.length; i++) {
      let session: ServerSession = ChatStore.sessions[i];
      if (!session.cwd || session.cwd.length === 0 || session.cwd === workspace.path) {
        result.push(session);
      }
    }
    result.sort((a: ServerSession, b: ServerSession) => b.createdAt - a.createdAt);
    return result;
  }

  getLatestSession(workspace: WorkspaceInfo): ServerSession | null {
    let sessions: ServerSession[] = this.getWorkspaceSessions(workspace);
    return sessions.length > 0 ? sessions[0] : null;
  }

  getWorkspaceStatus(workspace: WorkspaceInfo): string {
    if (!HostRuntimeStore.isOnline(HostRuntimeStore.activeHostKey)) return 'Offline';
    let latest: ServerSession | null = this.getLatestSession(workspace);
    if (ChatStore.turnActive && latest && latest.sessionId === ChatStore.acpSessionId) {
      return 'Running';
    }
    if (WorkspaceStore.currentIndex === this.findWorkspaceIndex(workspace)) {
      return 'Active';
    }
    return latest ? 'Idle' : 'Ready';
  }

  findWorkspaceIndex(target: WorkspaceInfo): number {
    for (let i: number = 0; i < WorkspaceStore.workspaces.length; i++) {
      if (WorkspaceStore.workspaces[i].id === target.id) return i;
    }
    return -1;
  }

  formatRelativeTime(epoch: number): string {
    if (!epoch || epoch <= 0) return this.text($r('app.string.common_now'));
    let diff: number = Date.now() - epoch;
    let minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) return this.text($r('app.string.common_now'));
    if (minutes < 60) return this.text($r('app.string.common_minutes_ago'), minutes);
    let hours: number = Math.floor(minutes / 60);
    if (hours < 24) return this.text($r('app.string.common_hours_ago'), hours);
    return this.text($r('app.string.common_days_ago'), Math.floor(hours / 24));
  }

  matchesSearch(workspace: WorkspaceInfo): boolean {
    if (this.searchText.length === 0) return true;
    let query: string = this.searchText.toLowerCase();
    let latest: ServerSession | null = this.getLatestSession(workspace);
    return workspace.name.toLowerCase().indexOf(query) >= 0 ||
      workspace.path.toLowerCase().indexOf(query) >= 0 ||
      this.getBranch(workspace).toLowerCase().indexOf(query) >= 0 ||
      (latest?.title || '').toLowerCase().indexOf(query) >= 0;
  }

  matchesFilter(workspace: WorkspaceInfo): boolean {
    let status: string = this.getWorkspaceStatus(workspace);
    if (this.filterIndex === 0) return true;
    if (this.filterIndex === 1) return status === 'Active' || status === 'Running';
    if (this.filterIndex === 2) return status === 'Idle' || status === 'Ready';
    return status === 'Offline';
  }

  getStatusDotColor(status: string): Resource {
    if (status === 'Running' || status === 'Active' || status === 'Ready' || status === 'Idle') {
      return Colors.success;
    }
    if (status === 'Offline') {
      return Colors.foregroundMuted;
    }
    return Colors.warning;
  }

  getStatusLabel(status: string): string {
    if (status === 'Running') return this.text($r('app.string.workspace_status_running'));
    if (status === 'Active') return this.text($r('app.string.workspace_status_active'));
    if (status === 'Idle') return this.text($r('app.string.workspace_status_idle'));
    if (status === 'Ready') return this.text($r('app.string.workspace_status_ready'));
    if (status === 'Offline') return this.text($r('app.string.workspace_status_offline'));
    return status;
  }

  addWorkspace(): void {
    let path = this.newWorkspacePath.trim();
    if (path.length === 0) return;
    let ws = new WorkspaceInfo();
    ws.id = Date.now().toString();
    ws.name = path.split('\\').pop() || path.split('/').pop() || this.text($r('app.string.workspace_project_fallback'));
    ws.path = path;
    WorkspaceStore.workspaces.push(ws);
    WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
    this.newWorkspacePath = '';
    this.showAddWorkspace = false;
    saveWorkspaces('');
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Colors.foregroundMuted])
            .margin({ right: Spacing.sm })
          TextInput({ placeholder: $r('app.string.workspace_search_placeholder'), text: this.searchText })
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Colors.transparent)
            .fontSize(FontSize.base)
            .fontColor(Colors.foreground)
            .placeholderColor(Colors.foregroundMuted)
            .onChange((value: string) => { this.searchText = value; })
        }
        .width(Layout.contentWidth)
        .height(48)
        .padding({ left: Spacing.md, right: Spacing.md })
        .margin({ bottom: Spacing.md })

        Row({ space: Spacing.sm }) {
          this.FilterTab(this.text($r('app.string.workspace_filter_all')), 0)
          this.FilterTab(this.text($r('app.string.workspace_filter_active')), 1)
          this.FilterTab(this.text($r('app.string.workspace_filter_idle')), 2)
          this.FilterTab(this.text($r('app.string.workspace_filter_offline')), 3)
        }
        .width(Layout.contentWidth)
        .padding({ bottom: Spacing.lg })

        if (WorkspaceStore.workspaces.length === 0) {
          Column() {
            Text($r('app.string.workspace_empty_manage'))
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.md })
        } else {
          List({ space: Spacing.md }) {
            ForEach(WorkspaceStore.workspaces, (workspace: WorkspaceInfo, index: number) => {
              if (this.matchesSearch(workspace) && this.matchesFilter(workspace)) {
                ListItem() {
                  this.WorkspaceCard(workspace, index)
                }
              }
            }, (workspace: WorkspaceInfo) => workspace.id + ':' + this.filterIndex.toString() + ':' + this.searchText + ':' +
              HostRuntimeStore.getPhase(HostRuntimeStore.activeHostKey))
          }
          .layoutWeight(1)
          .width(Layout.contentWidth)
          .padding({ bottom: Spacing.xxxl })
        }

        if (this.showAddWorkspace) {
          Row() {
            TextInput({ placeholder: $r('app.string.ws_path_placeholder'), text: this.newWorkspacePath })
              .layoutWeight(1).height(44)
              .borderRadius(Radius.sm)
              .padding({ left: Spacing.md, right: Spacing.md })
              .fontSize(FontSize.sm)
              .backgroundColor(Colors.transparent)
              .onChange((v: string) => { this.newWorkspacePath = v })
              .onSubmit(() => { this.addWorkspace(); })
            Button($r('app.string.ws_add'))
              .height(44).backgroundColor(Colors.transparent).fontColor(Colors.accent)
              .fontWeight(FontWeight.Medium).borderRadius(Radius.sm).fontSize(FontSize.sm)
              .margin({ left: Spacing.sm })
              .onClick(() => { this.addWorkspace(); })
              .stateStyles({
                pressed: { .backgroundColor(Colors.surface1) },
                normal: { .backgroundColor(Colors.transparent) }
              })
          }
          .width(Layout.contentWidth)
          .padding({ bottom: Spacing.md })
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.surface0)
      .padding({ top: 42 })
    }
    .titleBar({
      content: {
        title: { mainTitle: this.text($r('app.string.ws_title')) },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.plus'),
              action: () => { this.showAddWorkspace = !this.showAddWorkspace; }
            }
          }]
        }
      }
    })
    .width('100%').height('100%')
  }

  @Builder
  FilterTab(label: string, idx: number) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(FontSize.sm)
      .fontWeight(this.filterIndex === idx ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.filterIndex === idx ? Colors.foreground : Colors.foregroundMuted)
      .backgroundColor(Colors.transparent)
      .borderRadius(Radius.md)
      .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
      .onClick(() => { this.filterIndex = idx; })
      .stateStyles({
        pressed: {
          .backgroundColor(Colors.surface1)
        },
        normal: {
          .backgroundColor(Colors.transparent)
        }
      })
  }

  @Builder
  WorkspaceCard(workspace: WorkspaceInfo, index: number) {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(20)
            .fontColor([Colors.foreground])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .margin({ right: Spacing.md })

        Column() {
          Text(workspace.name)
            .fontSize(FontSize.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.getBranch(workspace) + ' · ' + (this.getLatestSession(workspace) ?
            this.formatRelativeTime(this.getLatestSession(workspace)!.createdAt) : this.text($r('app.string.workspace_no_sessions'))))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .margin({ top: Spacing.xxs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        this.StatusPill(this.getWorkspaceStatus(workspace))
      }
      .width('100%')
      .margin({ bottom: Spacing.md })

      if (this.getLatestSession(workspace)) {
        Text(this.getLatestSession(workspace)!.title || this.text($r('app.string.common_untitled')))
          .fontSize(FontSize.md)
          .fontColor(Colors.foreground)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: Spacing.xs })
      } else {
        Text($r('app.string.workspace_no_sessions'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .margin({ bottom: Spacing.xs })
      }

      Row() {
        Text(this.text($r('app.string.workspace_sessions_count'), this.getWorkspaceSessions(workspace).length))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
        Blank()
        Text(this.getLatestSession(workspace)?.agent || ChatStore.selectedAgentName || ChatStore.agentType ||
          this.text($r('app.string.workspace_unspecified_agent')))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.lg)
    .onClick(() => { this.onSelectWorkspace?.(index); })
    .stateStyles({
      pressed: {
        .backgroundColor(Colors.surface1)
      },
      normal: {
        .backgroundColor(Colors.transparent)
      }
    })
  }

  @Builder
  StatusPill(status: string) {
    Row() {
      Circle({ width: 6, height: 6 })
        .fill(this.getStatusDotColor(status))
        .margin({ right: Spacing.xs })
      Text(this.getStatusLabel(status))
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
    }
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xs, bottom: Spacing.xs })
    .backgroundColor(Colors.surface1)
    .borderRadius(Radius.full)
  }
}
