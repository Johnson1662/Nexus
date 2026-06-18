import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { ThinkingSection } from './ThinkingSection';
import { ToolCallCard } from './ToolCallCard';
import { MarkdownRender } from './MarkdownRender';
import pasteboard from '@ohos.pasteboard';

interface FilePrefixInfo {
  fileType: string;
  fileName: string;
  dataUri: string;
  restText: string;
}

function parseFilePrefix(content: string): FilePrefixInfo {
  let result: FilePrefixInfo = { fileType: '', fileName: '', dataUri: '', restText: content };
  if (content.startsWith('[Image: ')) {
    let endBracket: number = content.indexOf(']\n');
    if (endBracket > 0) {
      let rawFileName: string = content.substring(8, endBracket);
      let after: string = content.substring(endBracket + 2);
      let rawDataUri: string = '';
      let rawRest: string = after;
      if (after.startsWith('data:')) {
        let nl: number = after.indexOf('\n');
        if (nl > 0) {
          rawDataUri = after.substring(0, nl);
          rawRest = after.substring(nl + 1);
        } else {
          rawDataUri = after;
          rawRest = '';
        }
      }
      result = { fileType: 'image', fileName: rawFileName, dataUri: rawDataUri, restText: rawRest };
    }
  } else if (content.startsWith('[File: ')) {
    let endBracket: number = content.indexOf(']\n');
    if (endBracket > 0) {
      let rawFileName: string = content.substring(7, endBracket);
      result = { fileType: 'file', fileName: rawFileName, dataUri: '', restText: '' };
    }
  }
  return result;
}

@Reusable
@Component
export struct MessageCard {
  @Prop isUser: boolean = false;
  @Prop msgId: string = '';
  @Prop msgSendStatus: string = '';
  @Prop time: string = '';
  @Prop status: string = '';
  @Prop @Watch('onMsgContentChange') msgContent: string = '';
  @Prop msgType: string = 'text';
  @Prop msgToolName: string = '';
  @Prop msgToolStatus: string = '';
  @Prop msgToolKind: string = '';
  @Prop msgToolContent: string = '';
  @Prop msgToolContentType: string = '';
  @Prop msgToolPath: string = '';
  @Prop msgToolOldText: string = '';
  @Prop msgToolNewText: string = '';
  @Prop msgToolTerminalId: string = '';
  @Prop streaming: boolean = false;
  onRetry?: (id: string, content: string) => void;
  @State parsedFileType: string = '';
  @State parsedFileName: string = '';
  @State parsedDataUri: string = '';
  @State parsedRestText: string = '';


  aboutToAppear(): void {
    this.parseFilePrefixInternal();
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.isUser = Boolean(params['isUser']);
    this.msgId = String(params['msgId'] || '');
    this.msgSendStatus = String(params['msgSendStatus'] || '');
    this.time = String(params['time'] || '');
    this.status = String(params['status'] || '');
    this.msgContent = String(params['msgContent'] || '');
    this.msgType = String(params['msgType'] || 'text');
    this.msgToolName = String(params['msgToolName'] || '');
    this.msgToolStatus = String(params['msgToolStatus'] || '');
    this.msgToolKind = String(params['msgToolKind'] || '');
    this.msgToolContent = String(params['msgToolContent'] || '');
    this.msgToolContentType = String(params['msgToolContentType'] || '');
    this.msgToolPath = String(params['msgToolPath'] || '');
    this.msgToolOldText = String(params['msgToolOldText'] || '');
    this.msgToolNewText = String(params['msgToolNewText'] || '');
    this.msgToolTerminalId = String(params['msgToolTerminalId'] || '');
    this.streaming = Boolean(params['streaming']);
    this.parseFilePrefixInternal();
  }


  // When @Prop values change, re-parse file prefix
  onMsgContentChange(): void {
    this.parseFilePrefixInternal();
  }

  private parseFilePrefixInternal(): void {
    let info: FilePrefixInfo = parseFilePrefix(this.msgContent);
    this.parsedFileType = info.fileType;
    this.parsedFileName = info.fileName;
    this.parsedDataUri = info.dataUri;
    this.parsedRestText = info.restText;
  }

