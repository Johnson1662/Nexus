import { Colors, FontSize, Spacing, Duration } from '../../constants/DesignTokens';

@Component
export struct ToolCallCard {
  @Prop name: string = '';
  @Prop status: string = 'pending';
  @Prop kind: string = '';
  @Prop content: string = '';
  @State breathFlag: boolean = false;

  aboutToAppear(): void {
    if (this.status === 'in_progress') {
      setTimeout(() => {
        this.breathFlag = true;
      }, 50);
    }
  }

  build() {
    Column() {
      Row() {
        Text(this.name)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontFamily('monospace')
          .fontStyle(FontStyle.Italic)
          .fontWeight(FontWeight.Medium)
          .opacity(this.status === 'in_progress' ? (this.breathFlag ? 0.4 : 1.0) : 1.0)
          .animation(this.status === 'in_progress' ? {
            duration: 1000,
            curve: Curve.EaseInOut,
            playMode: PlayMode.Alternate,
            iterations: -1
          } : { duration: 0 })
      }
      .width('100%')
      .padding({ top: Spacing.xs, bottom: Spacing.xs })
      .alignItems(VerticalAlign.Center)

      if (this.content.length > 0) {
        Text(this.content)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundLight)
          .fontFamily('monospace')
          .padding({ top: Spacing.xs, bottom: Spacing.sm })
          .width('100%')
      }
    }
    .width('100%')
  }
}
