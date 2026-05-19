import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
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
  @State msgToolKind: string = '';
  @State msgToolContent: string = '';
  @State streaming: boolean = false;

  aboutToReuse(params: Record<string, object>): void {
    this.isUser = Boolean(params['isUser']);
    this.time = String(params['time']);
    this.status = String(params['status']);
    this.msgContent = String(params['msgContent']);
    this.msgType = String(params['msgType']) || 'text';
    this.msgToolName = String(params['msgToolName']);
    this.msgToolStatus = String(params['msgToolStatus']);
    this.msgToolKind = String(params['msgToolKind']);
    this.msgToolContent = String(params['msgToolContent']);
    this.streaming = Boolean(params['streaming']);
  }

  copyContent() {
    let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.msgContent);
    let systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      this.getUIContext().getPromptAction().openToast({ message: 'Copied' });
    });
  }

  build() {
    Row() {
      if (this.isUser) {
        Blank() // Push user message to the right
      }

      Column() {
        if (!this.isUser) {
          // Agent message: full width, no background, no border radius
          Column() {
            if (this.msgType === 'thinking') {
              ThinkingSection({ thinking: this.msgContent, isStreaming: this.streaming })
            } else if (this.msgType === 'tool_call') {
              ToolCallCard({ name: this.msgToolName, status: this.msgToolStatus, kind: this.msgToolKind, content: this.msgToolContent })
            } else {
              if (this.msgContent.length > 0) {
                if (this.streaming) {
                  Text(this.msgContent)
                    .fontSize(FontSize.base)
                    .fontColor(Colors.foreground)
                    .lineHeight(24)
                } else {
                  MarkdownRender({ text: this.msgContent })
                }
              }
            }
          }
          .padding({ 
            top: (this.msgType === 'thinking' || this.msgType === 'tool_call') ? 0 : Spacing.xs, 
            bottom: (this.msgType === 'thinking' || this.msgType === 'tool_call') ? 0 : Spacing.xs 
          })
          .alignItems(HorizontalAlign.Start)
          .width('100%')

        } else {
          // User message: right aligned, light gray bubble
          Column() {
            if (this.msgContent.length > 0) {
              Text(this.msgContent)
                .fontSize(FontSize.base)
                .fontColor(Colors.foreground)
                .lineHeight(22)
            }
          }
          .padding({ 
            top: Spacing.md, 
            bottom: Spacing.md, 
            left: Spacing.lg, 
            right: Spacing.lg 
          })
          .backgroundColor(Colors.userBubble)
          .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl, bottomLeft: Radius.xl, bottomRight: Radius.xs })
          .alignItems(HorizontalAlign.Start)
        }
      }
      .constraintSize(this.isUser ? { maxWidth: '85%' } : { minWidth: '100%' })
    }
    .width('100%')
    .padding({ 
      left: Spacing.lg, 
      right: Spacing.lg, 
      top: (this.msgType === 'thinking' || this.msgType === 'tool_call') ? 0 : Spacing.xs, 
      bottom: (this.msgType === 'thinking' || this.msgType === 'tool_call') ? 0 : Spacing.xs 
    })
    
  }
}
