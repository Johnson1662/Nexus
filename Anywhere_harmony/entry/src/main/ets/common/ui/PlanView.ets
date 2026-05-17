import { Colors, FontSize, Spacing } from '../../constants/DesignTokens';
import { PlanEntry } from '../model/ChatState';

@Component
export struct PlanView {
  @Prop entries: PlanEntry[] = [];

  build() {
    Column() {
      ForEach(this.entries, (entry: PlanEntry, index: number) => {
        Row() {
          Text((index + 1).toString() + '.')
            .fontSize(FontSize.sm)
            .fontColor(entry.status === 'completed' ? Colors.foreground : Colors.foregroundMuted)
            .fontWeight(FontWeight.Bold)
            .margin({ right: Spacing.sm })
          
          Text(entry.content)
            .fontSize(FontSize.sm)
            .fontColor(entry.status === 'completed' ? Colors.foreground : Colors.foregroundMuted)
            .lineHeight(22)
            .layoutWeight(1)
            
          if (entry.status === 'completed') {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontColor([Colors.success])
              .fontSize(16)
              .margin({ left: Spacing.sm, top: 3 })
          } else if (entry.status === 'in_progress') {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(Colors.foregroundMuted)
              .margin({ left: Spacing.sm, top: 4 })
          }
        }
        .width('100%')
        .padding({ top: Spacing.xs, bottom: Spacing.xs })
        .alignItems(VerticalAlign.Top)
      }, (entry: PlanEntry, index: number) => entry.content + index.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
