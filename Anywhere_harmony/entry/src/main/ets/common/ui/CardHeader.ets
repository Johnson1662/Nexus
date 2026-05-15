import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';

@Component
export struct CardHeader {
  @Prop role: string = '';
  @Prop name: string = '';
  @Prop time: string = '';
  @Prop status: string = '';

  build() {
    Row() {
      if (this.role === 'user') {
        Text('user@local ~$')
          .fontFamily('monospace')
          .fontSize(FontSize.xs)
          .fontColor(Colors.accent)
          .fontWeight(FontWeight.Bold)
      } else {
        Text('agent@remote ~$')
          .fontFamily('monospace')
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .fontWeight(FontWeight.Bold)
      }

      Blank()

      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(FontSize.xs)
          .fontFamily('monospace')
          .fontColor(Colors.warning)
          .margin({ right: Spacing.sm })
      }

      Text(this.time)
        .fontSize(FontSize.xs)
        .fontFamily('monospace')
        .fontColor(Colors.foregroundLight)
    }
    .width('100%')
    .padding({ bottom: Spacing.xs, top: Spacing.md })
    .alignItems(VerticalAlign.Center)
  }
}
