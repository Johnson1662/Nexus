import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';
import { PlanEntry } from '../model/ChatState';

@Component
export struct PlanView {
  @Prop entries: PlanEntry[] = [];

  build() {
    Column() {
      ForEach(this.entries, (entry: PlanEntry, index: number) => {
        if (index > 0) {
          Row().height(0.5).backgroundColor(Colors.borderLight).width('100%').margin({ left: 24, top: Spacing.xs, bottom: Spacing.xs })
        }
        Row() {
          if (entry.status === 'completed') {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(14)
              .fontColor([Colors.foregroundMuted])
              .margin({ right: Spacing.sm })
          } else if (entry.status === 'in_progress') {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(Colors.accent)
              .margin({ right: Spacing.sm })
          } else {
            SymbolGlyph($r('sys.symbol.circle'))
              .fontSize(14)
              .fontColor([Colors.foregroundMuted])
              .margin({ right: Spacing.sm })
          }
          Text(entry.content)
            .fontSize(FontSize.sm)
            .fontColor(entry.status === 'completed' ? Colors.foregroundMuted : Colors.foreground)
            .fontWeight(entry.status === 'in_progress' ? FontWeight.Medium : FontWeight.Regular)
            .lineHeight(22)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: Spacing.sm, bottom: Spacing.sm })
        .alignItems(VerticalAlign.Top)
      }, (entry: PlanEntry, index: number) => entry.content + index.toString())
    }
    .width('100%')
    .padding(Spacing.md)
    .backgroundColor(Colors.surface1)
    .borderRadius(Radius.md)
    .alignItems(HorizontalAlign.Start)
  }
}
