import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';
import { PlanEntry } from '../model/ChatState';

@Component
export struct PlanView {
  @Prop entries: PlanEntry[] = [];

  build() {
    Column() {
      ForEach(this.entries, (entry: PlanEntry, index: number) => {
        Row() {
          if (entry.status === 'completed') {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.sm })
          } else if (entry.status === 'in_progress') {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(16).fontColor([Colors.foreground]).margin({ right: Spacing.sm })
          } else {
            SymbolGlyph($r('sys.symbol.circle')).fontSize(16).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.sm })
          }
          Text(entry.content)
            .fontSize(FontSize.sm)
            .fontColor(entry.status === 'completed' ? Colors.foregroundMuted : Colors.foreground)
            .lineHeight(22)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: Spacing.xs, bottom: Spacing.xs })
        .alignItems(VerticalAlign.Top)
      }, (entry: PlanEntry, index: number) => entry.content + index.toString())
    }
    .width('100%')
    .backgroundColor(Colors.surface0)
    .borderRadius(12)
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
    .alignItems(HorizontalAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }
}
