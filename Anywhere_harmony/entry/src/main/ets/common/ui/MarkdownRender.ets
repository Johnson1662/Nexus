import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { Colors } from '../../constants/DesignTokens';

@Component
export struct MarkdownRender {
  @Prop text: string = '';

  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    this.controller.setTextColor(Colors.foreground);
    this.controller.setTextSize(15);
    this.controller.setTextLineHeight(24);
    this.controller.setTitleColor('#1A1A1A');
    this.controller.setCodeBlockTheme('light');
    this.controller.setCodeBlockIdxState(false);
    this.controller.setCodeBlockBorderRadius(6);
    this.controller.setTableBackgroundColor('#FFFFFF');
    this.controller.setTableInterleaveBackgroundColor('#F5F5F5');
    this.controller.setTableBorderRadius(6);
    this.controller.setQuoteBackgroundColor('#F8F9FA');
    this.controller.setQuoteBorderColor(Colors.accent);
    this.controller.setHyperlinkTextColor(Colors.accent);
    this.controller.setHyperlinkUnderlineState(true);
    this.controller.setThreadRenderEnable(true);
    this.controller.setBlockSpacing(10);
  }

  build() {
    Markdown({
      text: this.text,
      controller: this.controller
    })
      .width('100%')
  }
}
