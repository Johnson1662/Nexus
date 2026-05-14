import { markdownCodeThemeChangeEventName } from '../constant/CodeTheme';
import { MDBaseController } from '../controller/BaseController';
import { CodeBlockImpl } from '../impl/CodeBlockImpl';
import { HighlightCode, HighlightNode } from '../model/highlightNode';
import { CodeBlockNode } from '../model/TreeNode';
import { highlightCodeToJSON } from '../utils/highlightCode';

@Component
export struct CodeRender {
  @Consume markdownUnion: string
  @State base: CodeBlockNode | undefined = undefined
  @State highlightNode: HighlightNode[] = []
  @State MAX_ROWS: number = 10
  BASE_ROWS: number = 10

  aboutToAppear(): void {
    this.getHighlightNode()
    this.codeThemeChangeListener()
  }

  aboutToDisappear(): void {
    getContext().eventHub.off(markdownCodeThemeChangeEventName)
  }

  codeThemeChangeListener() {
    getContext().eventHub.on(markdownCodeThemeChangeEventName, () => {
      this.getHighlightNode()
    })
  }

  getHighlightNode() {
    if (this.base?.type == "codeBlock") {
      this.highlightNode = highlightCodeToJSON(this.base?.text,
        MDBaseController.getMarkdownController(this.markdownUnion).getCodeHighlight()) as HighlightNode[]
      this.BASE_ROWS = this.highlightNode.length
    }
  }

  showMore() {
    this.getUIContext().animateTo({ duration: 300 }, () => {
      this.MAX_ROWS = this.BASE_ROWS
    })
  }

  build() {
    Column() {
      Row() {
        Text(this.base?.lang || "code")
          .fontSize(15)
          .fontColor(MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == "dark" ?
            "#F9FAFB" : "#cd000000")
          .fontWeight(FontWeight.Medium)

        Button() {
          if (MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == "dark") {
            Image($rawfile("imgs/plus_square_on_square_fill_w.png")).width(18).height(18)
              .interpolation(ImageInterpolation.Medium)
          } else {
            Image($rawfile("imgs/plus_square_on_square_fill_b.png")).width(18).height(18)
              .interpolation(ImageInterpolation.Medium)
          }
        }
        .backgroundColor(Color.Transparent)
        .width(30)
        .height(30)
        .borderRadius(8)
        .onClick(() => {
          CodeBlockImpl.copyText(this.markdownUnion, this.base?.text || "")
        })
      }
      .width("100%")
      .padding({
        left: 14,
        right: 12
      })
      .height(42)
      .margin({ bottom: 10 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor(MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == "dark" ?
        "#24262B" : "#F3F4F6")

      Row() {
        if (MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockIdxState()) {
          Column() {
            ForEach(this.highlightNode.slice(0, this.MAX_ROWS), (row: HighlightNode, idx: number) => {
              Row() {
                Text(idx + 1 + "")
                  .lineHeight(22)
                  .fontSize(14)
                  .fontColor(MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == "dark" ?
                    "#ff6d7273" : "#606366")
              }
              .justifyContent(FlexAlign.End)
              .padding({ right: 6 })
              .height(22)
              .border({
                width: {
                  top: 0,
                  left: 0,
                  bottom: 0,
                  right: 0.8
                },
                color: MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == "dark" ?
                  "#2cd8dfe7" : "#2c4d5053"
              })
              .width(34)
            })
          }
          .width(34)
        }

        Scroll() {
          Column() {
            ForEach(this.highlightNode.slice(0, this.MAX_ROWS), (row: HighlightNode) => {
              Row() {
                Text() {
                  ForEach(row.code, (code: HighlightCode) => {
                    Span(code.text)
                      .fontColor(code.color)
                  })
                }
                .lineHeight(22)
                .fontSize(14.8)
              }
              .height(22)
            })
          }
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 12,
            right: 12,
            bottom: 12
          })
        }
        .width(`calc(100% - ${MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockIdxState() ? 34 :
          0}vp)`)
        .align(Alignment.Start)
        .scrollable(ScrollDirection.Horizontal)
        .edgeEffect(EdgeEffect.Spring)
      }
      .alignItems(VerticalAlign.Top)
      .width("100%")

      if (this.BASE_ROWS >= 10 && this.BASE_ROWS != this.MAX_ROWS) {
        Row() {
          Row() {
            Image($rawfile("imgs/down_b.png")).width(20).height(20)
          }
          .justifyContent(FlexAlign.Center)
          .width(60)
          .height(25)
          .borderRadius(99)
          .backgroundColor("#5cffffff")
          .margin({ bottom: 7 })
          .onClick(() => {
            this.showMore()
          })
        }
        // .margin({ bottom: 12 })
        .width("100%")
        .justifyContent(FlexAlign.Center)
      }
    }
    .width("100%")
    .alignItems(HorizontalAlign.Start)
    .borderRadius(CodeBlockImpl.handleCodeBlockBorderRadius(this.markdownUnion))
    .clip(true)
    .backgroundColor(CodeBlockImpl.handleBackgroundColor(MDBaseController.getMarkdownController(this.markdownUnion)
      .getCodeBlockTheme()))
  }
}