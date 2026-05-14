import { Colors } from '../constants/Colors';
import { FontSize, Spacing, Radius } from '../constants/DesignTokens';

@Component
export struct ConnectingView {
  @Prop hostUrl: string = '';

  build() {
    Column() {
      Column() {
        Row() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(Colors.accent)
        }
        .width(48)
        .height(48)
        .backgroundColor(Colors.accentLight)
        .borderRadius(Radius.full)
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: Spacing.lg })

        Text('连接成功')
          .fontSize(FontSize.xl)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .margin({ bottom: Spacing.xs })

        Text(this.hostUrl)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: Spacing.lg, right: Spacing.lg })
      }
      .padding(32)
      .backgroundColor(Colors.surfaceElevated)
      .borderRadius(Radius.xxl)
      .width('70%')
      .alignItems(HorizontalAlign.Center)
      .shadow({ radius: 16, color: Colors.shadowColor, offsetY: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
