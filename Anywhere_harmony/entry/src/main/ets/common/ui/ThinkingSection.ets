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
          if (this.isStreaming) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(FontSize.md)
              .fontColor([Colors.foregroundMuted])
              .margin({ right: Spacing.sm })
              .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
          } else {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(FontSize.md)
              .fontColor([Colors.foregroundMuted])
              .margin({ right: Spacing.sm })
              .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
          }

          if (this.isStreaming) {
            Text($r('app.string.thinking_label'))
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
              .fontWeight(FontWeight.Medium)
          } else {
            Text($r('app.string.thinking_done_label'))
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
              .fontWeight(FontWeight.Medium)
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
        .padding({ left: Spacing.sm })
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
          Text(this.thinking)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .lineHeight(22)
            .width('100%')
        }
        .width('100%')
        .padding({ left: Spacing.xxl, top: Spacing.sm, bottom: Spacing.sm })
        .margin({ left: Spacing.sm })
        .border({ width: { left: 1 }, color: { left: Colors.border } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
    .transition(TransitionEffect.OPACITY)
  }
}
