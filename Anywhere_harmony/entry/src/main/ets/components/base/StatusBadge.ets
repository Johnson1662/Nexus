import { Colors, Radius, FontSize, Spacing } from '../../constants/DesignTokens';

@Component
export struct StatusBadge {
  @Prop isOnline: boolean = false;
  @Prop label: string = '';
  @Prop showDot: boolean = true;
  
  build() {
    Row() {
      if (this.showDot) {
        Circle()
          .width(8)
          .height(8)
          .fill(this.isOnline ? Colors.success : Colors.error)
          .margin({ right: 6 })
      }
      
      Text(this.label)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
    }
    .padding({ left: Spacing.md, right: Spacing.md, top: 6, bottom: 6 })
    .backgroundColor(Colors.surface0)
    .borderRadius(Radius.lg)
  }
}
