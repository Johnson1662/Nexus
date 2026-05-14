import { Colors, FontSize, Spacing, Radius } from '../../constants/Colors';
import { PlanEntry } from '../model/ChatState';

@Component
export struct PlanView {
  @Prop entries: PlanEntry[] = [];

  build() {
    Column() {
      ForEach(this.entries, (entry: PlanEntry, index: number) => {
        Row() {
          Row() {
            Text((index + 1).toString())
              .fontSize(10)
              .fontColor(entry.status === 'completed' ? Colors.accentDark : Colors.foregroundMuted)
              .fontWeight(FontWeight.Bold)
          }
          .width(16)
          .height(16)
          .borderRadius(Radius.full)
          .backgroundColor(entry.status === 'completed' ? Colors.accentLight : Colors.surface2)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          
          Text(entry.content)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foreground)
            .lineHeight(20)
            .margin({ left: Spacing.sm })
            .layoutWeight(1)
            
          if (entry.status === 'completed') {
            Image($r('app.media.ic_check')).fillColor(Colors.success).width(16).height(16).margin({ left: Spacing.sm, top: 4 })
          } else if (entry.status === 'in_progress') {
            Image($r('app.media.ic_dots')).fillColor(Colors.warning).width(16).height(16).margin({ left: Spacing.sm, top: 4 })
          } else {
            Image($r('app.media.ic_circle')).fillColor(Colors.foregroundLight).width(16).height(16).margin({ left: Spacing.sm, top: 4 })
          }
        }
        .width('100%')
        .padding({ top: Spacing.xs, bottom: Spacing.xs })
        .alignItems(VerticalAlign.Top)
      }, (entry: PlanEntry, index: number) => entry.content + index.toString())
    }
    .width('100%')
  }
}
