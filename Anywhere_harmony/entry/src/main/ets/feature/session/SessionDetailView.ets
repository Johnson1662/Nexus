import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore, PlanEntry } from '../../common/model/ChatState';
import { MessageData } from '../../common/model/MessageData';

@Component
export struct SessionDetailView {
  @Prop session: ServerSession = new ServerSession();
  onOpenChat?: () => void;
  @State showDetails: boolean = false;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  getTitle(): string {
    if (ChatStore.sessionTitle.length > 0) return ChatStore.sessionTitle;
    if (this.session.title.length > 0) return this.session.title;
    return this.text($r('app.string.session_untitled'));
  }

  getAgent(): string {
    if (this.session.agent && this.session.agent.length > 0) return this.session.agent;
    return ChatStore.selectedAgentName || ChatStore.agentType || 'Agent';
  }

  getUserRequest(): string {
    for (let i: number = 0; i < ChatStore.messages.length; i++) {
      let message: MessageData = ChatStore.messages[i];
      if (message.role === 'user' && message.content.length > 0) {
        return message.content;
      }
    }
    return this.getTitle();
  }

  getStatusText(): string {
    if (ChatStore.turnActive) return 'Running';
    if (ChatStore.messages.length > 0) return 'Completed';
    return 'Idle';
  }

  getStatusColor(): ResourceColor {
    if (ChatStore.turnActive) return Colors.accent;
    if (ChatStore.messages.length > 0) return Colors.success;
    return Colors.foregroundMuted;
  }

