import { Colors, FontSize, Spacing, Duration } from '../../constants/DesignTokens';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Watch('onStreamingChange') @Prop isStreaming: boolean = false;
  @State expanded: boolean = true;
  @State breathFlag: boolean = false;
  @State elapsedSeconds: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    if (this.isStreaming) {
      this.startTimer();
    }
    setTimeout(() => {
      this.breathFlag = this.isStreaming;
      if (!this.isStreaming) {
        this.getUIContext()?.animateTo({ duration: 0 }, () => {
          this.expanded = false;
        });
      }
    }, 50);
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  onStreamingChange() {
    if (this.isStreaming) {
      this.expanded = true;
      this.startTimer();
      this.breathFlag = true;
    } else {
      this.stopTimer();
      this.breathFlag = false;
      this.getUIContext()?.animateTo({ duration: Duration.normal, curve: Curve.EaseInOut }, () => {
        this.expanded = false;
      });
    }
  }

  startTimer() {
    if (this.timerId === -1) {
      this.timerId = setInterval(() => {
        this.elapsedSeconds += 1;
      }, 1000);
    }
  }

  stopTimer() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        SymbolGlyph(this.isStreaming ? $r('sys.symbol.ellipsis_message_1') : $r('sys.symbol.checkmark'))
          .fontSize(FontSize.md)
          .fontColor([Colors.foregroundMuted])
          .margin({ right: Spacing.sm })
          .opacity(this.isStreaming ? (this.breathFlag ? 0.4 : 1.0) : 1.0)
          .animation(this.isStreaming ? {
            duration: 1200,
            curve: Curve.EaseInOut,
            playMode: PlayMode.Alternate,
            iterations: -1
          } : { duration: 0 })

        Text(this.isStreaming ? `Thinking about your request · ${this.elapsedSeconds}s` : (this.elapsedSeconds > 0 ? `Thought for ${this.elapsedSeconds}s` : `Thought process`))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontWeight(FontWeight.Medium)

        Blank()

        // Collapse Toggle
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(FontSize.md)
          .fontColor([Colors.foregroundMuted])
          .rotate({ z: 1, angle: this.expanded ? 0 : -90 })
          .animation({ duration: Duration.fast, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)
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
        }
        .width('100%')
        .padding({ left: Spacing.md, top: Spacing.xs, bottom: Spacing.sm })
        .margin({ left: 7 }) // shift slightly right to align visual center of ellipsis
        .border({ width: { left: 1 }, color: { left: Colors.border } })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
  }
}
