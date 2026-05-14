import { Colors, FontSize, Spacing, Radius } from '../../constants/Colors';
import { CardHeader } from './CardHeader';
import { ThinkingSection } from './ThinkingSection';
import { ToolCallCard } from './ToolCallCard';
import { MarkdownRender } from './MarkdownRender';
import pasteboard from '@ohos.pasteboard';

@Component
export struct MessageCard {
  @Prop isUser: boolean = false;
  @Prop time: string = '';
  @Prop status: string = '';
  @Prop msgContent: string = '';
  @Prop msgType: string = 'text';
  @Prop msgToolName: string = '';
  @Prop msgToolStatus: string = '';
  @Prop streaming: boolean = false;

  copyContent() {
    let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.msgContent);
    let systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      this.getUIContext().getPromptAction().openToast({ message: 'Copied to clipboard' });
    });
  }

  build() {
    Column() {
      CardHeader({ role: this.isUser ? 'user' : 'agent', name: this.isUser ? 'You' : 'Agent', time: this.time, status: this.status })

      if (this.isUser) {
        Row() {
          Text(this.msgContent)
            .fontSize(FontSize.base)
            .fontColor(Colors.foreground)
            .lineHeight(24)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: Spacing.sm, bottom: Spacing.sm })
      } else {
        Column() {
          if (this.msgType === 'thinking') {
            ThinkingSection({ thinking: this.msgContent })
          } else if (this.msgType === 'tool_call') {
            ToolCallCard({ name: this.msgToolName, status: this.msgToolStatus })
          } else {
            if (this.msgContent.length > 0) {
              if (this.streaming) {
                Text(this.msgContent)
                  .fontSize(FontSize.base)
                  .fontColor(Colors.foreground)
                  .lineHeight(24)
                  .width('100%')
                  .padding({ top: Spacing.sm, bottom: Spacing.sm })
              } else {
                MarkdownRender({ text: this.msgContent })
                  .width('100%')
                  .padding({ top: Spacing.sm, bottom: Spacing.sm })
              }
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Row() {
        Image($r('app.media.ic_copy'))
          .fillColor(Colors.foregroundLight).width(16).height(16)
          .onClick(() => { this.copyContent() })
      }
      .width('100%')
      .justifyContent(this.isUser ? FlexAlign.End : FlexAlign.Start)
      .padding({ top: Spacing.xs, bottom: Spacing.md })
    }
    .width('100%')
    .padding({ left: Spacing.lg, right: Spacing.lg })
    .border({
      width: { left: this.isUser ? 0 : 3, right: this.isUser ? 3 : 0 },
      color: { left: Colors.borderLight, right: Colors.accent }
    })
    .backgroundColor(this.isUser ? Colors.surface0 : Colors.surface1)
    .margin({ top: Spacing.xs, bottom: Spacing.xs })
  }
}
