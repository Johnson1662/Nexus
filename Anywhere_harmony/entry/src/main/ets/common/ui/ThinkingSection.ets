import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';
import { CustomIcon } from './CustomIcon';
@Component
export struct ThinkingSection {
  @Prop thinking: string = '';
  @Prop @Watch('onStreamingChange') isStreaming: boolean = false;
  @StorageLink('pref_thinking_expanded') prefThinkingExpanded: boolean = true;
  @State expanded: boolean = true;

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
      // Header
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
          .accessibilityText(this.expanded ? 'Collapse thinking' : 'Expand thinking')
          .rotate({ z: 1, angle: this.expanded ? 0 : -90 })
          .animation({ duration: 200, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
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
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin(0)
  }
}
