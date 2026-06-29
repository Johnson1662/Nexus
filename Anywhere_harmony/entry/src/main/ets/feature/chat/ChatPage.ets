import { Colors, FontSize, Spacing, Radius, Duration, Shadow, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { MessageData } from '../../common/model/MessageData';
import { MessageCard } from '../../common/ui/MessageCard';
import { ThinkingSection } from '../../common/ui/ThinkingSection';
import { PlanView } from '../../common/ui/PlanView';
import { MessageDataSource, messageLazyKey } from '../../common/ui/MessageDataSource';

interface MessageMargin {
  top: number;
  bottom: number;
}

@Component
struct PulsingDots {
  @State phase: number = 0;
  private timer: number = 0;

  aboutToAppear(): void {
    this.timer = setInterval((): void => {
      this.phase = (this.phase + 1) % 3;
    }, 250);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  build() {
    Row({ space: 5 }) {
      ForEach([0, 1, 2], (idx: number) => {
        Circle()
          .width(4)
          .height(4)
          .fill(Colors.accent)
          .opacity(this.phase === idx ? 1.0 : 0.3)
          .animation({ duration: 150, curve: Curve.EaseOut })
      }, (idx: number) => idx.toString())
    }
  }
}

@Component
export struct ChatPage {
  @Prop @Watch('onMessagesChange') messages: MessageData[] = [];
  @Prop @Watch('onStreamingChange') streamingThinking: string = '';
  onSendMessage?: (text: string) => void;
  onRetry?: (id: string, content: string) => void;

  private scroller: Scroller = new Scroller();
  private dataSource: MessageDataSource = new MessageDataSource([]);

  @State iconScale: number = 1.0;
  @State followsOutput: boolean = true;
  @State showJumpButton: boolean = false;
  @State messageMargins: Array<MessageMargin> = [];
  @State streamingTailMsgId: string = '';

  localize(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  private marginForIndex(index: number): MessageMargin {
    let top = Spacing.sm;
    let bottom = Spacing.sm;
    if (index === 0) {
      top = Spacing.md;
    } else if (this.messages[index - 1].role !== this.messages[index].role) {
      top = Spacing.xl;
    }
    if (index === this.messages.length - 1) {
      bottom = Spacing.xl;
    }
    return { top: top, bottom: bottom };
  }

  private computeMessageMargins(): Array<MessageMargin> {
    let margins: Array<MessageMargin> = [];
    for (let i = 0; i < this.messages.length; i++) {
      margins.push(this.marginForIndex(i));
    }
    return margins;
  }

  private refreshStreamingTailId(): void {
    this.streamingTailMsgId = '';
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === 'assistant') {
        this.streamingTailMsgId = this.messages[i].id;
        return;
      }
    }
  }

  private syncMessageMargins(prevLen: number): void {
    const nextLen: number = this.messages.length;
    if (nextLen === 0) {
      this.messageMargins = [];
      return;
    }
    if (this.messageMargins.length !== prevLen) {
      this.messageMargins = this.computeMessageMargins();
      return;
    }
    if (nextLen > prevLen) {
      for (let i = prevLen; i < nextLen; i++) {
        this.messageMargins.push(this.marginForIndex(i));
      }
      if (prevLen > 0) {
        const prevLast: number = prevLen - 1;
        this.messageMargins[prevLast] = this.marginForIndex(prevLast);
      }
      return;
    }
    if (nextLen < prevLen) {
      this.messageMargins = this.messageMargins.slice(0, nextLen);
      if (nextLen > 0) {
        this.messageMargins[nextLen - 1] = this.marginForIndex(nextLen - 1);
      }
      return;
    }
    const last: number = nextLen - 1;
    this.messageMargins[last] = this.marginForIndex(last);
    if (last > 0 && this.messages[last - 1].role !== this.messages[last].role) {
      this.messageMargins[last - 1] = this.marginForIndex(last - 1);
    }
  }

  aboutToAppear(): void {
    this.dataSource = new MessageDataSource(this.messages);
    this.messageMargins = this.computeMessageMargins();
    this.refreshStreamingTailId();
    setTimeout(() => {
      this.iconScale = 1.08;
    }, 100);
  }

  onMessagesChange(): void {
    const prevLen: number = this.dataSource.totalCount();
    this.dataSource.updateData(this.messages);
    this.syncMessageMargins(prevLen);
    this.refreshStreamingTailId();
    if (this.followsOutput) {
      setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 50);
    }
  }

  onStreamingChange(): void {
    if (this.followsOutput) {
      setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 50);
    }
  }

  getReconnectBannerText(): string {
    let phase: string = ChatStore.reconnectPhase;
    if (phase === 'disconnected') {
      return getContext(this).resourceManager.getStringSync($r('app.string.chat_reconnect_disconnected').id);
    } else if (phase === 'reconnecting') {
      return getContext(this).resourceManager.getStringSync($r('app.string.chat_reconnect_reconnecting').id, ChatStore.reconnectAttempt);
    } else if (phase === 'syncing') {
      return getContext(this).resourceManager.getStringSync($r('app.string.chat_reconnect_syncing').id);
    }
    return '';
  }

  hasSelectedAgent(): boolean {
    return (ChatStore.selectedAgentName || ChatStore.agentType).length > 0;
  }

  private isSameDay(ts1: number, ts2: number): boolean {
    if (!ts1 || !ts2) return false;
    let d1 = new Date(ts1);
    let d2 = new Date(ts2);
    return d1.getFullYear() === d2.getFullYear() && d1.getMonth() === d2.getMonth() && d1.getDate() === d2.getDate();
  }

  private formatDateDivider(ts: number): string {
    if (!ts) return '';
    let now = new Date();
    let d = new Date(ts);
    let diffDays = Math.floor((now.getTime() - d.getTime()) / 86400000);
    if (diffDays === 0) return '今天';
    if (diffDays === 1) return '昨天';
    return (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }

  @Builder
  DateDivider(ts: number) {
    Row() {
      Text(this.formatDateDivider(ts))
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: Spacing.lg, bottom: Spacing.sm })
  }

  build() {
    Column() {
      if (ChatStore.reconnectPhase.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(14)
            .fontColor([Colors.warning])
            .margin({ right: Spacing.sm })
          Text(this.getReconnectBannerText())
            .fontSize(FontSize.sm).fontColor(Colors.warningFgDark).fontWeight(FontWeight.Medium)
            .layoutWeight(1)
        }
        .width(Layout.contentWidth)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
        .backgroundColor(Colors.warningLight)
        .borderRadius(Radius.md)
        .margin({ top: Spacing.sm, bottom: Spacing.xs })
      }

      if (ChatStore.loadingSession) {
        Row() {
          LoadingProgress().width(20).height(20).color(Colors.accent)
          Text($r('app.string.chat_loading_session'))
            .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
            .margin({ left: Spacing.sm })
        }
        .width(Layout.contentWidth)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
        .margin({ top: Spacing.xs, bottom: Spacing.xs })
        .transition(TransitionEffect.OPACITY)
        .accessibilityText(this.localize($r('app.string.chat_loading_session')))
      }

      if (this.messages.length === 0) {
        Column() {
          if (ChatStore.turnActive) {
            Column() {
              LoadingProgress().width(20).height(20).color(Colors.accent)
              Text($r('app.string.chat_waiting_response'))
                .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
                .margin({ top: Spacing.sm })
            }
            .alignItems(HorizontalAlign.Center)
            .transition(TransitionEffect.OPACITY)
            .animation({ duration: Duration.fast, curve: Curve.EaseInOut })
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.ellipsis_message'))
                .fontSize(40)
                .fontColor([Colors.foregroundMuted])
                .opacity(0.25)
                .margin({ bottom: Spacing.lg })
              Text($r('app.string.chat_empty_title'))
                .fontSize(FontSize.headingLg)
                .fontWeight(FontWeight.Bold)
                .fontColor(Colors.foreground)
              Text($r('app.string.chat_empty_subtitle'))
                .fontSize(FontSize.lg)
                .fontColor(Colors.foregroundMuted)
                .margin({ top: Spacing.sm })
            }
            .alignItems(HorizontalAlign.Center)
            .transition(TransitionEffect.OPACITY)
            .animation({ duration: Duration.normal, curve: Curve.EaseOut })
          }
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xxl, bottom: Spacing.xxl })
      } else {
        List({ scroller: this.scroller }) {
          LazyForEach(this.dataSource, (msg: MessageData, index: number) => {
            ListItem() {
              Column() {
                if (index > 0 && !this.isSameDay(this.dataSource.getData(index - 1).timestamp, msg.timestamp)) {
                  this.DateDivider(msg.timestamp)
                }

                if (msg.type === 'plan') {
                  PlanView({ entries: ChatStore.planEntries })
                    .width('100%')
                    .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.xs, bottom: Spacing.xs })
                } else {
                  MessageCard({
                    isUser: msg.role === 'user',
                    msgId: msg.id,
                    msgSendStatus: msg.sendStatus,
                    time: this.formatTime(msg.timestamp),
                    status: (msg.role === 'assistant' && msg.type === 'text'
                      && ChatStore.turnActive) ? this.localize($r('app.string.common_running')) : '',
                    msgContent: msg.content,
                    msgType: msg.type,
                    msgToolName: msg.toolName,
                    msgToolStatus: msg.toolStatus,
                    msgToolKind: msg.toolKind,
                    msgToolContent: msg.toolContent,
                    msgToolContentType: msg.toolContentType,
                    msgToolPath: msg.toolPath,
                    msgToolOldText: msg.toolOldText,
                    msgToolNewText: msg.toolNewText,
                    msgToolTerminalId: msg.toolTerminalId,
                    streaming: ChatStore.turnActive && msg.role === 'assistant' && msg.id === this.streamingTailMsgId,
                    onRetry: (id: string, content: string) => { if (this.onRetry !== undefined) this.onRetry(id, content) }
                  })
                }
              }
            }
            .height('auto')
            .margin(this.messageMargins[index])
          }, (msg: MessageData) => messageLazyKey(msg))

          if (this.streamingThinking.length > 0 && ChatStore.turnActive) {
            ListItem() {
              ThinkingSection({ thinking: this.streamingThinking, isStreaming: true })
                .width('100%')
                .padding({ left: Spacing.lg, right: Spacing.lg })
            }
            .height('auto')
            .margin({ top: Spacing.sm, bottom: Spacing.md })
          }

          if (ChatStore.turnActive) {
            ListItem() {
              PulsingDots()
                .padding({ left: Spacing.lg, top: Spacing.xs, bottom: Spacing.xs })
            }
            .margin({ top: Spacing.sm, bottom: Spacing.md })
            .transition(TransitionEffect.OPACITY)
          }

          if (!ChatStore.turnActive && ChatStore.lastUsage !== null && this.messages.length > 0) {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.xs })
                Text(this.localize($r('app.string.chat_tokens_usage'), ChatStore.lastUsage!.totalTokens))
                  .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted).fontWeight(FontWeight.Medium)
                Blank()
                Text($r('app.string.chat_done')).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
              }
              .width('100%')
              .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.md })
            }
            .margin({ top: Spacing.sm, bottom: Spacing.md })
            .transition(TransitionEffect.OPACITY)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .onScrollStart(() => { this.followsOutput = false; this.showJumpButton = true; })
        .onScrollStop(() => {
          if (ChatStore.turnActive) {
            this.showJumpButton = true;
          }
        })
      }

      if (this.showJumpButton && ChatStore.turnActive) {
        Button() {
          Row({ space: Spacing.xs }) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([Colors.foreground])
            Text($r('app.string.chat_jump_latest_label'))
              .fontSize(FontSize.xs)
              .fontColor(Colors.foreground)
              .fontWeight(FontWeight.Medium)
          }
        }
        .height(32)
        .padding({ left: Spacing.lg, right: Spacing.lg })
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.full)
        .shadow(Shadow.sm)
        .stateStyles({
          pressed: { .backgroundColor(Colors.surface1) },
          normal: { .backgroundColor(Colors.surfaceElevated) }
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
        .alignSelf(ItemAlign.End)
        .margin({ right: Spacing.xl, bottom: Spacing.lg })
        .onClick(() => {
          this.scroller.scrollEdge(Edge.Bottom);
          this.followsOutput = true;
          this.showJumpButton = false;
        })
      }
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.surface0)
  }

  formatTime(ts: number): string {
    if (!ts) return '';
    let d = Date.now() - ts;
    let m = Math.floor(d / 60000);
    if (m < 1) return this.localize($r('app.string.common_now'));
    if (m < 60) return this.localize($r('app.string.common_minutes_ago'), m);
    let h = Math.floor(m / 60);
    if (h < 24) return this.localize($r('app.string.common_hours_ago'), h);
    let date = new Date(ts);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
  }
}
