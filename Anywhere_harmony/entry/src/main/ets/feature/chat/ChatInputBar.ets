import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';

@Component
export struct ChatInputBar {
  @State text: string = '';
  @Prop disabled: boolean = false;
  onSend?: (text: string) => void;

  @State isFocused: boolean = false;
  private textAreaController: TextAreaController = new TextAreaController();

  build() {
    Column() {
      Column() {
        Row() {
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
}
