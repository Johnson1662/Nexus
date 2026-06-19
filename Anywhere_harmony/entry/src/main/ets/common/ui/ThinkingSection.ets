import { Colors, FontSize, Spacing, Radius, Duration, getLocalizedString } from '../../constants/DesignTokens';
@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Prop @Watch('onStreamingChange') isStreaming: boolean = false;
  @StorageLink('pref_thinking_expanded') prefThinkingExpanded: boolean = true;
  @State expanded: boolean = true;

  text(res: Resource): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res);
  }

  aboutToAppear(): void {
    if (this.isStreaming) {
      this.expanded = true;
    } else {
      this.expanded = this.prefThinkingExpanded;
    }
  }

  onStreamingChange(): void {
    if (!this.isStreaming && this.expanded) {
      this.expanded = this.prefThinkingExpanded;
    }
  }

  build() {
    Column() {
      Button() {
        Row() {
          // Icon in fixed-width column — border line uses same width for perfect alignment
          Column() {
            if (this.isStreaming) {
              SymbolGlyph($r('sys.symbol.lightbulb'))
                .fontSize(FontSize.md)
                .fontColor([Colors.foregroundMuted])
                .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
            } else {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(FontSize.md)
                .fontColor([Colors.foregroundMuted])
                .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
            }
          }
          .width(28)
          .height(20)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          if (this.isStreaming) {
            Text($r('app.string.thinking_label'))
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
              .fontWeight(FontWeight.Medium)
              .margin({ left: Spacing.xs })
          } else {
            Text($r('app.string.thinking_done_label'))
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
              .fontWeight(FontWeight.Medium)
              .margin({ left: Spacing.xs })
          }

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(FontSize.md)
            .fontColor([Colors.foregroundMuted])
            .accessibilityText(this.expanded ? this.text($r('app.string.thinking_collapse')) : this.text($r('app.string.thinking_expand')))
            .rotate({ z: 1, angle: this.expanded ? 0 : -90 })
            .animation({ duration: Duration.normal, curve: Curve.EaseInOut })
        }
        .width('100%')
        .height(36)
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .padding(0)
      .borderRadius(Radius.md)
      .stateStyles({
        pressed: { .backgroundColor(Colors.surface1) },
        normal: { .backgroundColor(Colors.transparent) }
      })
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: Duration.normal, curve: Curve.EaseInOut }, () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded && this.thinking.length > 0) {
        Row() {
          // Border line in same-width column, centered — matches icon column above
          Column() {
            Column()
              .width(1)
              .height('100%')
              .backgroundColor(Colors.border)
          }
          .width(28)
          .alignItems(HorizontalAlign.Center)

          Text(this.thinking)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .lineHeight(22)
            .layoutWeight(1)
            .margin({ left: Spacing.xs })
        }
        .width('100%')
        .padding({ top: Spacing.sm, bottom: Spacing.sm })
        .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
    .transition(TransitionEffect.OPACITY)
  }
}
