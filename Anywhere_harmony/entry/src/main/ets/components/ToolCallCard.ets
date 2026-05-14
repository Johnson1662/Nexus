import { Colors } from '../constants/Colors';
import { FontSize, Spacing, Radius, Duration } from '../constants/DesignTokens';

@Component
export struct ToolCallCard {
  @Prop name: string = 'Tool';
  @Prop status: string = 'pending';

  private getStatusMark(): string {
    if (this.status === 'completed') return '✓';
    if (this.status === 'failed') return '✗';
    if (this.status === 'in_progress') return '⚙';
    return '⏱';
  }

  private getStatusColor(): string {
    if (this.status === 'completed') return Colors.success;
    if (this.status === 'failed') return Colors.error;
    if (this.status === 'in_progress') return Colors.warning;
    return Colors.foregroundMuted;
  }

  private getStatusBg(): string {
    if (this.status === 'completed') return Colors.successLight;
    if (this.status === 'failed') return Colors.errorLight;
    if (this.status === 'in_progress') return Colors.warningLight;
    return Colors.surface1;
  }

  private getStatusText(): string {
    if (this.status === 'pending') return '等待中...';
    if (this.status === 'in_progress') return '执行中...';
    if (this.status === 'completed') return '已完成';
    if (this.status === 'failed') return '失败';
    return this.status;
  }

  build() {
    Row() {
      Column() {
        if (this.status === 'in_progress') {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.getStatusColor())
        } else {
          Text(this.getStatusMark())
            .fontSize(FontSize.md)
            .fontColor(this.getStatusColor())
            .fontWeight(FontWeight.Bold)
        }
      }
      .width(36)
      .height(36)
      .backgroundColor(this.getStatusBg())
      .borderRadius(Radius.lg)
      .justifyContent(FlexAlign.Center)
      .margin({ right: Spacing.md })

      Column() {
        Text(this.name)
          .fontSize(FontSize.base)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Medium)

        Text(this.getStatusText())
          .fontSize(FontSize.sm)
          .fontColor(this.getStatusColor())
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
    .backgroundColor(Colors.surfaceElevated)
    .borderRadius(Radius.lg)
    .border({ width: 1, color: this.status === 'in_progress' ? Colors.accentLight : Colors.borderLight })
    .constraintSize({ maxWidth: '90%' })
    .margin({ left: Spacing.lg })
    .shadow({ radius: 4, color: Colors.shadowColor, offsetY: 2 })
  }
}
