import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { Colors } from '../../constants/Colors';

@Component
export struct MarkdownRender {
  @Prop text: string = '';
  @Prop mathEnabled: boolean = true;

  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    // ── Typography ──
    this.controller.setTextColor(Colors.foreground);
    this.controller.setTextSize(14);
    this.controller.setTitleColor('#1A1A1A');

    // ── Code blocks (light theme to match terminal aesthetic) ──
    this.controller.setCodeBlockTheme('light');
    this.controller.setCodeBlockIdxState(false);

    // ── Tables ──
    this.controller.setTableBackgroundColor('#FFFFFF');
    this.controller.setTableInterleaveBackgroundColor('#F5F5F5');

    // ── Blockquotes ──
    this.controller.setQuoteBackgroundColor('#F8F9FA');
    this.controller.setQuoteBorderColor('#20744A');

    // ── Worker thread for performance ──
    this.controller.setThreadRenderEnable(true);
  }

  build() {
    Markdown({
      text: this.text,
      controller: this.controller
    })
      .width('100%')
  }
}
