import { Colors } from '../constants/Colors';
import { MessageData } from '../store/SessionStore';
import { ToolCallCard } from './ToolCallCard';
import { ThinkingSection } from './ThinkingSection';
import { FontSize, Spacing, Radius, Duration } from '../constants/DesignTokens';

@Component
export struct MessageBubble {
  @Prop message: MessageData;

  private getTimestamp(): string {
    if (!this.message.timestamp) return '';

    const now = Date.now();
    const diff = now - this.message.timestamp;
    const sec = Math.floor(diff / 1000);

    if (sec < 60) return '刚刚';

    const min = Math.floor(sec / 60);
    if (min < 60) return min + '分钟前';

    const hour = Math.floor(min / 60);
    if (hour < 24) return hour + '小时前';

    const date = new Date(this.message.timestamp);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hourStr = date.getHours().toString().padStart(2, '0');
    const minStr = date.getMinutes().toString().padStart(2, '0');
    return month + '/' + day + ' ' + hourStr + ':' + minStr;
  }

  build() {
    Column() {
      if (this.message.role === 'user') {
        Column() {
          Column() {
            Text(this.message.content)
              .fontSize(FontSize.base)
              .fontColor(Color.White)
              .lineHeight(26)
              .maxLines(1000)

            Text(this.getTimestamp())
              .fontSize(FontSize.xs)
              .fontColor('#FFFFFFCC')
              .margin({ top: Spacing.xs })
              .alignSelf(ItemAlign.End)
          }
          .backgroundColor(Colors.userBubble)
          .borderRadius(Radius.lg)
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
          .constraintSize({ maxWidth: '70%' })
          .shadow({ radius: 8, color: Colors.shadowAccent, offsetY: 3 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.End)

      } else if (this.message.type === 'tool_call') {
        ToolCallCard({
          name: this.message.toolName ? this.message.toolName : 'Tool',
          status: this.message.toolStatus ? this.message.toolStatus : 'pending'
        })

      } else if (this.message.type === 'thinking') {
        Row() {
          Column() {
            ThinkingSection({ thinking: this.message.content })
          }
          .width('100%')
          .padding({ left: Spacing.sm, right: Spacing.sm })
        }
        .width('100%')

      } else {
        Row() {
          Column() {
            if (this.message.thinkingContent && this.message.thinkingContent.length > 0) {
              ThinkingSection({ thinking: this.message.thinkingContent })
              
              if (this.message.content && this.message.content.length > 0) {
                Divider()
                  .color(Colors.borderLight)
                  .margin({ top: Spacing.lg, bottom: Spacing.lg })
              }
            }

            if (this.message.content && this.message.content.length > 0) {
              Column() {
                Text(this.message.content)
                  .fontSize(FontSize.base)
                  .fontColor(Colors.foreground)
                  .lineHeight(28)
                  .maxLines(1000)

                Row() {
                  Text(this.getTimestamp())
                    .fontSize(FontSize.xs)
                    .fontColor(Colors.foregroundLight)
                }
                .margin({ top: Spacing.sm })
              }
            }
          }
          .backgroundColor(Colors.surfaceElevated)
          .borderRadius(Radius.lg)
          .border({ width: 1, color: Colors.borderLight })
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })
          .constraintSize({ maxWidth: '75%' })
          .shadow({ radius: 4, color: Colors.shadowColor, offsetY: 2 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
  }
}
