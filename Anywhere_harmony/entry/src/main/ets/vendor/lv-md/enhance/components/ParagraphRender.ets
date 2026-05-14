import { ImageBuilder } from '../builders/ImageBuilder'
import { TextSelectionController } from '../controller/TextSelectionController'
import { MDBaseController } from '../controller/BaseController'
import { LatexNode, PluginNode, TreeNode } from '../model/TreeNode'
import { SpanRenderBuilder } from '../builders/SpanRenderBuilder'
import { TextImpl } from '../impl/TextImpl'
import { IntactImpl } from '../impl/IntactImpl'
import { LatexImpl } from '../impl/LatexImpl'
import { getLatexText, preloadLatexImage } from '../builders/LatexBuilder'
import { buildSelectionSegmentsFromBlock } from '../utils/selectionText'
import { generateRandomString } from '../utils/RandomString'
import { BlockSelectionStartInfo } from '../model/TextSelectionInfo'
import {
  buildInlinePluginRects,
  buildParagraphInlinePluginPlacements,
  InlinePluginPlacement,
  InlinePluginRect,
  isSameInlinePluginRects
} from '../utils/inlinePluginOverlay'
import { getPluginRenderer, PluginInlineRenderHost } from './PluginRenderHost'

@Component
export struct ParagraphRender {
  @Consume markdownUnion: string
  @Consume selectionUnion: string
  @Consume pluginUnion: string
  @State @Watch('loadParagraphLatex') base: TreeNode | undefined = undefined
  @State private latexRefreshTick: number = 0
  @State private inlinePluginPlacements: InlinePluginPlacement[] = []
  @State private inlinePluginRects: InlinePluginRect[] = []
  private latexLoadingSet: Set<string> = new Set()
  private textController: TextController = new TextController()
  private selectionId: string = `md_select_${generateRandomString()}`
  private inlinePluginRefreshTimer: number = 0

  aboutToAppear(): void {
    this.prepareInlinePluginPlacements()
  }

  private prepareInlinePluginPlacements() {
    const placements = buildParagraphInlinePluginPlacements(this.markdownUnion, this.pluginUnion, this.base)
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
  }

  private collectLatexNodes(node: TreeNode | undefined, nodes: LatexNode[]) {
    if (!node) {
      return
    }
    if (node.type == 'latex') {
      nodes.push(node as LatexNode)
      return
    }
    if (!node.children || node.children.length == 0) {
      return
    }
    for (let i = 0; i < node.children.length; i++) {
      this.collectLatexNodes(node.children[i] as TreeNode, nodes)
    }
  }

  private loadParagraphLatex() {
    this.syncSelectionBlock()
    this.prepareInlinePluginPlacements()
    this.refreshInlinePluginRectsSoon()
    const nodes: LatexNode[] = []
    this.collectLatexNodes(this.base, nodes)
    if (nodes.length == 0) {
      return
    }

    let uiContext: UIContext
    try {
      uiContext = this.getUIContext()
    } catch (_err) {
      return
    }

    const taskList: Promise<void>[] = []
    for (let i = 0; i < nodes.length; i++) {
      const latexText = getLatexText(nodes[i] as ESObject)
      const taskKey = `${this.markdownUnion}_${latexText}`
      if (!latexText || this.latexLoadingSet.has(taskKey)) {
        continue
      }
      this.latexLoadingSet.add(taskKey)
      taskList.push(preloadLatexImage(this.markdownUnion, latexText, uiContext).then(() => {
        this.latexLoadingSet.delete(taskKey)
      }).catch(() => {
        this.latexLoadingSet.delete(taskKey)
      }))
    }

    if (taskList.length > 0) {
      Promise.all(taskList).then(() => {
        this.latexRefreshTick++
        this.refreshInlinePluginRectsSoon()
      })
    }
  }

  private hasLatexNode(node?: TreeNode): boolean {
    if (!node) {
      return false
    }
    if (node.type == "latex") {
      return true
    }
    if (!node.children || node.children.length == 0) {
      return false
    }
    for (let i = 0; i < node.children.length; i++) {
      if (this.hasLatexNode((node.children[i] as TreeNode))) {
        return true
      }
    }
    return false
  }

  private getParagraphLineHeight(): ResourceStr | number {
    const textLineHeight = TextImpl.handleLineHeight(this.markdownUnion)
    if (!this.hasLatexNode(this.base)) {
      return textLineHeight
    }
    const latexSize = LatexImpl.handleLatexMathTextSize(this.markdownUnion)
    const latexLineHeight = Math.ceil(latexSize * 1.8)
    if (typeof textLineHeight === 'number') {
      return Math.max(textLineHeight, latexLineHeight)
    }
    return latexLineHeight
  }

  build() {
    Column({ space: IntactImpl.handleBlockSpacing(this.markdownUnion) }) {
      if (this.inlinePluginPlacements.length == 0) {
        Text('', { controller: this.textController }) {
          ForEach(this.base?.children, (item: TreeNode) => {
            if (item.type == "image") {
              ImageBuilder(this.markdownUnion, item)
            } else {
              SpanRenderBuilder(this.markdownUnion, this.pluginUnion, item, this.getUIContext(), this.latexRefreshTick)
            }
          })
        }
        .id(this.selectionId)
        .lineHeight(this.getParagraphLineHeight())
        .fontSize(TextImpl.handleFontSize(this.markdownUnion))
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
        .onAppear(() => {
          this.loadParagraphLatex()
        })
        .onDisAppear(() => {
          this.clearInlinePluginRefreshTimer()
          TextSelectionController.getInstance(this.selectionUnion).unregisterBlock(this.selectionId)
        })
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Text('', { controller: this.textController }) {
            ForEach(this.base?.children, (item: TreeNode) => {
              if (item.type == "image") {
                ImageBuilder(this.markdownUnion, item)
              } else {
                SpanRenderBuilder(this.markdownUnion, this.pluginUnion, item, this.getUIContext(), this.latexRefreshTick)
              }
            })
          }
          .id(this.selectionId)
          .lineHeight(this.getParagraphLineHeight())
          .fontSize(TextImpl.handleFontSize(this.markdownUnion))
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
          .onAppear(() => {
            this.loadParagraphLatex()
          })
          .onDisAppear(() => {
            this.clearInlinePluginRefreshTimer()
            TextSelectionController.getInstance(this.selectionUnion).unregisterBlock(this.selectionId)
          })

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
    }
    .alignItems(HorizontalAlign.Start)
  }
}
