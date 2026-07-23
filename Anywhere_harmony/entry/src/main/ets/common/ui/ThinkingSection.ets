import { Colors, FontSize, Spacing, Radius, Duration, getLocalizedString, AnimationPresets } from '../../constants/DesignTokens';

@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Prop @Watch('onStreamingChange') isStreaming: boolean = false;
  @StorageLink('pref_thinking_expanded') prefThinkingExpanded: boolean = true;
  @State expanded: boolean = true;
  @State userToggled: boolean = false;
  collapseTimer: number = -1;

  text(res: Resource): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res);
  }

  aboutToAppear(): void {
    if (this.isStreaming) {
      this.expanded = true;
    } else {
      this.expanded = this.prefThinkingExpanded;
    }
  }

  onStreamingChange(): void {
    if (this.isStreaming) {
      // Streaming started — reset user-interaction flag and clear any pending auto-collapse
      this.userToggled = false;
      if (this.collapseTimer !== -1) {
        clearTimeout(this.collapseTimer);
        this.collapseTimer = -1;
      }
      this.expanded = true;
    } else {
      // Streaming finished — auto-collapse after 2.5s if user hasn't manually toggled
      if (this.expanded && !this.userToggled) {
        this.collapseTimer = setTimeout(() => {
          this.getUIContext()?.animateTo({ duration: Duration.normal, curve: AnimationPresets.spring }, () => {
            this.expanded = false;
          });
          this.collapseTimer = -1;
        }, 2500);
      }
    }
  }

  build() {
    Column() {
      Button() {
        Row() {
          if (this.isStreaming) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(FontSize.sm)
              .fontColor([Colors.accent])
              .margin({ right: Spacing.xs })
              .transition(AnimationPresets.fadeIn)
          } else {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(FontSize.sm)
              .fontColor([Colors.success])
              .margin({ right: Spacing.xs })
              .transition(AnimationPresets.fadeIn)
          }

          if (this.isStreaming) {
            Text($r('app.string.thinking_label'))
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundMuted)
              .fontWeight(FontWeight.Medium)
          } else {
            Text($r('app.string.thinking_done_label'))
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundMuted)
              .fontWeight(FontWeight.Medium)
          }

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(FontSize.sm)
            .fontColor([Colors.foregroundMuted])
            .accessibilityText(this.expanded ? this.text($r('app.string.thinking_collapse')) : this.text($r('app.string.thinking_expand')))
            .rotate({ z: 1, angle: this.expanded ? 0 : -90 })
        }
        .width('100%')
        .height(34)
        .padding({ left: Spacing.md, right: Spacing.md })
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(12)
      .stateStyles({
        pressed: { .backgroundColor(Colors.border) },
        normal: { .backgroundColor(Color.Transparent) }
      })
      .onClick(() => {
        this.userToggled = true;
        if (this.collapseTimer !== -1) {
          clearTimeout(this.collapseTimer);
          this.collapseTimer = -1;
        }
        this.getUIContext()?.animateTo({ duration: Duration.normal, curve: AnimationPresets.spring }, () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded && this.thinking.length > 0) {
        Row() {
          Text(this.thinking)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foreground)
            .lineHeight(22)
            .width('100%')
        }
        .width('100%')
        .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
        .margin({ top: Spacing.xs, bottom: Spacing.xs })
        .borderRadius(12)
        .backgroundColor(Color.Transparent)
        .transition(AnimationPresets.fadeIn)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
    .transition(AnimationPresets.fadeIn)
  }
}
