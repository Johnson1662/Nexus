import { BaseSpanRenderBuilder } from '../builders/SpanRenderBuilder';
import { MDBaseController } from '../controller/BaseController';
import { TextSelectionController } from '../controller/TextSelectionController';
import { TextImpl } from '../impl/TextImpl';
import { PluginNode, TextNode, TreeNode } from '../model/TreeNode';
import { BlockSelectionStartInfo } from '../model/TextSelectionInfo';
import { buildSelectionSegmentsFromBlock } from '../utils/selectionText';
import { generateRandomString } from '../utils/RandomString';
import {
  hasPluginInlineOverlay,
  PluginInlinePlaceholderSpan,
  getPluginRenderer,
  PluginInlineRenderHost
} from './PluginRenderHost';
import {
  buildInlinePluginRects,
  buildTextInlinePluginPlacements,
  InlinePluginPlacement,
  InlinePluginRect,
  isSameInlinePluginRects
} from '../utils/inlinePluginOverlay';

@Component
export struct TextRender {
  @Consume markdownUnion: string
  @Consume selectionUnion: string
  @Consume pluginUnion: string
  @State @Watch('syncSelectionBlock') base: TreeNode | undefined = undefined
  @State private inlinePluginPlacements: InlinePluginPlacement[] = []
  @State private inlinePluginRects: InlinePluginRect[] = []
  private textController: TextController = new TextController()
  private selectionId: string = `md_select_${generateRandomString()}`
  private inlinePluginRefreshTimer: number = 0

  aboutToAppear(): void {
    this.prepareInlinePluginPlacements()
  }

  private prepareInlinePluginPlacements() {
    const placements = buildTextInlinePluginPlacements(this.markdownUnion, this.pluginUnion, this.base)
    if (placements.length == 0 && this.inlinePluginPlacements.length == 0) {
      return
    }
    this.inlinePluginPlacements = placements
  }

  private refreshInlinePluginRects() {
    if (this.inlinePluginPlacements.length == 0) {
      if (this.inlinePluginRects.length > 0) {
        this.inlinePluginRects = []
      }
      return
    }
    try {
      const rects = buildInlinePluginRects(this.textController, this.inlinePluginPlacements, this.getUIContext())
      if (!isSameInlinePluginRects(this.inlinePluginRects, rects)) {
        this.inlinePluginRects = rects
      }
    } catch (_err) {
      if (this.inlinePluginRects.length > 0) {
        this.inlinePluginRects = []
      }
    }
  }

  private refreshInlinePluginRectsSoon() {
    if (this.inlinePluginPlacements.length == 0 || this.inlinePluginRefreshTimer > 0) {
      return
    }
    this.inlinePluginRefreshTimer = setTimeout(() => {
      this.inlinePluginRefreshTimer = 0
      this.refreshInlinePluginRects()
    }, 16)
  }

  private clearInlinePluginRefreshTimer() {
    if (this.inlinePluginRefreshTimer > 0) {
      clearTimeout(this.inlinePluginRefreshTimer)
      this.inlinePluginRefreshTimer = 0
    }
  }

  private handleTextAreaChange(oldValue: Area, newValue: Area) {
    const sizeSame = oldValue.width == newValue.width && oldValue.height == newValue.height
    if (this.inlinePluginPlacements.length == 0 || sizeSame) {
      return
    }
    this.refreshInlinePluginRectsSoon()
  }

  private syncSelectionBlock() {
    TextSelectionController.getInstance(this.selectionUnion)
      .registerBlock(this.selectionId, this.textController, buildSelectionSegmentsFromBlock(this.base))
    this.prepareInlinePluginPlacements()
    this.refreshInlinePluginRectsSoon()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text('', { controller: this.textController }) {
        ContainerSpan() {
          if (this.base?.type == "text" || this.base?.type == "inlineCode" || this.base?.type == "footnoteRef" ||
            this.base?.type == "inlineHtmlFont") {
            BaseSpanRenderBuilder(this.markdownUnion, this.base)
          } else {
            ForEach(this.base?.children, (item: TreeNode) => {
              if (item.type == "plugin") {
                if (hasPluginInlineOverlay(this.pluginUnion, item as PluginNode)) {
                  PluginInlinePlaceholderSpan(this.pluginUnion, item as PluginNode)
                } else {
                  BaseSpanRenderBuilder(this.markdownUnion, { text: (item as PluginNode).raw, type: 'text' })
                }
              } else if (item.type == "text" || item.type == "inlineHtmlFont") {
                // 传递根节点类型
                BaseSpanRenderBuilder(this.markdownUnion, {
                  text: item.text,
                  type: item.type == "inlineHtmlFont" ? item.type : this.base?.type,
                  url: this.base?.type == "link" ? this.base?.url : undefined,
                  color: item.type == "inlineHtmlFont" ? item.color : undefined,
                  size: item.type == "inlineHtmlFont" ? item.size : undefined,
                  face: item.type == "inlineHtmlFont" ? item.face : undefined
                }, this.base)
              } else {
                if (item?.type == "inlineCode") {
                  BaseSpanRenderBuilder(this.markdownUnion, item, this.base)
                } else {
                  // 被其他语法包裹的文本
                  ForEach(item.children, (item2: TreeNode) => {
                    if (item2.type == 'plugin') {
                      if (hasPluginInlineOverlay(this.pluginUnion, item2 as PluginNode)) {
                        PluginInlinePlaceholderSpan(this.pluginUnion, item2 as PluginNode)
                      } else {
                        BaseSpanRenderBuilder(this.markdownUnion, { text: (item2 as PluginNode).raw, type: 'text' }, this.base)
                      }
                    } else {
                      BaseSpanRenderBuilder(this.markdownUnion, {
                        text: (item2 as TextNode).text,
                        type: item.type,
                        url: item.type == "link" ? item.url : undefined
                      }, this.base)
                    }
                  })
                }
              }
            })
          }
        }
      }
      .id(this.selectionId)
      .copyOption(TextImpl.handleCopyOption(this.markdownUnion))
      .gesture(
        LongPressGesture()
          .onAction((event: GestureEvent) => {
            if (!MDBaseController.getMarkdownController(this.markdownUnion).getTextSelectionEnable() ||
              event.fingerList.length == 0) {
              return
            }
            const finger = event.fingerList[0]
            TextSelectionController.getInstance(this.selectionUnion)
              .triggerStartSelection(new BlockSelectionStartInfo(this.selectionId, finger.localX, finger.localY))
          })
      )
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.handleTextAreaChange(oldValue, newValue)
      })

      if (this.inlinePluginPlacements.length > 0) {
        ForEach(this.inlinePluginRects, (item: InlinePluginRect) => {
          if (getPluginRenderer(this.pluginUnion, item.node)) {
            PluginInlineRenderHost({
              node: item.node,
              renderer: getPluginRenderer(this.pluginUnion, item.node) as (node: PluginNode) => void
            })
              .width(item.width)
              .height(item.height)
              .position({ x: item.left, y: item.top })
              .hitTestBehavior(HitTestMode.Transparent)
              .zIndex(1)
          }
        })
      }
    }
    .id(TextImpl.handleSpanId(this.markdownUnion, this.base))
    .margin({
      top: (this.base?.type == "heading") ? 6 : null,
      bottom: (this.base?.type == "heading") ? 6 : null
    })
    .onAppear(() => {
      this.syncSelectionBlock()
    })
    .onDisAppear(() => {
      this.clearInlinePluginRefreshTimer()
      TextSelectionController.getInstance(this.selectionUnion).unregisterBlock(this.selectionId)
    })
  }
}
