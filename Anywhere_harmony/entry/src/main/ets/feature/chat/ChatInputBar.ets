import { Colors, FontSize, Spacing, Radius, Shadow } from '../../constants/DesignTokens';
import { ChatStore, AvailableCommand } from '../../common/model/ChatState';

@Component
export struct ChatInputBar {
  @State text: string = '';
  @Prop disabled: boolean = false;
  onSend?: (text: string) => void;
  onCancel?: () => void;

  @State isFocused: boolean = false;
  private textAreaController: TextAreaController = new TextAreaController();

  build() {
    Column() {
      // Slash command dropdown — separate from the input bar
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

      // Input bar
      Column() {
        Row() {
          TextArea({
            placeholder: 'Type a message...',
            text: this.text,
            controller: this.textAreaController
          })
            .layoutWeight(1)
            .backgroundColor('transparent')
            .padding({ left: Spacing.md, right: Spacing.sm })
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
        .padding({ top: Spacing.sm, bottom: Spacing.xs })

        Row() {
          Blank()

          if (this.disabled) {
            SymbolGlyph($r('sys.symbol.smallcircle_filled_circle'))
              .fontColor([Colors.error])
              .fontSize(28)
              .onClick(() => { if (this.onCancel) this.onCancel() })
          } else if (this.text.length > 0) {
            SymbolGlyph($r('sys.symbol.arrow_up_circle_fill'))
              .fontColor([Colors.foreground])
              .fontSize(28)
              .onClick(() => { this.doSend() })
          } else {
            Text('agent')
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundLight)
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
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.xl })
    .backgroundColor(Colors.surface0)
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
    if (t.length === 0) return;
    if (this.onSend) this.onSend(t);
    this.text = '';
  }

  selectCommand(cmd: AvailableCommand): void {
    this.text = '/' + cmd.name + ' ';
    this.textAreaController.caretPosition(this.text.length);
  }
}
