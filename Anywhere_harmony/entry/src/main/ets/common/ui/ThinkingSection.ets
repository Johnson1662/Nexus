import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Prop isStreaming: boolean = false;
  @State expanded: boolean = true;

  aboutToAppear(): void {
    if (!this.isStreaming) {
      this.expanded = false;
    }
  }

  build() {
    Column() {
      // Hidden trigger — references @Prop isStreaming DIRECTLY in template to subscribe.
      // When isStreaming transitions true→false, this Text appears and onAppear fires once,
      // collapsing this section independently.
      if (!this.isStreaming) {
        Text('')
          .visibility(Visibility.None)
          .onAppear(() => {
            if (this.expanded) {
              this.expanded = false;
            }
          })
      }

      // Header
      Row() {
        SymbolGlyph(this.isStreaming ? $r('sys.symbol.lightbulb') : $r('sys.symbol.checkmark'))
          .fontSize(FontSize.md)
          .fontColor([Colors.foregroundMuted])
          .margin({ right: Spacing.sm })

        if (this.isStreaming) {
          Text('Thinking')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .fontWeight(FontWeight.Medium)
        } else {
          Text('Thought process')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .fontWeight(FontWeight.Medium)
        }

        Blank()

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(FontSize.md)
          .fontColor([Colors.foregroundMuted])
          .rotate({ z: 1, angle: this.expanded ? 0 : -90 })
          .animation({ duration: 200, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded && this.thinking.length > 0) {
        Row() {
          Text(this.thinking)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .lineHeight(22)
            .width('100%')
        }
        .width('100%')
        .padding({ left: Spacing.md, top: Spacing.xs, bottom: Spacing.sm })
        .margin({ left: 7 })
        .border({ width: { left: 1 }, color: { left: Colors.border } })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
  }
}
