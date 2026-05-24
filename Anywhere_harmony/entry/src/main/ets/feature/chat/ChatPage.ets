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

  private scroller: Scroller = new Scroller();
  private dataSource: MessageDataSource = new MessageDataSource([]);

  @State iconScale: number = 1.0;

  aboutToAppear(): void {
    this.dataSource = new MessageDataSource(this.messages);
    setTimeout(() => {
      this.iconScale = 1.08;
    }, 100);
  }

  onMessagesChange(): void {
    this.dataSource.updateData(this.messages);
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  onStreamingChange(): void {
    // Scroll to follow streaming thinking output
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  build() {
    Column() {
      if (this.messages.length === 0) {
          Column() {
            if (ChatStore.loadingSession) {
              Column() {
                LoadingProgress().width(24).height(24).color(Colors.accent)
                Text('Loading session...')
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
                  .margin({ top: Spacing.sm })
              }
              .alignItems(HorizontalAlign.Center)
              .transition(TransitionEffect.OPACITY)
            } else if (ChatStore.turnActive) {
              Column() {
                LoadingProgress().width(20).height(20).color(Colors.accent)
                Text('Waiting for response')
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
                  .animation({ duration: 2500, curve: Curve.EaseInOut, playMode: PlayMode.Alternate, iterations: -1 })
Text('Anywhere')
  .fontSize(FontSize.xxl).fontColor(Colors.foreground).fontWeight(FontWeight.Bold).fontFamily('serif')
                Text('Select a workspace and start typing.')
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
                  time: this.formatTime(msg.timestamp),
                  status: (msg.role === 'assistant' && msg.type === 'text'
                    && ChatStore.turnActive) ? 'Running' : '',
                  msgContent: msg.content,
                  msgType: msg.type,
                  msgToolName: msg.toolName,
                  msgToolStatus: msg.toolStatus,
                  msgToolKind: msg.toolKind,
                  msgToolContent: msg.toolContent,
                  streaming: ChatStore.turnActive && msg.role === 'assistant' && msg.id === ChatStore.messages[ChatStore.messages.length - 1]?.id
                })
                  .margin({ bottom: msg.role === 'user' ? Spacing.lg : 0 })
              }
            }
            .height('auto')
            // Key includes content length so streaming text messages re-render
          }, (msg: MessageData) => msg.id + msg.content.length)

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
      }

      ChatInputBar({
        disabled: ChatStore.turnActive || !ChatStore.sessionReady,
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