  formatTime(epoch: number): string {
    if (!epoch || epoch <= 0) return '--:--';
    let date: Date = new Date(epoch);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
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

  getToolMessages(): MessageData[] {
    let calls: MessageData[] = [];
    for (let i: number = 0; i < ChatStore.messages.length; i++) {
      let message: MessageData = ChatStore.messages[i];
      if (message.type === 'tool_call') {
        calls.push(message);
      }
    }
    return calls;
  }

  getFileMessages(): MessageData[] {
    let files: MessageData[] = [];
    let tools: MessageData[] = this.getToolMessages();
    for (let i: number = 0; i < tools.length; i++) {
      if (tools[i].toolPath.length > 0 || tools[i].toolKind === 'edit' || tools[i].toolKind === 'write') {
        files.push(tools[i]);
      }
    }
    return files;
  }

  getProgressPercent(): number {
    if (ChatStore.planEntries.length === 0) {
      if (ChatStore.turnActive) return 20;
      return ChatStore.messages.length > 0 ? 100 : 0;
    }
    let completed: number = 0;
    for (let i: number = 0; i < ChatStore.planEntries.length; i++) {
      if (ChatStore.planEntries[i].status === 'completed') {
        completed += 1;
      }
    }
    return Math.floor((completed / ChatStore.planEntries.length) * 100);
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          this.HeaderSection()
          this.RunStatusSection()
          this.ActivityFeedSection()
          this.ChangedFilesSection()
          this.OpenChatButton()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: Spacing.xxxl })
        .backgroundColor(Colors.surface0)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .hideTitleBar(false)
    .title(this.getTitle())
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderSection() {
    Column() {
      Text(this.getTitle())
        .fontSize(FontSize.xxxl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: Spacing.xs })

      Row() {
        Text(this.getAgent())
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
        Text('·')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ left: Spacing.xs, right: Spacing.xs })
        Text(this.formatRelativeTime(this.session.createdAt))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.xxxl, left: Spacing.xl, right: Spacing.xl, bottom: Spacing.md })
  }

  @Builder
  RunStatusSection() {
    Column() {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill(this.getStatusColor())
          .margin({ right: Spacing.sm })

        Text(this.getStatusText())
          .fontSize(FontSize.sm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)

        Blank()

        Text(this.getAgent())
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
      }
      .width('100%')
      .margin({ bottom: Spacing.md })

      Text(this.getUserRequest())
        .fontSize(FontSize.md)
        .fontColor(Colors.foreground)
        .lineHeight(24)
        .width('100%')
        .margin({ bottom: Spacing.lg })

      if (ChatStore.turnActive) {
        Row() {
          Text(this.text($r('app.string.session_progress')))
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
          Blank()
          Text(this.getProgressPercent().toString() + '%')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .margin({ bottom: Spacing.md })

        Progress({ value: this.getProgressPercent(), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(Colors.foreground)
          .backgroundColor(Colors.surface1)
          .margin({ bottom: Spacing.md })

        if (ChatStore.planEntries.length > 0) {
          ForEach(ChatStore.planEntries, (entry: PlanEntry) => {
            this.PlanRow(entry.content, entry.status)
          }, (entry: PlanEntry) => entry.content + entry.status)
        } else {
          this.PlanRow(this.text($r('app.string.session_plan_waiting')), 'in_progress')
        }

        Text('Started ' + this.formatRelativeTime(this.session.createdAt))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.sm })
          .width('100%')
      } else if (ChatStore.messages.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Colors.success])
            .margin({ right: Spacing.sm })
          Text(this.text($r('app.string.session_turn_finished')))
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
        }
        .width('100%')
        .margin({ bottom: Spacing.md })

        if (ChatStore.lastUsage) {
          Row() {
            Text('Tokens: ' + ChatStore.lastUsage.totalTokens.toString())
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
          }
          .width('100%')
        }
      }
    }
    .width(Layout.contentWidth)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.md, bottom: Spacing.xl })
  }

  @Builder
  PlanRow(content: string, status: string) {
    Row() {
      if (status === 'completed') {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([Colors.foregroundMuted])
          .margin({ right: Spacing.md })
      } else if (status === 'in_progress') {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(16)
          .fontColor([Colors.foreground])
          .margin({ right: Spacing.md })
      } else {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(16)
          .fontColor([Colors.surface1])
          .margin({ right: Spacing.md })
      }

      Text(content)
        .fontSize(FontSize.sm)
        .fontColor(status === 'pending' ? Colors.foregroundMuted : Colors.foreground)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: Spacing.sm, bottom: Spacing.sm })
  }

  @Builder
  ActivityFeedSection() {
    Column() {
      this.TimelineEvent(
        this.formatTime(this.session.createdAt),
        this.text($r('app.string.session_timeline_started')),
        this.getUserRequest()
      )

      ForEach(this.getToolMessages(), (message: MessageData) => {
        this.TimelineEvent(
          this.formatTime(message.timestamp),
          message.toolName || this.text($r('app.string.session_tool_call')),
          message.toolPath || message.toolContent || message.content || this.text($r('app.string.session_tool_running'))
        )
      }, (message: MessageData) => message.toolCallId + message.toolStatus + message.toolContent.length.toString())

      if (ChatStore.turnActive) {
        this.TimelineEvent(
          this.formatTime(Date.now()),
          this.text($r('app.string.session_agent_working')),
          this.text($r('app.string.session_turn_active'))
        )
      } else if (ChatStore.messages.length > 0) {
        this.TimelineEvent(
          this.formatTime(Date.now()),
          this.text($r('app.string.session_turn_finished')),
          this.text($r('app.string.session_turn_finished_detail'))
        )
      }

      this.DetailsSection()
    }
    .width(Layout.contentWidth)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.md, bottom: Spacing.xl })
  }

  @Builder
  TimelineEvent(time: string, type: string, content: string) {
    Row() {
      Text(time)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
        .width(56)

      Column() {
        Circle({ width: 8, height: 8 })
          .fill(Colors.foregroundMuted)
          .margin({ top: 4 })
        Column()
          .width(1)
          .height(44)
          .backgroundColor(Colors.surface1)
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ right: Spacing.md })

      Column() {
        Text(type)
          .fontSize(FontSize.sm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
        Text(content)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.xxs })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: Spacing.sm, bottom: Spacing.sm, left: Spacing.sm, right: Spacing.sm })
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.md)
    .stateStyles({
      normal: {
        .backgroundColor(Colors.transparent)
      },
      pressed: {
        .backgroundColor(Colors.surface1)
      }
    })
  }

  @Builder
  DetailsSection() {
    Column() {
      Button() {
        Row() {
          Text('Details')
            .fontSize(FontSize.sm)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
          Blank()
          Text(this.showDetails ? '▲' : '▼')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
      }
      .type(ButtonType.Normal)
      .backgroundColor(Colors.transparent)
      .padding({ top: Spacing.md, bottom: Spacing.md })
      .onClick(() => { this.showDetails = !this.showDetails; })
      .stateStyles({
        normal: {
          .backgroundColor(Colors.transparent)
        },
        pressed: {
          .backgroundColor(Colors.surface1)
        }
      })

      if (this.showDetails) {
        Column() {
          this.LogRow(this.text($r('app.string.session_log_session_id')), this.session.sessionId || ChatStore.acpSessionId || '—')
          this.LogRow(this.text($r('app.string.session_log_bridge_session')), ChatStore.bridgeSessionId || '—')
          this.LogRow(this.text($r('app.string.session_log_model')), ChatStore.sessionCurrentModelId || ChatStore.lastModelId || '—')
          this.LogRow(this.text($r('app.string.session_log_token_usage')), ChatStore.lastUsage ? ChatStore.lastUsage.totalTokens.toString() : '—')
          this.LogRow(this.text($r('app.string.session_log_workspace')), this.session.cwd || '—')
        }
        .width('100%')
        .padding({ top: Spacing.sm })
      }
    }
    .width('100%')
    .margin({ top: Spacing.md })
  }

  @Builder
  LogRow(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(FontSize.xs)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.foregroundMuted)
        .width('100%')
        .margin({ bottom: Spacing.xs })
      Text(value)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foreground)
        .width('100%')
        .fontFamily('monospace')
    }
    .width('100%')
    .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.sm, right: Spacing.sm })
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.md)
    .stateStyles({
      normal: {
        .backgroundColor(Colors.transparent)
      },
      pressed: {
        .backgroundColor(Colors.surface1)
      }
    })
    .margin({ bottom: Spacing.xs })
  }

  @Builder
  ChangedFilesSection() {
    Column() {
      Text(this.text($r('app.string.session_files_title')))
        .fontSize(FontSize.md)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.md })

      if (this.getFileMessages().length === 0) {
        this.FileRow(this.text($r('app.string.session_files_empty')), '+0', '-0')
      } else {
        ForEach(this.getFileMessages(), (message: MessageData) => {
          this.FileRow(
            message.toolPath || message.toolName || this.text($r('app.string.session_unnamed_file')),
            message.toolNewText.length > 0 ? '+' + message.toolNewText.split('\n').length.toString() : '+?',
            message.toolOldText.length > 0 ? '-' + message.toolOldText.split('\n').length.toString() : '-?'
          )
        }, (message: MessageData) => message.toolCallId + message.toolPath)
      }
    }
    .width(Layout.contentWidth)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.md, bottom: Spacing.xl })
  }

  @Builder
  FileRow(name: string, add: string, remove: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.doc'))
        .fontSize(18)
        .fontColor([Colors.foregroundMuted])
        .margin({ right: Spacing.md })
      Text(name)
        .fontSize(FontSize.sm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.foreground)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(add)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
        .margin({ right: Spacing.sm })
      Text(remove)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
    }
    .width('100%')
    .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.sm, right: Spacing.sm })
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.md)
    .stateStyles({
      normal: {
        .backgroundColor(Colors.transparent)
      },
      pressed: {
        .backgroundColor(Colors.surface1)
      }
    })
    .margin({ bottom: Spacing.xs })
  }

  @Builder
  OpenChatButton() {
    Button('Open chat')
      .type(ButtonType.Normal)
      .width(Layout.contentWidth)
      .height(48)
      .fontSize(FontSize.md)
      .fontWeight(FontWeight.Medium)
      .fontColor(Colors.surface0)
      .backgroundColor(Colors.foreground)
      .borderRadius(Radius.lg)
      .margin({ top: Spacing.lg, bottom: Spacing.xxl })
      .onClick(() => {
        if (this.onOpenChat) {
          this.onOpenChat();
        }
      })
      .stateStyles({
        normal: {
          .backgroundColor(Colors.foreground)
        },
        pressed: {
          .backgroundColor(Colors.foregroundMuted)
        }
      })
  }
}
