import { Colors, FontSize, Spacing, Duration } from '../constants/DesignTokens';

@Component
export struct ToolCallCard {
  @Prop name: string = 'Tool';
  @Prop status: string = 'pending';
  @Prop kind: string = '';

  @State breathFlag: boolean = false;
  @State shimmerOffset: number = -120;

  aboutToAppear(): void {
    if (this.status === 'in_progress') {
      setTimeout(() => {
        this.breathFlag = true;
        this.shimmerOffset = 600;
      }, 50);
    }
  }

  getDisplayText(): string {
    let k: string = this.kind.toLowerCase();
    if (k === 'skill') return 'Skill: ' + this.name;
    return this.name;
  }

  build() {
    Stack() {
      // Base text
      Text(this.getDisplayText())
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .fontFamily('monospace')
        .fontStyle(FontStyle.Italic)
        .fontWeight(FontWeight.Medium)
        .opacity(this.status === 'in_progress' ? (this.breathFlag ? 0.35 : 0.85) : 0.65)
        .animation(this.status === 'in_progress' ? {
          duration: 1200,
          curve: Curve.EaseInOut,
          playMode: PlayMode.Alternate,
          iterations: -1
        } : { duration: 0 })

      // Shimmer sweep (only during active)
      if (this.status === 'in_progress') {
        Row()
          .width(80)
          .height(18)
          .borderRadius(9)
          .linearGradient({
            direction: GradientDirection.Right,
            colors: [["#00FFFFFF", 0], ["#35FFFFFF", 0.5], ["#00FFFFFF", 1]]
          })
          .position({ x: this.shimmerOffset, y: 2 })
          .animation({
            duration: 1500,
            curve: Curve.Linear,
            playMode: PlayMode.Alternate,
            iterations: -1
          })
      }
    }
    .width('100%')
    .height(24)
    .clip(true)
    .padding({ top: Spacing.xs, bottom: Spacing.xs })
    .alignContent(Alignment.Start)
  }
}
