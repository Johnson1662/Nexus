import { Colors, FontSize, Spacing, Radius } from '../../constants/Colors';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @State expanded: boolean = true;

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_thinking')).fillColor(Colors.foregroundMuted).width(20).height(20).margin({ right: Spacing.sm })

        Text('Thinking')
          .fontSize(FontSize.base)
          .fontColor(Colors.foregroundMuted)
      }
      .padding({ top: Spacing.sm, bottom: Spacing.sm })
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: 150, curve: Curve.EaseInOut }, () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded) {
        Row() {
          Text(this.thinking)
            .fontSize(FontSize.base)
            .fontColor(Colors.foreground)
            .lineHeight(24)
            .width('100%')
            .padding({ bottom: Spacing.sm, top: Spacing.xs })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Spacing.xs, bottom: Spacing.xs })
  }
}
