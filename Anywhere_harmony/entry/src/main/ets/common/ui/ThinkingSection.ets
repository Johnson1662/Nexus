import { Colors, FontSize, Spacing, Duration } from '../../constants/DesignTokens';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Prop isStreaming: boolean = false;
  @State expanded: boolean = true;
  @State breathFlag: boolean = false;

  aboutToAppear(): void {
    if (this.isStreaming) {
      // 触发布局后改变状态以启动动画
      setTimeout(() => {
        this.breathFlag = true;
      }, 50);
    }
  }

  build() {
    Column() {
      Row() {
        Text('Thinking...')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontStyle(FontStyle.Italic)
          .fontWeight(FontWeight.Medium)
          .opacity(this.isStreaming ? (this.breathFlag ? 0.4 : 1.0) : 1.0)
          .animation(this.isStreaming ? {
            duration: 1000,
            curve: Curve.EaseInOut,
            playMode: PlayMode.Alternate,
            iterations: -1
          } : { duration: 0 })
      }
      .width('100%')
      .padding({ top: Spacing.xs, bottom: Spacing.xs })
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: Duration.fast, curve: Curve.EaseInOut }, () => {
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
            .padding({ bottom: Spacing.xs })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 })))
        .animation({ duration: Duration.fast, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
  }
}
