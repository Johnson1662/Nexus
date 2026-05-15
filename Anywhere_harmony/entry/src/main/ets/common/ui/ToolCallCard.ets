import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';

@Component
export struct ToolCallCard {
  @Prop name: string = '';
  @Prop status: string = 'pending';

  build() {
    Row() {
      if (this.status === 'in_progress') {
        LoadingProgress().width(14).height(14).color(Colors.accent).margin({ right: Spacing.sm })
      } else if (this.status === 'completed') {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontColor([Colors.success])
          .fontSize(FontSize.sm)
          .margin({ right: Spacing.sm })
      } else if (this.status === 'failed') {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontColor([Colors.error])
          .fontSize(FontSize.sm)
          .margin({ right: Spacing.sm })
      } else {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontColor([Colors.foregroundMuted])
          .fontSize(FontSize.sm)
          .margin({ right: Spacing.sm })
      }

      Text(this.name)
        .fontSize(FontSize.sm)
        .fontFamily('monospace')
        .fontColor(Colors.foreground)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(this.getText())
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundMuted)
        .margin({ left: Spacing.sm })
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: 10, bottom: 10 })
    .backgroundColor(Colors.surfaceElevated)
    .borderRadius(Radius.md)
    .border({ width: 1, color: Colors.borderLight })
    .margin({ top: Spacing.xs, bottom: Spacing.xs })
    .transition(TransitionEffect.OPACITY)
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
  }

  getText(): string {
    if (this.status === 'pending') return '等待'
    if (this.status === 'in_progress') return '执行'
    if (this.status === 'completed') return '完成'
    if (this.status === 'failed') return '失败'
    return this.status
  }
}
