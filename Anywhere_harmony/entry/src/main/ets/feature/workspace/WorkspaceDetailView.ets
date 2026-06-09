import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { WorkspaceStore, WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore, PlanEntry } from '../../common/model/ChatState';
import { HostRuntimeStore } from '../../common/model/HostState';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { AgentInfo } from '../../common/websocket/WSProtocol';
import { CustomIcon } from '../../common/ui/CustomIcon';

class WorkspaceAgentEntry {
  name: string = '';
  title: string = '';
}

class WorkspaceActivityRow {
  time: string = '';
  actor: string = '';
  content: string = '';
}

@Component
export struct WorkspaceDetailView {
  @Prop workspaceIndex: number = 0;
  onBack?: () => void;
  onSelectSession?: (session: ServerSession) => void;
  onNewSession?: (workspaceIndex: number) => void;

  @State detailTabIndex: number = 0;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  getWorkspace(): WorkspaceInfo {
    if (this.workspaceIndex >= 0 && this.workspaceIndex < WorkspaceStore.workspaces.length) {
      return WorkspaceStore.workspaces[this.workspaceIndex];
    }
    return new WorkspaceInfo();
  }

  getWorkspaceSessions(): ServerSession[] {
    let result: ServerSession[] = [];
    let workspace: WorkspaceInfo = this.getWorkspace();
    for (let i: number = 0; i < ChatStore.sessions.length; i++) {
      let session: ServerSession = ChatStore.sessions[i];
      if (!session.cwd || session.cwd.length === 0 || session.cwd === workspace.path) {
        result.push(session);
      }
    }
    result.sort((a: ServerSession, b: ServerSession) => b.createdAt - a.createdAt);
    return result;
  }

  getLatestSession(): ServerSession | null {
    let sessions: ServerSession[] = this.getWorkspaceSessions();
    return sessions.length > 0 ? sessions[0] : null;
  }

  getCurrentAgentName(): string {
    let latest: ServerSession | null = this.getLatestSession();
    return latest?.agent || ChatStore.selectedAgentName || ChatStore.agentType || this.text($r('app.string.config_agent'));
  }

  getProgressValue(): number {
    if (ChatStore.planEntries.length === 0) {
      return ChatStore.turnActive ? 18 : (this.getLatestSession() ? 100 : 0);
    }
    let completed: number = 0;
    for (let i: number = 0; i < ChatStore.planEntries.length; i++) {
      if (ChatStore.planEntries[i].status === 'completed') {
        completed += 1;
      }
    }
    return Math.floor((completed / ChatStore.planEntries.length) * 100);
  }

