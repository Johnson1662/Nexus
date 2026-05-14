import { Markdown } from '../../vendor/lv-md/enhance/index';
import { MarkdownController } from '../../vendor/lv-md/enhance/controller/MarkdonwController';
import { Colors } from '../../constants/Colors';

@Component
export struct MarkdownRender {
  @Prop text: string = '';
  @Prop streaming: boolean = false;

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
    this.controller.setQuoteBorderColor('#20744A');
    this.controller.setHyperlinkTextColor(Colors.accent);
    this.controller.setHyperlinkUnderlineState(true);
    this.controller.setThreadRenderEnable(true);
    this.controller.setBlockSpacing(10);
  }

  build() {
    Markdown({
      text: this.text,
      controller: this.controller,
      streaming: this.streaming
    })
      .width('100%')
  }
}
