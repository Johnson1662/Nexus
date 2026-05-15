import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';

interface SelectOption {
  value: string;
}

@Component
export struct ChatInputBar {
  @State text: string = '';
  @State selectedModel: number = 0;
  @State selectedMode: number = 0;
  @Prop models: string[] = [];
  @Prop modes: string[] = [];
  @Prop disabled: boolean = false;
  onSend?: (text: string) => void;
  onModelChange?: (index: number) => void;
  onModeChange?: (index: number) => void;

  @State isFocused: boolean = false;
  private textAreaController: TextAreaController = new TextAreaController();

  build() {
    Column() {
      Column() {
        Row() {
          Text('>')
            .fontFamily('monospace')
            .fontSize(FontSize.md)
            .fontColor(Colors.accent)
            .fontWeight(FontWeight.Bold)
            .margin({ left: Spacing.md, top: Spacing.sm })

          TextArea({
            placeholder: 'Enter command or message...',
            text: this.text,
            controller: this.textAreaController
          })
            .layoutWeight(1)
            .backgroundColor('transparent')
            .padding({ left: Spacing.sm, right: Spacing.md })
            .fontSize(FontSize.base)
            .enabled(!this.disabled)
            .maxLines(6)
            .minLines(1)
            .enterKeyType(EnterKeyType.Send)
            .onChange((val: string) => { this.text = val })
            .onSubmit(() => { this.doSend() })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row() {
          if (this.models.length > 0) {
            Select(this.buildOpts(this.models))
              .value('Model')
              .font({ size: FontSize.xs }).fontColor(Colors.foregroundMuted)
              .selectedOptionFont({ size: FontSize.xs }).selectedOptionFontColor(Colors.accent)
              .selectedOptionBgColor(Colors.accentLight)
              .backgroundColor('transparent')
              .onSelect((i) => { this.selectedModel = i; if (this.onModelChange) this.onModelChange(i) })
          }

          Blank()

          if (this.text.length > 0 && !this.disabled) {
            SymbolGlyph($r('sys.symbol.arrow_up_circle_fill'))
              .fontColor([Colors.accent])
              .fontSize(FontSize.xxxl)
              .onClick(() => { this.doSend() })
          } else {
            Text('agent')
              .fontFamily('monospace')
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundLight)
          }
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.lg, top: Spacing.sm })
        .alignItems(VerticalAlign.Center)
      }
      .backgroundColor(Colors.surface1)
      .borderRadius(Radius.lg)
      .border({ width: 1, color: Colors.borderLight })
      .width('100%')
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: 10 })
    .backgroundColor(Colors.surface0)
  }

  doSend(): void {
    if (this.disabled) return;
    let t: string = this.text.trim();
    if (t.length === 0) return;
    if (this.onSend) this.onSend(t);
    this.text = '';
  }

  buildOpts(items: string[]): SelectOption[] {
    let o: SelectOption[] = [{ value: '—' }];
    for (let i = 0; i < items.length; i++) o.push({ value: items[i] });
    return o;
  }
}
