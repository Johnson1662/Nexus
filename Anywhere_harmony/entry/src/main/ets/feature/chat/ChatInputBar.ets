import { Colors, FontSize, Spacing, Radius } from '../../constants/Colors';

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

          TextInput({ placeholder: 'Enter command or message...', text: this.text })
            .layoutWeight(1)
            .height(48)
            .backgroundColor('transparent')
            .padding({ left: Spacing.sm, right: Spacing.md, top: Spacing.sm })
            .fontSize(FontSize.base)
            .enabled(!this.disabled)
            .onChange((val: string) => { this.text = val })
            .onSubmit(() => { this.doSend() })
        }
        .width('100%')

        Row() {
          Image($r('app.media.ic_attachment'))
            .fillColor(Colors.foreground)
            .width(24).height(24)
            .onClick(() => { this.getUIContext().getPromptAction().openToast({ message: 'File picker (Coming soon)' }) })

          Row() {
            Image($r('app.media.ic_model'))
              .fillColor(Colors.foregroundMuted).width(18).height(18).margin({ right: Spacing.xs })
            if (this.models.length > 0) {
              Select(this.buildOpts(this.models))
                .value('Select model')
                .font({ size: FontSize.sm })
                .fontColor(Colors.foregroundMuted)
                .backgroundColor('transparent')
                .onSelect((i) => { this.selectedModel = i; if (this.onModelChange) this.onModelChange(i) })
            } else {
              Text('Select model').fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            }
          }.margin({ left: Spacing.md })

          Blank()

          if (this.text.length > 0 && !this.disabled) {
            Image($r('app.media.ic_send_active'))
              .fillColor(Colors.foreground).width(28).height(28).onClick(() => { this.doSend() })
          } else {
            Image($r('app.media.ic_mic'))
              .fillColor(Colors.foreground).width(24).height(24).margin({ right: Spacing.md })
              .onClick(() => { this.getUIContext().getPromptAction().openToast({ message: 'Voice input (Coming soon)' }) })
            Image($r('app.media.ic_waveform'))
              .fillColor(Colors.foreground).width(24).height(24)
              .onClick(() => { this.getUIContext().getPromptAction().openToast({ message: 'Voice input (Coming soon)' }) })
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
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: 100 })
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
