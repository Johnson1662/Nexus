import { QuoteImpl } from '../impl/QuoteImpl';
import { TreeNode } from '../model/TreeNode';
import { IntactRender } from './IntactRender';

@Component
export struct BlockquoteRender {
  @Consume markdownUnion: string
  @State base: TreeNode | undefined = undefined

  build() {
    if (this.base && this.base.children) {
      Column() {
        IntactRender({ children: this.base.children as TreeNode[] })
      }
      .margin({ top: 5, bottom: 5 })
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .backgroundColor(QuoteImpl.handleBackgroundColor(this.markdownUnion))
      .padding(QuoteImpl.handleQuotePadding(this.markdownUnion))
      .border({
        radius: QuoteImpl.handleBorderRadius(this.markdownUnion),
        color: {
          left: QuoteImpl.handleBorderColor(this.markdownUnion)
        },
        style: {
          left: BorderStyle.Solid
        },
        width: {
          left: QuoteImpl.handleBorderWidth(this.markdownUnion),
          right: '0',
          top: '0',
          bottom: '0'
        }
      })
    }
  }
}