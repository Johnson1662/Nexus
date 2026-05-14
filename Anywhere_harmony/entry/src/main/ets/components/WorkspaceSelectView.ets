import { Colors } from '../constants/Colors';
import { FontSize, Spacing, Radius } from '../constants/DesignTokens';

@Component
export struct WorkspaceSelectView {
  onOpenDrawer?: () => void;

  build() {
    Column() {
      Row() {
        Row() {
          Text('☰')
            .fontSize(20)
            .fontColor(Colors.foreground)
        }
        .width(40)
        .height(40)
        .borderRadius(Radius.md)
        .backgroundColor(Colors.surface1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onOpenDrawer) {
            this.onOpenDrawer();
          }
        })

        Text('选择工作区')
          .fontSize(FontSize.xl)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .layoutWeight(1)
          .margin({ left: Spacing.md })
      }
      .width('100%')
      .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
      .backgroundColor(Colors.surfaceElevated)

      Column() {
        Text('📂')
          .fontSize(64)
          .margin({ bottom: Spacing.lg })

        Text('请选择工作区')
          .fontSize(FontSize.xxl)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .margin({ bottom: Spacing.xs })

        Text('点击左上角菜单选择或添加工作区')
          .fontSize(FontSize.base)
          .fontColor(Colors.foregroundMuted)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }
}
