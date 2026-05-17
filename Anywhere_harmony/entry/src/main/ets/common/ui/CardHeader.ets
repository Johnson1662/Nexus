import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';

@Component
export struct CardHeader {
  @Prop role: string = '';
  @Prop name: string = '';
  @Prop time: string = '';
  @Prop status: string = '';

  build() {
    Row() {
      // 在气泡设计下，我们可以更精简头部，甚至不要名字。这里保留一个小小的标识
      Text(this.role === 'user' ? '' : 'Assistant')
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
        .fontWeight(FontWeight.Medium)

      Blank()

      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(FontSize.xxs)
          .fontColor(Colors.warning)
          .margin({ right: Spacing.sm })
      }
    }
    .width('100%')
    .padding({ bottom: Spacing.xxs })
    .alignItems(VerticalAlign.Center)
    .visibility(this.role === 'user' ? Visibility.None : Visibility.Visible) // 用户消息不显示头部
  }
}
