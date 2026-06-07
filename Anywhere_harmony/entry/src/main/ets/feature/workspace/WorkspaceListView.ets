import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { WorkspaceStore, WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';

@Component
export struct WorkspaceListView {
  onSelectWorkspace?: (index: number) => void;
  onNewSession?: (workspaceIndex: number) => void;

  @State searchText: string = '';
  @State filterIndex: number = 0;

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
    if (!ChatStore.connected) return 'Offline';
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
    if (!epoch || epoch <= 0) return '刚刚';
    let diff: number = Date.now() - epoch;
    let minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) return '刚刚';
    if (minutes < 60) return minutes.toString() + ' 分钟前';
    let hours: number = Math.floor(minutes / 60);
    if (hours < 24) return hours.toString() + ' 小时前';
    return Math.floor(hours / 24).toString() + ' 天前';
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
    if (status === 'Running' || status === 'Active') {
      return Colors.success;
    }
    if (status === 'Offline') {
      return Colors.foregroundMuted;
    }
    return Colors.warning;
  }

  build() {
    Column() {
      Row() {
        Text('Workspaces')
          .fontSize(FontSize.xxxxl)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
        Blank()
        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([Colors.surface0])
        }
        .width(40)
        .height(40)
        .borderRadius(Radius.full)
        .backgroundColor(Colors.foreground)
        .onClick(() => { this.onNewSession?.(WorkspaceStore.currentIndex); })
      }
      .width('100%')
      .padding({ top: Spacing.xxxl, bottom: Spacing.lg, left: Spacing.xl, right: Spacing.xl })

      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([Colors.foregroundMuted])
          .margin({ right: Spacing.sm })
        TextInput({ placeholder: '搜索工作区、任务或路径...', text: this.searchText })
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
        this.FilterTab('全部', 0)
        this.FilterTab('活跃', 1)
        this.FilterTab('空闲', 2)
        this.FilterTab('离线', 3)
      }
      .width(Layout.contentWidth)
      .padding({ bottom: Spacing.lg })

      if (WorkspaceStore.workspaces.length === 0) {
        Column() {
          Text('还没有工作区。先从聊天页侧边栏添加项目路径，再从这里管理工作区和会话。')
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
          }, (workspace: WorkspaceInfo) => workspace.id + ':' + this.filterIndex.toString() + ':' + this.searchText)
        }
        .layoutWeight(1)
        .width(Layout.contentWidth)
        .padding({ bottom: Spacing.xxxl })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.surface0)
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
            this.formatRelativeTime(this.getLatestSession(workspace)!.createdAt) : '暂无会话'))
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
        Text(this.getLatestSession(workspace)!.title || 'Untitled')
          .fontSize(FontSize.md)
          .fontColor(Colors.foreground)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: Spacing.xs })
      } else {
        Text('还没有历史会话')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .margin({ bottom: Spacing.xs })
      }

      Row() {
        Text(this.getWorkspaceSessions(workspace).length.toString() + ' 个会话')
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
        Blank()
        Text(this.getLatestSession(workspace)?.agent || ChatStore.selectedAgentName || ChatStore.agentType || '未指定 Agent')
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
      Text(status)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
    }
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xs, bottom: Spacing.xs })
    .backgroundColor(Colors.surface1)
    .borderRadius(Radius.full)
  }
}
