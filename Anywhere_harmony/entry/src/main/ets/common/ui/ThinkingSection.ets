import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @State expanded: boolean = true;

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.ellipsis_message_1'))
          .fontSize(FontSize.sm)
          .fontColor([Colors.warning])
          .margin({ right: Spacing.sm })

        Text('Thinking')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(32)
      .padding({ left: Spacing.md, right: Spacing.md })
      .backgroundColor(Colors.surface0)
      .borderRadius(Radius.md)
      .border({ width: 1, color: Colors.borderLight })
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: Duration.fast, curve: Curve.EaseInOut }, () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded) {
        Row() {
          Text(this.thinking)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .lineHeight(22)
            .width('100%')
            .padding({ bottom: Spacing.sm, top: Spacing.xs })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 })))
        .animation({ duration: Duration.fast, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Spacing.xs, bottom: Spacing.xs })
  }
}
