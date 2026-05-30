import { Colors, FontSize, Spacing, Radius, Shadow, Duration } from '../../constants/DesignTokens';
import { ChatStore, AvailableCommand } from '../../common/model/ChatState';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatInputBar';

const TEXT_EXTENSIONS: string[] = ['txt', 'md', 'json', 'xml', 'yaml', 'yml', 'csv', 'ts', 'tsx', 'js',
  'ets', 'css', 'html', 'log', 'ini', 'cfg', 'conf', 'env', 'sh', 'bat', 'ps1', 'py', 'java', 'c', 'cpp',
  'h', 'hpp', 'rs', 'go', 'rb', 'php', 'sql', 'gradle', 'toml', 'kt', 'swift'];

const IMAGE_EXTENSIONS: string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];

function getExt(fileName: string): string {
  let parts: string[] = fileName.split('.');
  if (parts.length < 2) return '';
  return parts[parts.length - 1].toLowerCase();
}

function getMimeType(ext: string): string {
  if (ext === 'jpg' || ext === 'jpeg') return 'image/jpeg';
  if (ext === 'png') return 'image/png';
  if (ext === 'gif') return 'image/gif';
  if (ext === 'webp') return 'image/webp';
  if (ext === 'bmp') return 'image/bmp';
  if (ext === 'svg') return 'image/svg+xml';
  if (ext === 'pdf') return 'application/pdf';
  if (ext === 'doc') return 'application/msword';
  if (ext === 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  return 'application/octet-stream';
}

function classifyFile(fileName: string): string {
  let ext: string = getExt(fileName);
  if (IMAGE_EXTENSIONS.indexOf(ext) >= 0) return 'image';
  if (TEXT_EXTENSIONS.indexOf(ext) >= 0) return 'text';
  return 'binary';
}

@Component
export struct ChatInputBar {
  @State text: string = '';
  @Prop disabled: boolean = false;
  @Prop showCancel: boolean = false;
  @State pendingFileName: string = '';
  @State pendingFileContent: string = '';
  @State pendingFileType: string = '';
  @State pendingFileBase64: string = '';
  @State pendingFileMime: string = '';
  onSend?: (text: string) => void;
  onCancel?: () => void;

  private textAreaController: TextAreaController = new TextAreaController();

  clearPendingFile(): void {
    this.pendingFileName = '';
    this.pendingFileContent = '';
    this.pendingFileType = '';
    this.pendingFileBase64 = '';
    this.pendingFileMime = '';
  }

  pickImage(): void {
    try {
      let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      let photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(photoSelectOptions).then((result: photoAccessHelper.PhotoSelectResult) => {
        let uris: string[] = result.photoUris;
        if (uris.length === 0) return;
        this.readBinaryFile(uris[0], 'image');
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, `PhotoViewPicker failed, falling back to document picker: ${err}`);
        this.pickFile();
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `PhotoViewPicker unavailable, falling back to document picker: ${err}`);
      this.pickFile();
    }
  }

  pickFile(): void {
    let ctx = this.getUIContext().getHostContext();
    if (!ctx) return;
    let documentPicker = new picker.DocumentViewPicker(ctx);
    try {
      documentPicker.select().then((uris: string[]) => {
        if (uris.length === 0) return;
        let uri: string = uris[0];
        let fileName: string = decodeURIComponent(uri.split('/').pop() || 'file');
        let category: string = classifyFile(fileName);
        if (category === 'image') {
          this.readBinaryFile(uri, 'image');
        } else if (category === 'text') {
          this.readTextFile(uri, fileName);
        } else {
          this.readBinaryFile(uri, 'binary');
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `DocumentViewPicker cancelled or unavailable: ${err}`);
    }
  }

  readTextFile(uri: string, fileName: string): void {
    try {
      let file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let maxSize: number = 1024 * 100;
      if (stat.size > maxSize) {
        fileIo.closeSync(file);
        return;
      }
      let buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      let decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      let content: string = decoder.decodeToString(new Uint8Array(buf));
      this.pendingFileName = fileName;
      this.pendingFileContent = content;
      this.pendingFileType = 'text';
      this.pendingFileBase64 = '';
      this.pendingFileMime = '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, `readTextFile failed: ${err}`);
    }
  }

  async readBinaryFile(uri: string, category: string): Promise<void> {
    try {
      let file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let maxSize: number = category === 'image' ? 1024 * 1024 : 512 * 1024;
      if (stat.size > maxSize) {
        fileIo.closeSync(file);
        return;
      }
      let buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      let uint8 = new Uint8Array(buf);
      let base64: string = await new util.Base64Helper().encodeToString(uint8);
      let fileName: string = decodeURIComponent(uri.split('/').pop() || 'file');
      let ext: string = getExt(fileName);
      let mime: string = getMimeType(ext);
      this.pendingFileName = fileName;
      this.pendingFileContent = '';
      this.pendingFileType = category;
      this.pendingFileBase64 = base64;
      this.pendingFileMime = mime;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `readBinaryFile failed: ${err}`);
    }
  }

  build() {
    Column() {
      if (this.text.startsWith('/') && !this.disabled && this.hasCommands()) {
        List({ space: 2 }) {
          ForEach(this.getFilteredCommands(), (cmd: AvailableCommand) => {
            ListItem() {
              Row() {
                Column() {
                  Text('/' + cmd.name)
                    .fontSize(FontSize.base)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Colors.foreground)
                    .width('100%')
                  Text(cmd.description)
                    .fontSize(FontSize.sm)
                    .fontColor(Colors.foregroundMuted)
                    .width('100%')
                    .margin({ top: 2 })
                  if (cmd.hint && cmd.hint.length > 0) {
                    Text(cmd.hint)
                      .fontSize(FontSize.xs)
                      .fontColor(Colors.foregroundLight)
                      .width('100%')
                      .margin({ top: 1 })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
              .onClick(() => { this.selectCommand(cmd) })
            }
          }, (cmd: AvailableCommand) => cmd.name)
        }
        .width('100%')
        .height(this.getDropdownHeight())
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.lg)
        .border({ width: 1, color: Colors.borderLight })
        .shadow({ radius: 10, color: '#00000020', offsetY: 6 })
        .margin({ bottom: Spacing.sm })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
        .animation({ duration: 200, curve: Curve.EaseOut })
      }

      if (this.pendingFileName.length > 0) {
        Row() {
          if (this.pendingFileType === 'image' && this.pendingFileBase64.length > 0) {
            Image('data:' + this.pendingFileMime + ';base64,' + this.pendingFileBase64)
              .width(28).height(28).borderRadius(Radius.sm)
              .objectFit(ImageFit.Cover).margin({ right: Spacing.xs })
          } else {
            SymbolGlyph($r('sys.symbol.paperclip'))
              .fontSize(14).fontColor([Colors.accent])
              .margin({ right: Spacing.xs })
          }
          Column() {
            Text(this.pendingFileName)
              .fontSize(FontSize.sm).fontColor(Colors.accent)
              .fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.pendingFileType === 'image' ? 'Image' : (this.pendingFileType === 'text' ? 'Text file' : 'Binary file'))
              .fontSize(10).fontColor(Colors.foregroundLight)
              .width('100%')
            if (this.pendingFileType === 'image' && this.pendingFileBase64.length > 270000) {
              Text('Large image may be slow to send')
                .fontSize(10).fontColor(Colors.error)
                .width('100%')
            }
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          .margin({ left: Spacing.xs, right: Spacing.xs })

          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14).fontColor([Colors.foregroundMuted])
            .onClick(() => { this.clearPendingFile() })
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.xs })
        .backgroundColor(Colors.surface1)
        .borderRadius({ topLeft: Radius.lg, topRight: Radius.lg })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
        .animation({ duration: Duration.fast, curve: Curve.EaseOut })
      }

      Column() {
        Row() {
          TextArea({
            placeholder: this.getPlaceholder(),
            text: this.text,
            controller: this.textAreaController
          })
            .layoutWeight(1)
            .backgroundColor('transparent')
            .padding({ left: Spacing.md, right: Spacing.sm })
            .fontSize(FontSize.base)
            .enabled(!this.disabled)
            .enterKeyType(EnterKeyType.Send)
            .onChange((val: string) => { this.text = val })
            .onSubmit(() => { this.doSend() })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ top: Spacing.sm, bottom: Spacing.xs })

        Row() {
          Row({ space: Spacing.sm }) {
            SymbolGlyph($r('sys.symbol.paperclip'))
              .fontSize(22)
              .fontColor([this.disabled ? Colors.border : Colors.foregroundMuted])
              .enabled(!this.disabled)
              .onClick(() => { if (!this.disabled) this.pickFile() })
              .animation({ duration: Duration.fast, curve: Curve.EaseOut })
          }
          .alignItems(VerticalAlign.Center)

          Blank()

          if (this.showCancel) {
            SymbolGlyph($r('sys.symbol.smallcircle_filled_circle'))
              .fontColor([Colors.error])
              .fontSize(28)
              .accessibilityText('Cancel generation')
              .onClick(() => { if (this.onCancel) this.onCancel() })
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.5, y: 0.5 })))
              .animation({ duration: Duration.fast, curve: Curve.EaseOut })
          } else if (this.text.length > 0 || this.pendingFileName.length > 0) {
            SymbolGlyph($r('sys.symbol.arrow_up_circle_fill'))
              .fontColor([Colors.foreground])
              .fontSize(28)
              .accessibilityText('Send message')
              .onClick(() => { this.doSend() })
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.5, y: 0.5 })))
              .animation({ duration: Duration.fast, curve: Curve.EaseOut })
          } else {
            Text($r('app.string.EntryAbility_label'))
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundLight)
              .accessibilityText('Message input inactive')
              .transition(TransitionEffect.OPACITY)
              .animation({ duration: Duration.fast })
          }
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.sm })
        .alignItems(VerticalAlign.Center)
      }
      .backgroundColor(Colors.surfaceElevated)
      .borderRadius(Radius.xl)
      .border({ width: 1, color: Colors.borderLight })
      .shadow(Shadow.sm)
      .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.xxxl })
    .backgroundColor(Colors.surface0)
    .accessibilityGroup(true)
  }

  getPlaceholder(): string {
    if (ChatStore.reconnectPhase.length > 0) {
      if (ChatStore.reconnectPhase === 'disconnected') {
        return getContext().resourceManager.getStringSync($r('app.string.chat_input_disconnected_placeholder'));
      } else if (ChatStore.reconnectPhase === 'reconnecting') {
        return getContext().resourceManager.getStringSync($r('app.string.chat_input_reconnecting_placeholder'));
      } else if (ChatStore.reconnectPhase === 'syncing') {
        return getContext().resourceManager.getStringSync($r('app.string.chat_input_syncing_placeholder'));
      }
    }
    if (this.pendingFileName.length > 0) {
      return getContext().resourceManager.getStringSync($r('app.string.chat_input_file_placeholder'));
    }
    return getContext().resourceManager.getStringSync($r('app.string.chat_input_placeholder'));
  }

  hasCommands(): boolean {
    return ChatStore.availableCommands.length > 0 && this.getFilteredCommands().length > 0;
  }

  getFilteredCommands(): AvailableCommand[] {
    let query: string = this.text.substring(1).toLowerCase();
    let result: AvailableCommand[] = [];
    for (let i: number = 0; i < ChatStore.availableCommands.length; i++) {
      if (ChatStore.availableCommands[i].name.toLowerCase().includes(query)) {
        result.push(ChatStore.availableCommands[i]);
      }
    }
    return result;
  }

  getDropdownHeight(): number {
    let count: number = this.getFilteredCommands().length;
    let h: number = count * 66;
    if (h > 240) h = 240;
    return h;
  }

  doSend(): void {
    if (this.disabled) return;
    let t: string = this.text.trim();
    let hasFile: boolean = this.pendingFileName.length > 0;

    if (t.length === 0 && !hasFile) return;

    let msg: string = '';
    if (this.pendingFileType === 'image' && this.pendingFileBase64.length > 0) {
      let dataUri: string = 'data:' + this.pendingFileMime + ';base64,' + this.pendingFileBase64;
      msg = '[Image: ' + this.pendingFileName + ']\n' + dataUri;
    } else if (this.pendingFileType === 'text' && this.pendingFileContent.length > 0) {
      msg = '[File: ' + this.pendingFileName + ']\n' + this.pendingFileContent;
    } else if (this.pendingFileType === 'binary' && this.pendingFileBase64.length > 0) {
      let dataUri: string = 'data:' + this.pendingFileMime + ';base64,' + this.pendingFileBase64;
      msg = '[File: ' + this.pendingFileName + ']\n' + dataUri;
    }

    if (t.length > 0) {
      if (msg.length > 0) {
        msg = msg + '\n\n' + t;
      } else {
        msg = t;
      }
    }

    if (this.onSend) this.onSend(msg);
    this.text = '';
    this.clearPendingFile();
  }

  selectCommand(cmd: AvailableCommand): void {
    this.text = '/' + cmd.name + ' ';
    this.textAreaController.caretPosition(this.text.length);
  }
}
