import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { Colors } from '../../constants/Colors';

@Component
export struct MarkdownRender {
  @Prop text: string = '';

  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    // ── Typography (match FontSize.base = 15, lineHeight = 24) ──
    this.controller.setTextColor(Colors.foreground);
    this.controller.setTextSize(15);
    this.controller.setTextLineHeight(24);
    this.controller.setTitleColor('#1A1A1A');

    // ── Code blocks (light theme, no line numbers) ──
    this.controller.setCodeBlockTheme('light');
    this.controller.setCodeBlockIdxState(false);
    this.controller.setCodeBlockBorderRadius(6);

    // ── Tables ──
    this.controller.setTableBackgroundColor('#FFFFFF');
    this.controller.setTableInterleaveBackgroundColor('#F5F5F5');
    this.controller.setTableBorderRadius(6);

    // ── Blockquotes ──
    this.controller.setQuoteBackgroundColor('#F8F9FA');
    this.controller.setQuoteBorderColor('#20744A');

    // ── Hyperlinks ──
    this.controller.setHyperlinkTextColor(Colors.accent);
    this.controller.setHyperlinkUnderlineState(true);

    // ── Layout & performance ──
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
