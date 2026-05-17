import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { MessageData } from '../../common/model/MessageData';
import { MessageCard } from '../../common/ui/MessageCard';
import { PlanView } from '../../common/ui/PlanView';
import { ChatInputBar } from './ChatInputBar';
import { MessageDataSource } from '../../common/ui/MessageDataSource';

@Component
export struct ChatPage {
  @Prop @Watch('onMessagesChange') messages: MessageData[] = [];
  onSendMessage?: (text: string) => void;

  private scroller: Scroller = new Scroller();
  private dataSource: MessageDataSource = new MessageDataSource([]);

  aboutToAppear(): void {
    this.dataSource = new MessageDataSource(this.messages);
  }

  onMessagesChange(): void {
    this.dataSource.updateData(this.messages);
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  build() {
    Column() {
      if (this.messages.length === 0) {
          Column() {
            if (ChatStore.turnActive) {
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
                Text('No active task')
                  .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
                Text('Type a message below to start a new session.')
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
                  .margin({ top: Spacing.xs })
              }
              .alignItems(HorizontalAlign.Center)
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
                  streaming: ChatStore.turnActive && msg.role === 'assistant' && msg.id === ChatStore.messages[ChatStore.messages.length - 1]?.id
                })
                  .margin({ bottom: msg.role === 'user' ? Spacing.lg : 0 })
              }
            }
            .height('auto')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
            .animation({ duration: Duration.normal, curve: Curve.EaseOut })
          }, (msg: MessageData) => msg.id + msg.content.length + msg.toolStatus + (ChatStore.turnActive ? '_active' : '_done'))
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .clip(false)
      }

      ChatInputBar({
        disabled: ChatStore.turnActive,
        onSend: (text) => { if (this.onSendMessage) this.onSendMessage(text); }
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
