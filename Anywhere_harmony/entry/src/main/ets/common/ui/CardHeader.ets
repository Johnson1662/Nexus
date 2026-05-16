import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';

@Component
export struct CardHeader {
  @Prop role: string = '';
  @Prop name: string = '';
  @Prop time: string = '';
  @Prop status: string = '';

  build() {
    Row() {
      Circle()
        .width(8).height(8)
        .fill(this.role === 'user' ? Colors.accent : Colors.foregroundMuted)
        .margin({ right: Spacing.sm })

      Text(this.role === 'user' ? 'You' : 'Assistant')
        .fontSize(FontSize.sm)
        .fontColor(this.role === 'user' ? Colors.accent : Colors.foregroundMuted)
        .fontWeight(FontWeight.Medium)

      Blank()

      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(FontSize.xs)
          .fontColor(Colors.warning)
          .margin({ right: Spacing.sm })
      }

      Text(this.time)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundLight)
    }
    .width('100%')
    .padding({ bottom: Spacing.xs, top: Spacing.md })
    .alignItems(VerticalAlign.Center)
  }
}