  getCurrentTask(): string {
    if (ChatStore.sessionTitle.length > 0) return ChatStore.sessionTitle;
    let latest: ServerSession | null = this.getLatestSession();
    if (latest && latest.title.length > 0) return latest.title;
    return this.text($r('app.string.workspace_detail_no_task'));
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

  getAgentStatus(agentName: string): string {
    if (this.getCurrentAgentName() === agentName && ChatStore.turnActive) {
      return 'Running';
    }
    if (!HostRuntimeStore.isOnline(HostRuntimeStore.activeHostKey)) {
      return 'Offline';
    }
    if (this.getCurrentAgentName() === agentName) {
      return 'Idle';
    }
    return 'Ready';
  }

  getAgentsForCurrentDevice(): WorkspaceAgentEntry[] {
    let currentHostKey: string = HostRuntimeStore.activeHostKey;
    if (currentHostKey.length > 0) {
      let agents: AgentInfo[] = DeviceAgentStore.getAgents(currentHostKey);
      if (agents.length > 0) {
        let mapped: WorkspaceAgentEntry[] = [];
        for (let i: number = 0; i < agents.length; i++) {
          let entry: WorkspaceAgentEntry = new WorkspaceAgentEntry();
          entry.name = agents[i].name;
          entry.title = agents[i].title || agents[i].name;
          mapped.push(entry);
        }
        return mapped;
      }
    }
    if (this.getCurrentAgentName().length > 0) {
      let fallback: WorkspaceAgentEntry = new WorkspaceAgentEntry();
      fallback.name = this.getCurrentAgentName();
      fallback.title = this.getCurrentAgentName();
      return [fallback];
    }
    return [];
  }

  getActivityRows(): WorkspaceActivityRow[] {
    let rows: WorkspaceActivityRow[] = [];
    let latest: ServerSession | null = this.getLatestSession();
    if (latest) {
      let latestRow: WorkspaceActivityRow = new WorkspaceActivityRow();
      latestRow.time = this.formatRelativeTime(latest.createdAt);
      latestRow.actor = latest.agent || this.text($r('app.string.config_agent'));
      latestRow.content = latest.title || this.text($r('app.string.workspace_detail_created_session'));
      rows.push(latestRow);
    }
    for (let i: number = 0; i < ChatStore.planEntries.length && i < 4; i++) {
      let entry: PlanEntry = ChatStore.planEntries[i];
      let row: WorkspaceActivityRow = new WorkspaceActivityRow();
      row.time = entry.status === 'completed' ? this.text($r('app.string.workspace_plan_completed')) :
        (entry.status === 'in_progress' ? this.text($r('app.string.workspace_plan_in_progress')) :
          this.text($r('app.string.workspace_plan_pending')));
      row.actor = this.getCurrentAgentName();
      row.content = entry.content;
      rows.push(row);
    }
    return rows;
  }

  getStatusDotColor(status: string): Resource {
    if (status === 'Running' || status === 'Ready' || status === 'Idle') {
      return Colors.success;
    }
    if (status === 'Offline') {
      return Colors.foregroundMuted;
    }
    if (status === 'Completed') {
      return Colors.foreground;
    }
    return Colors.warning;
  }

  getStatusLabel(status: string): string {
    if (status === 'Running') return this.text($r('app.string.workspace_status_running'));
    if (status === 'Ready') return this.text($r('app.string.workspace_status_ready'));
    if (status === 'Idle') return this.text($r('app.string.workspace_status_idle'));
    if (status === 'Offline') return this.text($r('app.string.workspace_status_offline'));
    if (status === 'Completed') return this.text($r('app.string.workspace_status_completed'));
    return status;
  }

  build() {
    NavDestination() {
      Column() {
        this.TitleBarBuilder()
        
        Scroll() {
          Column() {
            Row({ space: Spacing.sm }) {
              this.QuickAction(this.text($r('app.string.workspace_quick_new_session')), 'plus')
              this.QuickAction(this.text($r('app.string.workspace_quick_activity')), 'clock')
            }
            .width(Layout.contentWidth)
            .padding({ bottom: Spacing.lg })

            this.CurrentAgentCard()

            Row({ space: Spacing.sm }) {
              this.DetailTab(this.text($r('app.string.workspace_tab_sessions')), 0)
              this.DetailTab(this.text($r('app.string.workspace_tab_agents')), 1)
              this.DetailTab(this.text($r('app.string.workspace_tab_activity')), 2)
            }
            .width(Layout.contentWidth)
            .padding({ top: Spacing.lg, bottom: Spacing.md })

            if (this.detailTabIndex === 0) {
              this.SessionsSection()
            } else if (this.detailTabIndex === 1) {
              this.AgentsSection()
            } else {
              this.ActivitySection()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: Spacing.xxxl })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }

  @Builder
  TitleBarBuilder() {
    Row() {
      Text(this.getWorkspace().name || this.text($r('app.string.workspace_title_fallback')))
        .fontSize(FontSize.md)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.foreground)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(56)
    .padding({ left: Spacing.xl, right: Spacing.xl })
    .backgroundColor(Colors.surface0)
  }

  @Builder
  QuickAction(label: string, symbol: string) {
    Button() {
      Column() {
        if (symbol === 'plus') {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([Colors.foreground]).margin({ bottom: Spacing.xs })
        } else if (symbol === 'clock') {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(18).fontColor([Colors.foreground]).margin({ bottom: Spacing.xs })
        } else if (symbol === 'folder') {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(18).fontColor([Colors.foreground]).margin({ bottom: Spacing.xs })
        } else {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(18).fontColor([Colors.foreground]).margin({ bottom: Spacing.xs })
        }
        Text(label).fontSize(FontSize.xxs).fontColor(Colors.foreground).maxLines(1)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(64)
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.xl)
    .onClick(() => {
      if (symbol === 'plus') {
        this.onNewSession?.(this.workspaceIndex);
      } else if (symbol === 'clock') {
        this.detailTabIndex = 2;
      }
    })
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
  CurrentAgentCard() {
    Column() {
      Column() {
        Row() {
          Text(this.getCurrentAgentName())
            .fontSize(FontSize.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
          Blank()
          this.StatusPill(this.getAgentStatus(this.getCurrentAgentName()))
        }
        .width('100%')
        .margin({ bottom: Spacing.sm })

        Text(this.getCurrentTask())
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .maxLines(2)
          .margin({ bottom: Spacing.md })

        Progress({ value: this.getProgressValue(), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color(Colors.foreground)
          .backgroundColor(Colors.surface0)

        Row() {
          Text(this.getLatestSession() ? this.text($r('app.string.workspace_started_at'),
            this.formatRelativeTime(this.getLatestSession()!.createdAt)) : this.text($r('app.string.workspace_waiting_first_task')))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
          Blank()
          Text(this.getProgressValue().toString() + '%')
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .margin({ top: Spacing.sm })
      }
      .width('100%')
      .padding(Spacing.lg)
      .borderRadius(Radius.lg)
    }
    .width(Layout.contentWidth)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  DetailTab(label: string, idx: number) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(FontSize.sm)
      .fontWeight(this.detailTabIndex === idx ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.detailTabIndex === idx ? Colors.foreground : Colors.foregroundMuted)
      .backgroundColor(Colors.transparent)
      .borderRadius(Radius.md)
      .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
      .onClick(() => { this.detailTabIndex = idx; })
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
  SessionsSection() {
    if (this.getWorkspaceSessions().length === 0) {
      Column() {
        Text($r('app.string.workspace_empty_current'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
      }
      .layoutWeight(1)
      .width(Layout.contentWidth)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
    } else {
      List({ space: Spacing.sm }) {
        ForEach(this.getWorkspaceSessions(), (session: ServerSession) => {
          ListItem() {
            this.SessionCard(session)
          }
        }, (session: ServerSession) => session.sessionId)
      }
      .layoutWeight(1)
      .width(Layout.contentWidth)
      .padding({ bottom: Spacing.xxxl })
    }
  }

  @Builder
  SessionCard(session: ServerSession) {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.ellipsis_message'))
          .fontSize(18)
          .fontColor([Colors.foregroundMuted])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .margin({ right: Spacing.md })

      Column() {
        Text(session.title || this.text($r('app.string.common_untitled')))
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((session.agent || this.text($r('app.string.config_agent'))) + ' · ' + this.formatRelativeTime(session.createdAt))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.StatusPill(ChatStore.turnActive && session.sessionId === ChatStore.acpSessionId ? 'Running' : 'Completed')
    }
    .width('100%')
    .padding(Spacing.md)
    .onClick(() => { this.onSelectSession?.(session); })
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
  AgentsSection() {
    List({ space: Spacing.sm }) {
      ForEach(this.getAgentsForCurrentDevice(), (agent: WorkspaceAgentEntry) => {
        ListItem() {
          Row() {
            CustomIcon({ name: 'model', iconSize: 22, color: Colors.foreground })
              .margin({ right: Spacing.md })
            Column() {
              Text(agent.title || agent.name)
                .fontSize(FontSize.md)
                .fontColor(Colors.foreground)
              Text(agent.name)
                .fontSize(FontSize.xs)
                .fontColor(Colors.foregroundMuted)
                .margin({ top: Spacing.xxs })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            this.StatusPill(this.getAgentStatus(agent.name))
          }
          .width('100%')
          .padding(Spacing.md)
          .stateStyles({
            pressed: {
              .backgroundColor(Colors.surface1)
            },
            normal: {
              .backgroundColor(Colors.transparent)
            }
          })
        }
      }, (agent: WorkspaceAgentEntry) => agent.name)
    }
    .layoutWeight(1)
    .width(Layout.contentWidth)
    .padding({ bottom: Spacing.xxxl })
  }

  @Builder
  ActivitySection() {
    if (this.getActivityRows().length === 0) {
      Column() {
        Text($r('app.string.workspace_empty_activity'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
      }
      .layoutWeight(1)
      .width(Layout.contentWidth)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
    } else {
      List({ space: Spacing.sm }) {
        ForEach(this.getActivityRows(), (row: WorkspaceActivityRow, index: number) => {
          ListItem() {
            Row() {
              Text(row.time)
                .fontSize(FontSize.xs)
                .fontColor(Colors.foregroundMuted)
                .width(72)
              Column() {
                Text(row.actor)
                  .fontSize(FontSize.sm)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Colors.foreground)
                Text(row.content)
                  .fontSize(FontSize.sm)
                  .fontColor(Colors.foregroundMuted)
                  .margin({ top: 2 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(Spacing.md)
          .stateStyles({
            pressed: {
              .backgroundColor(Colors.surface1)
            },
            normal: {
              .backgroundColor(Colors.transparent)
            }
          })
        }
        }, (row: WorkspaceActivityRow, index: number) => row.actor + row.content + index.toString())
      }
      .layoutWeight(1)
      .width(Layout.contentWidth)
      .padding({ bottom: Spacing.xxxl })
    }
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
    .backgroundColor(Colors.surface0)
    .borderRadius(Radius.full)
  }
}
