import { Colors, FontSize, Spacing, Radius, Duration, Shadow } from '../../constants/DesignTokens';
import { CardHeader } from './CardHeader';
import { ThinkingSection } from './ThinkingSection';
import { ToolCallCard } from './ToolCallCard';
import { MarkdownRender } from './MarkdownRender';
import pasteboard from '@ohos.pasteboard';

@Component
@Reusable
export struct MessageCard {
  @State isUser: boolean = false;
  @State time: string = '';
  @State status: string = '';
  @State msgContent: string = '';
  @State msgType: string = 'text';
  @State msgToolName: string = '';
  @State msgToolStatus: string = '';
  @State streaming: boolean = false;

  aboutToReuse(params: Record<string, object>): void {
    this.isUser = Boolean(params['isUser']);
    this.time = String(params['time']);
    this.status = String(params['status']);
    this.msgContent = String(params['msgContent']);
    this.msgType = String(params['msgType']) || 'text';
    this.msgToolName = String(params['msgToolName']);
    this.msgToolStatus = String(params['msgToolStatus']);
    this.streaming = Boolean(params['streaming']);
  }

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
        SymbolGlyph($r('sys.symbol.doc'))
          .fontSize(FontSize.sm)
          .fontColor([Colors.foregroundLight])
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
    .backgroundColor(this.isUser ? Colors.surface0 : Colors.surfaceElevated)
    .margin({ top: Spacing.xs, bottom: Spacing.xs })
    .shadow(Shadow.sm)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
    .animation({ duration: Duration.normal, curve: Curve.EaseOut })
  }
}
