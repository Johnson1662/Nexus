import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { MessageData } from '../../common/model/MessageData';
import { MessageCard } from '../../common/ui/MessageCard';
import { ThinkingSection } from '../../common/ui/ThinkingSection';
import { PlanView } from '../../common/ui/PlanView';
import { ChatInputBar } from './ChatInputBar';
import { MessageDataSource } from '../../common/ui/MessageDataSource';

@Component
struct PulsingDots {
  @State opacities: number[] = [0.3, 0.3, 0.3];

  aboutToAppear(): void {
    this.getUIContext()?.animateTo({ duration: 600, curve: Curve.EaseInOut, delay: 0, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.opacities[0] = 1.0;
    });
    this.getUIContext()?.animateTo({ duration: 600, curve: Curve.EaseInOut, delay: 200, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.opacities[1] = 1.0;
    });
    this.getUIContext()?.animateTo({ duration: 600, curve: Curve.EaseInOut, delay: 400, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.opacities[2] = 1.0;
    });
  }

  aboutToDisappear(): void {
    // Stop infinite animations by resetting to static values
    this.opacities = [0.3, 0.3, 0.3];
  }

  build() {
    Row({ space: 5 }) {
      Circle().width(6).height(6).fill(Colors.foregroundMuted)
        .opacity(this.opacities[0])
      Circle().width(6).height(6).fill(Colors.foregroundMuted)
        .opacity(this.opacities[1])
      Circle().width(6).height(6).fill(Colors.foregroundMuted)
        .opacity(this.opacities[2])
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
  @State followsOutput: boolean = true;   // Stage 2: scroll anchoring
  @State showJumpButton: boolean = false; // Stage 2: floating jump-to-bottom
  aboutToAppear(): void {
    this.dataSource = new MessageDataSource(this.messages);
    setTimeout(() => {
      this.iconScale = 1.08;
    }, 100);
  }

  onMessagesChange(): void {
    this.dataSource.updateData(this.messages);
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
      return getContext().resourceManager.getStringSync($r('app.string.chat_reconnect_disconnected'));
    } else if (phase === 'reconnecting') {
      return getContext().resourceManager.getStringSync($r('app.string.chat_reconnect_reconnecting'), ChatStore.reconnectAttempt);
    } else if (phase === 'syncing') {
      return getContext().resourceManager.getStringSync($r('app.string.chat_reconnect_syncing'));
    }
    return '';
  }

  build() {
    Column() {
      if (ChatStore.reconnectPhase.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(14).fontColor([Colors.warning]).margin({ right: Spacing.sm })
          Text(this.getReconnectBannerText())
            .fontSize(FontSize.sm).fontColor(Colors.warningFgDark).fontWeight(FontWeight.Medium)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
        .backgroundColor(Colors.warningLight)
      }

      if (ChatStore.loadingSession) {
        Row() {
          LoadingProgress().width(20).height(20).color(Colors.accent)
          Text($r('app.string.chat_loading_session'))
            .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
            .margin({ left: Spacing.sm })
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
        .transition(TransitionEffect.OPACITY)
        .accessibilityText('Loading session')
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
                Image($r('app.media.anywhere_logo'))
                  .width(44).height(44)
                  .fillColor(Colors.accent)
                  .margin({ bottom: Spacing.lg })
                  .opacity(0.3)
                  .scale({ x: this.iconScale, y: this.iconScale })
                  .animation({ duration: Duration.slow, curve: Curve.EaseOut })
                Text($r('app.string.app_name'))
                  .fontSize(FontSize.xxl).fontColor(Colors.foreground).fontWeight(FontWeight.Bold).fontFamily('serif')
                Text($r('app.string.chat_empty_prompt'))
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
                  .margin({ top: Spacing.xs })
              }
              .alignItems(HorizontalAlign.Center)
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
              .animation({ duration: Duration.normal, curve: Curve.EaseOut })
            }
          }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .padding({ left: Spacing.xxl, right: Spacing.xxl })
      } else {
        List({ scroller: this.scroller }) {
          LazyForEach(this.dataSource, (msg: MessageData) => {
            ListItem() {
              if (msg.type === 'plan') {
                PlanView({ entries: ChatStore.planEntries })
                  .width('100%')
                  .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.xs, bottom: Spacing.xs })
                  .margin({ bottom: Spacing.sm })
              } else {
                MessageCard({
                  isUser: msg.role === 'user',
                  msgId: msg.id,
                  msgSendStatus: msg.sendStatus,
                  time: this.formatTime(msg.timestamp),
                  status: (msg.role === 'assistant' && msg.type === 'text'
                    && ChatStore.turnActive) ? 'Running' : '',
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
                  streaming: ChatStore.turnActive && msg.role === 'assistant' && msg.id === ChatStore.messages[ChatStore.messages.length - 1]?.id,
                  onRetry: (id: string, content: string) => { if (this.onRetry) this.onRetry(id, content) }
                })
                  .margin({ bottom: Spacing.lg })
              }
            }
            .height('auto')
            // Key includes tool payload changes so tool cards re-render on output/diff updates
          }, (msg: MessageData) => msg.id + ':' + msg.content.length + ':' + msg.toolContent.length + ':' +
            msg.toolContentType + ':' + msg.toolOldText.length + ':' + msg.toolNewText.length + ':' + msg.toolStatus)

          // Streaming thinking section (outside LazyForEach — no key changes on chunks)
          if (ChatStore.streamingThinking.length > 0 && ChatStore.turnActive) {
            ListItem() {
              ThinkingSection({ thinking: ChatStore.streamingThinking, isStreaming: true })
                .width('100%')
                .padding({ left: Spacing.lg, right: Spacing.lg })
            }
            .height('auto')
          }

          if (ChatStore.turnActive) {
            ListItem() {
              PulsingDots()
                .padding({ left: Spacing.lg, top: Spacing.xs, bottom: Spacing.xs })
            }
            .transition(TransitionEffect.OPACITY)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .onScrollStart(() => { this.followsOutput = false; this.showJumpButton = true; })
      }

      // Stage 2: jump-to-bottom button when user has scrolled up during turn
      if (this.showJumpButton && ChatStore.turnActive) {
        Row() {
          Text($r('app.string.chat_jump_latest'))
            .fontSize(FontSize.xs).fontColor(Colors.accent)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%').justifyContent(FlexAlign.Center)
        .padding({ bottom: Spacing.xs })
        .transition(TransitionEffect.OPACITY)
        .onClick(() => { this.scroller.scrollEdge(Edge.Bottom); this.followsOutput = true; this.showJumpButton = false; })
      }

      ChatInputBar({
        disabled: ChatStore.turnActive || ChatStore.loadingSession,
        showCancel: ChatStore.turnActive,
        onSend: (text) => { if (this.onSendMessage) this.onSendMessage(text); },
        onCancel: () => { if (this.onSendMessage) this.onSendMessage('__cancel__'); }
      })
    }
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }

  formatTime(ts: number): string {
    if (!ts) return '';
    let d = Date.now() - ts;
    let m = Math.floor(d / 60000);
    if (m < 1) return 'now';
    if (m < 60) return m + 'm';
    let h = Math.floor(m / 60);
    if (h < 24) return h + 'h';
    let date = new Date(ts);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
  }
}
