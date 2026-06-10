import { Colors, FontSize, Spacing, Radius, Shadow, Duration, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { ChatStore, AvailableCommand, ModelItem, ModeItem } from '../../common/model/ChatState';
import { CustomIcon } from '../../common/ui/CustomIcon';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';

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

class ConfigRowParams {
  label: string = '';
  selected: boolean = false;
  onClick?: () => void;
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
  @State showSheet: boolean = false;             // 唯一 bindsheet
  @State sheetView: string = 'summary';          // summary | agents | providers | models | modes
  @State selectedProvider: string = '';          // Model 钻取：选中的 provider
  @State isRefreshing: boolean = false;
  onSend?: (text: string) => void;
  onCancel?: () => void;
  onSelectAgent?: (index: number) => void;
  onSwitchModel?: (index: number) => void;
  onSwitchMode?: (index: number) => void;
  onRefreshAgents?: () => void;
  onRefreshModels?: () => void;

  private textAreaController: TextAreaController = new TextAreaController();

  localize(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

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
    let ctx = (this.getUIContext() as UIContext).getHostContext();
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
        .width(Layout.contentWidth)
        .height(this.getDropdownHeight())
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.lg)
        .border({ width: 1, color: Colors.borderLight })
        .shadow(Shadow.md)
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
            Text(this.pendingFileType === 'image' ? this.localize($r('app.string.chat_file_image_label')) :
              (this.pendingFileType === 'text' ? this.localize($r('app.string.chat_file_text_label')) :
                this.localize($r('app.string.chat_file_binary_label'))))
              .fontSize(10).fontColor(Colors.foregroundLight)
              .width('100%')
            if (this.pendingFileType === 'image' && this.pendingFileBase64.length > 270000) {
              Text($r('app.string.chat_file_large_warning'))
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
        .width(Layout.contentWidth)
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
            .constraintSize({ maxHeight: 150 })
            .layoutWeight(1)
            .backgroundColor('transparent')
            .padding({ left: Spacing.md, right: Spacing.md })
            .fontSize(FontSize.base)
            .enabled(!this.disabled)
            .enterKeyType(EnterKeyType.Send)
            .onChange((val: string) => { this.text = val })
            .onSubmit(() => { this.doSend() })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ top: Spacing.md, bottom: Spacing.xs })

        Row() {
          Row({ space: Spacing.sm }) {
            Button() {
              SymbolGlyph($r('sys.symbol.paperclip'))
                .fontSize(18)
                .fontColor([this.disabled ? Colors.border : Colors.foregroundMuted])
            }
            .width(30)
            .height(30)
            .backgroundColor(Colors.transparent)
            .enabled(!this.disabled)
            .stateStyles({
              pressed: { .scale({ x: 0.92, y: 0.92 }) },
              normal: { .scale({ x: 1, y: 1 }) }
            })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
            .onClick(() => { if (!this.disabled) this.pickFile() })

            // Model name chip → opens config bindsheet
            Button() {
              Row() {
                SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                  .fontSize(10)
                  .fontColor([Colors.foregroundMuted])
                  .margin({ right: Spacing.xs })
                Text(this.getModelName().length > 0 ? this.getModelName() : this.localize($r('app.string.config_model')))
                  .fontSize(11)
                  .fontColor(Colors.foreground)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(8)
                  .fontColor([Colors.foregroundMuted])
                  .margin({ left: Spacing.xxs })
              }
            }
            .height(26)
            .padding({ left: Spacing.sm, right: Spacing.sm })
            .backgroundColor(Colors.surface1)
            .borderRadius(Radius.sm)
            .stateStyles({
              pressed: { .backgroundColor(Colors.surface2) },
              normal: { .backgroundColor(Colors.surface1) }
            })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
            .onClick(() => { this.sheetView = 'summary'; this.showSheet = true; })
          }
          .alignItems(VerticalAlign.Center)

          Blank()

          if (this.showCancel) {
            Button() {
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(28)
                .fontColor([Colors.error])
            }
            .backgroundColor(Colors.transparent)
            .stateStyles({
              pressed: { .scale({ x: 0.92, y: 0.92 }) },
              normal: { .scale({ x: 1, y: 1 }) }
            })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
            .accessibilityText(this.localize($r('app.string.chat_cancel_button')))
            .onClick(() => { if (this.onCancel) this.onCancel() })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.5, y: 0.5 })))
          } else if (this.text.length > 0 || this.pendingFileName.length > 0) {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_up_circle_fill'))
                .fontColor([Colors.foreground])
                .fontSize(28)
            }
            .backgroundColor(Colors.transparent)
            .stateStyles({
              pressed: { .scale({ x: 0.92, y: 0.92 }) },
              normal: { .scale({ x: 1, y: 1 }) }
            })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
            .accessibilityText(this.localize($r('app.string.chat_send_button')))
            .onClick(() => { this.doSend() })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.5, y: 0.5 })))
          } else {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_up_circle_fill'))
                .fontColor([Colors.borderLight])
                .fontSize(28)
            }
            .backgroundColor(Colors.transparent)
            .enabled(false)
            .accessibilityText(this.localize($r('app.string.chat_send_button')))
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.5, y: 0.5 })))
          }
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.md })
        .alignItems(VerticalAlign.Center)
      }
      .backgroundColor(Colors.surfaceElevated)
      .borderRadius(Radius.xxl)
      .border({ width: 0 })
      .shadow(Shadow.md)
      .width(Layout.contentWidth)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: Spacing.md, bottom: Spacing.lg })
    .backgroundColor(Colors.surface0)
    .accessibilityGroup(true)
    .bindSheet($$this.showSheet, this.ConfigPanel(), {
      detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
      dragBar: true,
      backgroundColor: Colors.surface0,
      showClose: false,
      preferType: SheetType.BOTTOM
    })
  }

  getPlaceholder(): string {
    if (ChatStore.reconnectPhase.length > 0) {
      if (ChatStore.reconnectPhase === 'disconnected') {
        return getContext(this).resourceManager.getStringSync($r('app.string.chat_input_disconnected_placeholder').id);
      } else if (ChatStore.reconnectPhase === 'reconnecting') {
        return getContext(this).resourceManager.getStringSync($r('app.string.chat_input_reconnecting_placeholder').id);
      } else if (ChatStore.reconnectPhase === 'syncing') {
        return getContext(this).resourceManager.getStringSync($r('app.string.chat_input_syncing_placeholder').id);
      }
    }
    if (this.pendingFileName.length > 0) {
      return getContext(this).resourceManager.getStringSync($r('app.string.chat_input_file_placeholder').id);
    }
    if ((ChatStore.selectedAgentName || ChatStore.agentType).length === 0) {
      return getContext(this).resourceManager.getStringSync($r('app.string.chat_input_agent_required_placeholder').id);
    }
    return getContext(this).resourceManager.getStringSync($r('app.string.chat_input_placeholder').id);
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

  // ──────────────────────────────────────────────
  // 唯一 bindSheet：根据 sheetView 切换内容
  // ──────────────────────────────────────────────
  @Builder
  PanelHeader(title: string, showBack: boolean = false, showRefresh: boolean = false) {
    Row() {
      if (showBack) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Colors.foreground])
        }
        .width(36).height(36)
        .backgroundColor(Colors.transparent)
        .borderRadius(Radius.full)
        .margin({ right: Spacing.xs })
        .onClick(() => {
          if (this.sheetView === 'models') {
            this.switchView('providers');
          }
        })
      }

      Text(title)
        .fontSize(FontSize.xl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .layoutWeight(1)

      if (showRefresh) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(18)
            .fontColor([Colors.foregroundMuted])
        }
        .width(36).height(36)
        .backgroundColor(Colors.transparent)
        .borderRadius(Radius.full)
        .onClick(() => { this.doRefresh() })
      }

      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([Colors.foregroundMuted])
      }
      .width(36).height(36)
      .backgroundColor(Colors.transparent)
      .borderRadius(Radius.full)
      .onClick(() => { this.showSheet = false })
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
  }

  @Builder
  ConfigPanel() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.sheetView === 'summary') {
          // ── 摘要视图 ──
          this.PanelHeader(this.localize($r('app.string.config_panel_title')))

          Scroll() {
            Column() {
              Column() {
                this.SummaryRow(this.localize($r('app.string.config_agent')),
                  this.getAgentDisplayName(),
                  () => { this.switchView('agents') })

                Divider().height(0.5).color(Colors.borderLight).margin({ left: Spacing.lg, right: Spacing.lg })

                this.SummaryRow(this.localize($r('app.string.config_model')),
                  this.getModelName().length > 0 ? this.getModelName() : this.localize($r('app.string.common_not_selected')),
                  () => { this.switchView('providers') })

                Divider().height(0.5).color(Colors.borderLight).margin({ left: Spacing.lg, right: Spacing.lg })

                this.SummaryRow(this.localize($r('app.string.config_mode')),
                  this.getModeName().length > 0 ? this.getModeName() : this.localize($r('app.string.common_not_selected')),
                  () => { this.switchView('modes') })
              }
              .backgroundColor(Colors.surface1)
              .borderRadius(Radius.lg)
              .margin({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.lg })
              .clip(true)
            }
            .width('100%')
          }
          .width('100%')
        } else {
          // ── 选择列表 ──
          this.PanelHeader(this.getPanelTitle(), this.sheetView === 'models', true)

          Scroll() {
            Column() {
              if (this.sheetView === 'agents') {
                if (this.getAgentNames().length === 0) {
                  this.EmptyRow(this.localize($r('app.string.config_no_agent_refresh')))
                } else {
                  ForEach(this.getAgentNames(), (name: string, idx: number) => {
                    this.SelectableRow({
                      label: name,
                      selected: idx === this.getCurrentAgentIndex(),
                      onClick: () => {
                        this.showSheet = false;
                        if (this.onSelectAgent) this.onSelectAgent(idx + 1);
                      }
                    })
                  }, (name: string) => name)
                }
              } else if (this.sheetView === 'providers') {
                if (ChatStore.loadingModels) {
                  this.LoadingRow()
                } else if (ChatStore.models.length === 0) {
                  this.EmptyRow(this.localize($r('app.string.config_no_model_refresh')))
                } else if (this.getProviders().length <= 1) {
                  ForEach(ChatStore.models, (model: ModelItem, idx: number) => {
                    this.SelectableRow({
                      label: model.name,
                      selected: idx === ChatStore.modelIndex,
                      onClick: () => {
                        this.showSheet = false;
                        if (this.onSwitchModel) this.onSwitchModel(idx + 1);
                      }
                    })
                  }, (model: ModelItem) => model.modelId)
                } else {
                  ForEach(this.getProviders(), (provider: string) => {
                    this.ProviderRow(provider)
                  }, (provider: string) => provider)
                }
              } else if (this.sheetView === 'models') {
                if (this.selectedProvider.length > 0 && ChatStore.loadingModels) {
                  this.LoadingRow()
                } else if (this.selectedProvider.length > 0) {
                  if (this.getModelsForProvider(this.selectedProvider).length === 0) {
                    this.EmptyRow(this.localize($r('app.string.config_no_model')))
                  } else {
                    ForEach(this.getModelsForProvider(this.selectedProvider), (model: ModelItem) => {
                      this.SelectableRow({
                        label: this.stripProvider(model.name || model.modelId),
                        selected: model.modelId === ChatStore.models[ChatStore.modelIndex]?.modelId,
                        onClick: () => {
                          this.showSheet = false;
                          for (let i: number = 0; i < ChatStore.models.length; i++) {
                            if (ChatStore.models[i].modelId === model.modelId) {
                              if (this.onSwitchModel) this.onSwitchModel(i + 1);
                              break;
                            }
                          }
                        }
                      })
                    }, (model: ModelItem) => model.modelId)
                  }
                }
              } else if (this.sheetView === 'modes') {
                if (ChatStore.loadingModels) {
                  this.LoadingRow()
                } else if (ChatStore.modes.length === 0) {
                  this.EmptyRow(this.localize($r('app.string.config_no_mode')))
                } else {
                  ForEach(ChatStore.modes, (mode: ModeItem, idx: number) => {
                    this.SelectableRow({
                      label: mode.name,
                      selected: idx === ChatStore.modeIndex,
                      onClick: () => {
                        this.showSheet = false;
                        if (this.onSwitchMode) this.onSwitchMode(idx + 1);
                      }
                    })
                  }, (mode: ModeItem) => mode.value)
                }
              }

              Column().height(Spacing.xxxl)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: Spacing.lg, right: Spacing.lg })
          }
          .width('100%')
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .backgroundColor(Colors.surface0)
    .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
  }

  getPanelTitle(): string {
    if (this.sheetView === 'agents') return this.localize($r('app.string.config_select_agent'));
    if (this.sheetView === 'providers') return this.localize($r('app.string.config_select_model'));
    if (this.sheetView === 'models') return this.selectedProvider.length > 0 ? this.selectedProvider : this.localize($r('app.string.config_model'));
    if (this.sheetView === 'modes') return this.localize($r('app.string.config_select_mode'));
    return '';
  }

  /** 切换 sheet 内容（关闭后重开以重新渲染） */
  switchView(view: string): void {
    this.showSheet = false;
    this.sheetView = view;
    setTimeout(() => { this.showSheet = true; }, 30);
  }

  doRefresh(): void {
    this.isRefreshing = true;
    if (this.sheetView === 'agents' && this.onRefreshAgents) {
      this.onRefreshAgents();
    } else if ((this.sheetView === 'providers' || this.sheetView === 'models') && this.onRefreshModels) {
      this.onRefreshModels();
    }
    setTimeout(() => { this.isRefreshing = false; }, 1500);
  }

  getAgentDisplayName(): string {
    if (this.getAgentNames().length > 0) {
      let idx: number = this.getCurrentAgentIndex();
      if (idx >= 0) {
        let agents = DeviceAgentStore.getAgents(ChatStore.currentDeviceId);
        if (agents[idx]) return agents[idx].title || agents[idx].name;
      }
    }
    return ChatStore.selectedAgentName || ChatStore.agentType || this.localize($r('app.string.common_not_selected'));
  }

  getAgentNames(): string[] {
    let hostId: string = ChatStore.currentDeviceId;
    if (hostId.length === 0) return [];
    let agents = DeviceAgentStore.getAgents(hostId);
    let result: string[] = [];
    for (let i: number = 0; i < agents.length; i++) {
      result.push(agents[i].title || agents[i].name);
    }
    return result;
  }
  getCurrentAgentIndex(): number {
    let agents = DeviceAgentStore.getAgents(ChatStore.currentDeviceId);
    for (let i: number = 0; i < agents.length; i++) {
      if (agents[i].name === (ChatStore.selectedAgentName || ChatStore.agentType)) return i;
    }
    return -1;
  }

  getModelName(): string {
    if (ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length) {
      return ChatStore.models[ChatStore.modelIndex].name;
    }
    return '';
  }

  getModeName(): string {
    if (ChatStore.modeIndex >= 0 && ChatStore.modeIndex < ChatStore.modes.length) {
      return ChatStore.modes[ChatStore.modeIndex].name;
    }
    return '';
  }

  getProviders(): string[] {
    let result: string[] = [];
    for (let i: number = 0; i < ChatStore.models.length; i++) {
      let provider: string = this.extractProvider(ChatStore.models[i]);
      if (result.indexOf(provider) < 0) result.push(provider);
    }
    return result;
  }

  getModelsForProvider(provider: string): ModelItem[] {
    let result: ModelItem[] = [];
    for (let i: number = 0; i < ChatStore.models.length; i++) {
      if (this.extractProvider(ChatStore.models[i]) === provider) {
        result.push(ChatStore.models[i]);
      }
    }
    return result;
  }

  @Builder
  SummaryRow(label: string, value: string, onClick: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        Column() {
          Text(label)
            .fontSize(11)
            .fontColor(Colors.foregroundMuted)
            .fontWeight(FontWeight.Regular)
            .width('100%')
            .margin({ bottom: 2 })
          Text(value)
            .fontSize(FontSize.md)
            .fontColor(Colors.foreground)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // Minimalist: No chevron
      }
      .width('100%')
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface2) },
      normal: { .backgroundColor(Color.Transparent) }
    })
    .onClick(() => { if (onClick) onClick() })
  }

  @Builder
  ProviderRow(provider: string) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        Column() {
          Text(provider)
            .fontSize(FontSize.base)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
            .width('100%')
          Text(this.localize($r('app.string.config_models_count'), this.getModelsForProvider(provider).length))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Colors.border])
      }
      .width('100%')
      .padding({ left: Spacing.md, right: Spacing.md })
    }
    .width('100%')
    .height(56)
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.md)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Color.Transparent) }
    })
    .onClick(() => {
      this.selectedProvider = provider;
      this.switchView('models');
    })
  }

  /**
   * Check whether models span multiple providers (not all "Default").
   */
  hasMultipleProviders(): boolean {
    let providers: string[] = this.getProviders();
    return providers.length > 1 || (providers.length === 1 && providers[0] !== this.localize($r('app.string.config_default_provider')));
  }

  @Builder
  SectionHeader(label: string) {
    Text(label)
      .fontSize(FontSize.xs)
      .fontWeight(FontWeight.Medium)
      .fontColor(Colors.foregroundMuted)
      .letterSpacing(0.5)
      .width('100%')
      .padding({ bottom: Spacing.sm, top: Spacing.xs })
  }

  @Builder
  EmptyRow(msg: string) {
    Text(msg)
      .fontSize(FontSize.sm)
      .fontColor(Colors.foregroundLight)
      .width('100%')
      .padding({ top: Spacing.xs, bottom: Spacing.sm, left: Spacing.md })
  }

  @Builder
  LoadingRow() {
    Column() {
      LoadingProgress()
        .width(24).height(24)
        .color(Colors.foregroundMuted)
        .margin({ bottom: Spacing.sm })
      Text(this.localize($r('app.string.config_loading_models')))
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundLight)
    }
    .width('100%')
    .padding({ top: Spacing.xl, bottom: Spacing.xl })
  }

  @Builder
  SelectableRow(params: ConfigRowParams) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        Text(params.label)
          .fontSize(FontSize.base)
          .fontWeight(params.selected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(params.selected ? Colors.accent : Colors.foreground)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        if (params.selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Colors.accent])
        }
      }
      .width('100%')
      .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.lg, right: Spacing.lg })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .stateStyles({
      pressed: {
        .backgroundColor(Colors.surface1)
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
    .onClick(() => { if (params.onClick) params.onClick() })
  }

  stripProvider(fullName: string): string {
    let parts: string[] = fullName.split('/');
    return parts[parts.length - 1];
  }

  extractProvider(model: ModelItem): string {
    let id: string = model.modelId || model.name;
    let parts: string[] = id.split('/');
    if (parts.length >= 2) {
      return this.capitalize(parts[0]);
    }
    return this.localize($r('app.string.config_default_provider'));
  }

  capitalize(s: string): string {
    if (s.length === 0) return s;
    let words: string[] = s.split('-');
    let result: string = '';
    for (let i: number = 0; i < words.length; i++) {
      if (words[i].length > 0) {
        if (result.length > 0) result += ' ';
        result += words[i].charAt(0).toUpperCase() + words[i].substring(1);
      }
    }
    return result;
  }
}