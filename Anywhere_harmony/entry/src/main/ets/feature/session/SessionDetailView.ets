import { Colors, FontSize, Spacing, Radius, Shadow, Layout } from '../../constants/DesignTokens';
import { ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore, PlanEntry } from '../../common/model/ChatState';
import { MessageData } from '../../common/model/MessageData';

@Component
export struct SessionDetailView {
  @Prop session: ServerSession = new ServerSession();

  @State detailTabIndex: number = 0;
  @State composerText: string = '';

  getTitle(): string {
    if (ChatStore.sessionTitle.length > 0) return ChatStore.sessionTitle;
    if (this.session.title.length > 0) return this.session.title;
    return 'Untitled session';
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

  formatTime(epoch: number): string {
    if (!epoch || epoch <= 0) return '--:--';
    let date: Date = new Date(epoch);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
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

  getConversationPreview(): string {
    for (let i: number = ChatStore.messages.length - 1; i >= 0; i--) {
      let message: MessageData = ChatStore.messages[i];
      if (message.role === 'assistant' && message.type === 'text' && message.content.length > 0) {
        return message.content;
      }
    }
    if (ChatStore.streamingText.length > 0) {
      return ChatStore.streamingText;
    }
    return '会话内容加载后会显示在这里。';
  }

  build() {
    NavDestination() {
      Column() {
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

        Row({ space: Spacing.sm }) {
          this.TabButton('Conversation', 0)
          this.TabButton('Timeline', 1)
          this.TabButton('Files', 2)
          this.TabButton('Logs', 3)
        }
        .width(Layout.contentWidth)
        .padding({ bottom: Spacing.md })

        if (this.detailTabIndex === 0) {
          this.ConversationTab()
        } else if (this.detailTabIndex === 1) {
          this.TimelineTab()
        } else if (this.detailTabIndex === 2) {
          this.FilesTab()
        } else {
          this.LogsTab()
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)

    .width('100%')
    .height('100%')
  }

  @Builder
  TabButton(label: string, idx: number) {
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
  ConversationTab() {
    Column() {
      Scroll() {
        Column() {
          if (ChatStore.loadingSession) {
            Row() {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(Colors.foreground)
                .margin({ right: Spacing.sm })
              Text('正在加载会话历史...')
                .fontSize(FontSize.sm)
                .fontColor(Colors.foregroundMuted)
            }
            .width(Layout.contentWidth)
            .padding({ top: Spacing.md, bottom: Spacing.md })
            .margin({ bottom: Spacing.lg })
          }

          Column() {
            Text('用户任务')
              .fontSize(FontSize.xs)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.foregroundMuted)
              .margin({ bottom: Spacing.sm })
            Text(this.getUserRequest())
              .fontSize(FontSize.md)
              .fontColor(Colors.foreground)
              .lineHeight(24)
          }
          .width(Layout.contentWidth)
          .alignItems(HorizontalAlign.Start)
          .padding({ top: Spacing.md, bottom: Spacing.xl })

          Column() {
            Row() {
              Text('执行进度')
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
              .margin({ bottom: Spacing.lg })

            if (ChatStore.planEntries.length > 0) {
              ForEach(ChatStore.planEntries, (entry: PlanEntry) => {
                this.PlanRow(entry.content, entry.status)
              }, (entry: PlanEntry) => entry.content + entry.status)
            } else {
              this.PlanRow('等待 Agent 返回执行步骤', ChatStore.turnActive ? 'in_progress' : 'pending')
            }
          }
          .width(Layout.contentWidth)
          .alignItems(HorizontalAlign.Start)
          .padding({ top: Spacing.md, bottom: Spacing.xl })

          Column() {
            Text('最新输出')
              .fontSize(FontSize.md)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.foreground)
              .margin({ bottom: Spacing.md })
            Text(this.getConversationPreview())
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
              .lineHeight(24)
              .maxLines(10)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width(Layout.contentWidth)
          .alignItems(HorizontalAlign.Start)
          .padding({ top: Spacing.md, bottom: Spacing.xl })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: Spacing.xl })
      }
      .layoutWeight(1)

      Row() {
        TextInput({ placeholder: '继续追问这个会话...', text: this.composerText })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.full)
          .padding({ left: Spacing.lg, right: Spacing.lg })
          .fontSize(FontSize.sm)
          .fontColor(Colors.foreground)
          .placeholderColor(Colors.foregroundMuted)
          .onChange((value: string) => { this.composerText = value; })
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_up_circle_fill'))
            .fontSize(32)
            .fontColor([Colors.foreground])
        }
        .width(44)
        .height(44)
        .backgroundColor(Colors.transparent)
        .margin({ left: Spacing.sm })
      }
      .width(Layout.contentWidth)
      .padding({ top: Spacing.md, bottom: Spacing.xl })
      .backgroundColor(Colors.surface0)
    }
    .layoutWeight(1)
    .width('100%')
    .alignItems(HorizontalAlign.Center)
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
  TimelineTab() {
    Scroll() {
      Column() {
        this.TimelineEvent(this.formatTime(this.session.createdAt), 'Session started', this.getUserRequest())
        ForEach(this.getToolMessages(), (message: MessageData) => {
          this.TimelineEvent(
            this.formatTime(message.timestamp),
            message.toolName || 'Tool call',
            message.toolPath || message.toolContent || message.content || '工具调用执行中'
          )
        }, (message: MessageData) => message.toolCallId + message.toolStatus + message.toolContent.length.toString())
        if (ChatStore.turnActive) {
          this.TimelineEvent(this.formatTime(Date.now()), 'Agent working', '当前轮次仍在执行')
        } else if (ChatStore.messages.length > 0) {
          this.TimelineEvent(this.formatTime(Date.now()), 'Turn finished', '当前轮次已经结束')
        }
      }
      .width(Layout.contentWidth)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: Spacing.md, bottom: Spacing.xxxl })
    }
    .layoutWeight(1)
    .width('100%')
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
  FilesTab() {
    Scroll() {
      Column() {
        Text('文件变更')
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .width('100%')
          .margin({ bottom: Spacing.md })

        if (this.getFileMessages().length === 0) {
          this.FileRow('当前没有可提取的文件变更记录', '+0', '-0')
        } else {
          ForEach(this.getFileMessages(), (message: MessageData) => {
            this.FileRow(
              message.toolPath || message.toolName || '未命名文件',
              message.toolNewText.length > 0 ? '+' + message.toolNewText.split('\n').length.toString() : '+?',
              message.toolOldText.length > 0 ? '-' + message.toolOldText.split('\n').length.toString() : '-?'
            )
          }, (message: MessageData) => message.toolCallId + message.toolPath)
        }
      }
      .width(Layout.contentWidth)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: Spacing.md, bottom: Spacing.xxxl })
    }
    .layoutWeight(1)
    .width('100%')
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
  LogsTab() {
    Scroll() {
      Column() {
        this.LogRow('Session ID', this.session.sessionId || ChatStore.acpSessionId || '—')
        this.LogRow('Bridge Session', ChatStore.bridgeSessionId || '—')
        this.LogRow('Model', ChatStore.sessionCurrentModelId || ChatStore.lastModelId || '—')
        this.LogRow('Token Usage', ChatStore.lastUsage ? ChatStore.lastUsage.totalTokens.toString() : '—')
        this.LogRow('Workspace', this.session.cwd || '—')
      }
      .width(Layout.contentWidth)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: Spacing.md, bottom: Spacing.xxxl })
    }
    .layoutWeight(1)
    .width('100%')
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
}
