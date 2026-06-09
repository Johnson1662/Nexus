import { Colors, FontSize, Spacing, Radius, Duration, getLocalizedString } from '../../constants/DesignTokens';
import { CustomIcon } from './CustomIcon';
@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Prop @Watch('onStreamingChange') isStreaming: boolean = false;
  @StorageLink('pref_thinking_expanded') prefThinkingExpanded: boolean = true;
  @State expanded: boolean = true;

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
    if (!this.isStreaming && this.expanded) {
      this.expanded = this.prefThinkingExpanded;
    }
  }

  build() {
    Column() {
      Row() {
        CustomIcon({
          name: this.isStreaming ? 'thinking' : 'thinking_done',
          iconSize: 16,
          color: Colors.foregroundMuted
        }).margin({ right: Spacing.sm })

        if (this.isStreaming) {
          Text($r('app.string.thinking_label'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .fontWeight(FontWeight.Medium)
        } else {
          Text($r('app.string.thinking_done_label'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .fontWeight(FontWeight.Medium)
        }

        Blank()

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(FontSize.md)
          .fontColor([Colors.foregroundMuted])
          .accessibilityText(this.expanded ? this.text($r('app.string.thinking_collapse')) : this.text($r('app.string.thinking_expand')))
          .rotate({ z: 1, angle: this.expanded ? 0 : -90 })
          .animation({ duration: Duration.normal, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height(36)
      .padding({ left: Spacing.sm })
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        pressed: { .backgroundColor(Colors.surface1) },
        normal: { .backgroundColor(Colors.transparent) }
      })
      .animation({ duration: Duration.fast, curve: Curve.EaseOut })
      .borderRadius(Radius.md)
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: Duration.normal, curve: Curve.EaseInOut }, () => {
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
        .margin({ left: 7 })
        .border({ width: { left: 1 }, color: { left: Colors.border } })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -4 })))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
    .transition(TransitionEffect.OPACITY)
  }
}
