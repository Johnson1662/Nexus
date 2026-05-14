import { Colors } from '../constants/Colors';
import { FontSize, Spacing, Duration, Radius } from '../constants/DesignTokens';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @State expanded: boolean = true;
  @State isHovering: boolean = false;

  build() {
    Column() {
      Row() {
        Row() {
          Text('⚡')
            .fontSize(FontSize.xs)
            .fontColor(Colors.warning)
        }
        .width(20)
        .height(20)
        .backgroundColor(Colors.warningLight)
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ right: Spacing.sm })

        Text('推理过程')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)

        Text('▾')
          .fontSize(FontSize.xxs)
          .fontColor(Colors.foregroundLight)
          .rotate({ angle: this.expanded ? 180 : 0 })
          .animation({
            duration: Duration.fast,
            curve: Curve.EaseInOut
          })
      }
      .width('100%')
      .height(36)
      .padding({ left: Spacing.md, right: Spacing.md })
      .backgroundColor(Colors.surface0)
      .borderRadius(Radius.md)
      .border({ width: 1, color: Colors.borderLight })
      .onClick(() => {
        animateTo({ duration: Duration.fast, curve: Curve.EaseInOut }, () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded) {
        Column() {
          Text(this.thinking)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .textAlign(TextAlign.Start)
            .width('100%')
            .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.md })
            .lineHeight(22)
        }
        .width('100%')
        .backgroundColor(Colors.surface0)
        .borderRadius(Radius.md)
        .margin({ top: Spacing.xs })
        .border({ width: 1, color: Colors.borderLight })
      }
    }
    .width('100%')
  }
}
