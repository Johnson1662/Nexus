import { Colors, FontSize, Spacing, Radius, Duration } from '../constants/DesignTokens';
import { PlanEntry } from '../store/SessionStore';

@Component
export struct PlanView {
  @Prop entries: PlanEntry[] = [];

  private getCompletedCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].status === 'completed') {
        count++;
      }
    }
    return count;
  }

  private getProgress(): number {
    if (this.entries.length === 0) return 0;
    return this.getCompletedCount() / this.entries.length;
  }

  private getStatusMark(status: string): string {
    if (status === 'completed') return '✓';
    if (status === 'in_progress') return '⚙';
    return '⏱';
  }

  private getStatusColor(status: string): string {
    if (status === 'completed') return Colors.success;
    if (status === 'in_progress') return Colors.warning;
    return Colors.foregroundMuted;
  }

  private getStatusBg(status: string): string {
    if (status === 'completed') return Colors.successLight;
    if (status === 'in_progress') return Colors.warningLight;
    return Colors.surface1;
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text('📋')
            .fontSize(FontSize.lg)
        }
        .width(28)
        .height(28)
        .backgroundColor(Colors.accentLight)
        .borderRadius(Radius.md)
        .justifyContent(FlexAlign.Center)
        .margin({ right: Spacing.sm })

        Text('执行计划')
          .fontSize(FontSize.base)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .layoutWeight(1)

        Text(this.getCompletedCount().toString() + '/' + this.entries.length.toString())
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .margin({ bottom: Spacing.md })

      Stack() {
        Row()
          .width('100%')
          .height(6)
          .backgroundColor(Colors.surface1)
          .borderRadius(3)

        Row()
          .width((this.getProgress() * 100).toString() + '%')
          .height(6)
          .backgroundColor(Colors.accent)
          .borderRadius(3)
          .animation({
            duration: Duration.normal,
            curve: Curve.EaseInOut
          })
      }
      .width('100%')
      .margin({ bottom: Spacing.lg })
      .alignContent(Alignment.Center)

      ForEach(this.entries, (entry: PlanEntry, index: number) => {
        Row() {
          Row() {
            Text((index + 1).toString())
              .fontSize(10)
              .fontColor(entry.status === 'completed' ? Color.White : Colors.foregroundMuted)
              .fontWeight(FontWeight.Bold)
          }
          .width(20)
          .height(20)
          .backgroundColor(entry.status === 'completed' ? Colors.success : Colors.surface2)
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .margin({ right: Spacing.md })

          Text(this.getStatusMark(entry.status))
            .fontSize(FontSize.md)
            .fontColor(this.getStatusColor(entry.status))
            .margin({ right: Spacing.md })
            .fontWeight(FontWeight.Bold)

          Text(entry.content)
            .fontSize(FontSize.md)
            .fontColor(Colors.foreground)
            .layoutWeight(1)
            .lineHeight(20)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
        .backgroundColor(this.getStatusBg(entry.status))
        .borderRadius(Radius.md)
        .margin({ bottom: Spacing.xs })
        .border({ width: 1, color: entry.status === 'in_progress' ? Colors.accent : Colors.borderLight })
      }, (entry: PlanEntry, index: number) => entry.content + '_' + index.toString())
    }
    .width('100%')
    .padding(Spacing.lg)
    .backgroundColor(Colors.surfaceElevated)
    .borderRadius(Radius.lg)
    .margin({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
    .constraintSize({ maxWidth: '90%' })
    .shadow({ radius: 6, color: Colors.shadowColor, offsetY: 3 })
  }
}