  copyContent() {
    try {
      let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.msgContent);
      let systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData).then(() => {
        (this.getUIContext()).getPromptAction().showToast({ message: getContext(this).resourceManager.getStringSync($r('app.string.chat_copy_confirm').id) });
      })
    } catch (_e) { /* silently handled */ }
  }

  build() {
    Row() {
      if (this.isUser) {
        Blank()
      }

      Column() {
        if (!this.isUser) {
          Column() {
            if (this.msgType === 'thinking') {
              ThinkingSection({ thinking: this.msgContent, isStreaming: this.streaming })
            } else if (this.msgType === 'tool_call') {
              ToolCallCard({ name: this.msgToolName, status: this.msgToolStatus, kind: this.msgToolKind, content: this.msgToolContent,
                contentType: this.msgToolContentType, path: this.msgToolPath, oldText: this.msgToolOldText,
                newText: this.msgToolNewText, terminalId: this.msgToolTerminalId })
            } else {
              if (this.msgContent.length > 0) {
                if (this.streaming) {
                  Text(this.msgContent)
                    .fontSize(FontSize.base)
                    .fontColor(Colors.foreground)
                    .lineHeight(22)
                } else {
                  MarkdownRender({ text: this.msgContent, streaming: false })
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
          .gesture(LongPressGesture().onAction(() => { this.copyContent() }))

        } else {
          // User message bubble
          Column() {
            if (this.parsedFileType === 'image' && this.parsedDataUri.length > 0) {
              Image(this.parsedDataUri)
                .width('100%')
                .aspectRatio(1)
                .objectFit(ImageFit.Contain)
                .borderRadius(Radius.md)
                .margin({ bottom: Spacing.sm })
              Text(this.parsedFileName)
                .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: Spacing.xs })
              if (this.parsedRestText.length > 0) {
                Text(this.parsedRestText)
                  .fontSize(FontSize.base).fontColor(Colors.foreground).lineHeight(22)
              }
            } else if (this.parsedFileType === 'file') {
              Row() {
                SymbolGlyph($r('sys.symbol.paperclip'))
                  .fontSize(16).fontColor([Colors.foregroundMuted])
                  .margin({ right: Spacing.sm })
                Text(this.parsedFileName)
                  .fontSize(FontSize.base).fontColor(Colors.foreground)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: Spacing.xs, bottom: Spacing.xs })
              if (this.parsedRestText.length > 0) {
                Text(this.parsedRestText)
                  .fontSize(FontSize.base).fontColor(Colors.foreground).lineHeight(22)
                  .margin({ top: Spacing.sm })
              }
            } else {
              if (this.msgContent.length > 0) {
                Text(this.msgContent)
                  .fontSize(FontSize.base)
                  .fontColor(Colors.foreground)
                  .lineHeight(22)
              }
            }
          }
          .padding({
            top: Spacing.md,
            bottom: Spacing.md,
            left: Spacing.lg,
            right: Spacing.lg
          })
          .backgroundColor(Colors.surface1)
          .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl, bottomLeft: Radius.xl, bottomRight: Radius.xs })
          .alignItems(HorizontalAlign.Start)
          .gesture(LongPressGesture().onAction(() => { this.copyContent() }))

          if (this.msgSendStatus === 'failed') {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(16)
              .fontColor([Colors.error])
              .margin({ top: Spacing.xs })
              .onClick(() => { if (this.onRetry) this.onRetry(this.msgId, this.msgContent) })
          }
        }
      }
      .layoutWeight(this.isUser ? 0 : 1)
      .constraintSize(this.isUser ? { maxWidth: '85%' } : { maxWidth: '100%' })
    }
    .width('100%')
    .padding({
      left: Spacing.xl,
      right: Spacing.xl,
      top: (this.msgType === 'thinking' || this.msgType === 'tool_call') ? 0 : Spacing.xs,
      bottom: (this.msgType === 'thinking' || this.msgType === 'tool_call') ? 0 : Spacing.xs
    })
    .transition(TransitionEffect.OPACITY)
  }
}
