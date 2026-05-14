import { MarkdownController } from './controller/MarkdonwController';
import { MarkdownPluginRegistry } from './controller/PluginRegistry';
import { TextSelectionController } from './controller/TextSelectionController';
import { TableNode, TreeNode } from './model/TreeNode';

import { MarkdownPlugin, toPluginSyntaxManifestList } from './model/MarkdownPlugin';
import { MdCallback } from './model/MdCallback';
import { Logger } from './utils/Logger';
import {
  WorkerParam,
  WorkerParseReq,
  WorkerResTextParam,
  WorkerStringResp,
  WorkerTreeNodeResp
} from './model/WorkerParam';
import { IntactRender } from './components/IntactRender';
import { MainReader } from './mainThreadReader/reater';
import { BusinessError } from '@kit.BasicServicesKit';
import { LatexUtil } from './utils/LatextUtil';
import { WorkerManager } from './worker/WorkerManager';
import { generateRandomString } from './utils/RandomString';
import { getLatexText, preloadLatexImage } from './builders/LatexBuilder';
import { common2D } from '@kit.ArkGraphics2D';
import text from '@ohos.graphics.text';
import { BlockSelectionStartInfo, CaretInfo, RegisteredTextBlock, SelectedTextInfo } from './model/TextSelectionInfo';
import { componentUtils } from '@kit.ArkUI';

const TAG = "LV-MARKDOWN-IN"

/**
 * 承载 Markdown 内容渲染的组件。
 *
 * @controller 通过 MarkdownController 可以控制 Markdown 组件各种行为，如：自定义样式、设置图片点击拦截、设置超链接点击拦截等。
 * @text markdown 文本内容。
 * @mode Markdown 组件加载模式，支持纯文本加载、沙箱文件加载、资源文件加载，不填默认为 "text"。
 * @context mode 字段设置为 rawfile 时， context 为必填项。
 * @rawfilePath mode 字段设置为 rawfile 时， rawfilePath 为必填项，需传入 resources/rawfile 目录下对应的 rawfile 文件路径。
 * @sandboxPath mode 字段设置为 sandbox 时， sandboxPath 为必填项，需传入沙箱 text/md 文件的完整沙箱路径。例：getContext().getApplicationContext().filesDir + "/t2/text.md"。
 * @call callback回调方法，Markdown 组件加载状态结果告知。用于组件加载完成时，组件加载失败时回调，并返回错误码 code，错误信息 message，可用于问题分析。
 */
@Component
export struct Markdown {
  controller: MarkdownController = new MarkdownController()
  @Provide markdownUnion: string = ""
  @Provide selectionUnion: string = generateRandomString()
  @Provide pluginUnion: string = generateRandomString()
  /** 纯文本数据，mode：text */
  @Prop @Watch("_parseMarkdown") text: string = "";
  /**
   * 流式模式：启用后，text 更新会防抖解析，避免频繁重渲染。
   * 当 streaming 从 true 变为 false 时，立即执行最终解析。
   */
  @Prop @Watch("onStreamingChanged") streaming: boolean = false;
  private parsingInProgress: boolean = false;
  private needsReparse: boolean = false;
  plugins: MarkdownPlugin[] = []
  /** 加载模式：
   * text：纯文本模式
   * rawfile：rawfile资源文件模式
   * sandbox：本地沙箱路径文件模式
   */
  @Prop mode: "text" | "rawfile" | "sandbox" = "text";
  /**
   * 资源文件path
   */
  @Prop rawfilePath: string
  /**
   * 沙箱文件path
   */
  @Prop sandboxPath: string
  /**
   * 应用上下文
   */
  context: Context | undefined = undefined
  /**
   * 增强node集合
   */
  @State private treeNode: TreeNode[] = []
  private startCaretInfo: CaretInfo = new CaretInfo()
  private endCaretInfo: CaretInfo = new CaretInfo()
  @State private selectedTextInfos: SelectedTextInfo[] = []
  @State private selectionActive: boolean = false
  @State private selectionActionBarVisible: boolean = false
  @State private startCaretX: number = -100
  @State private startCaretY: number = -100
  @State private endCaretX: number = -100
  @State private endCaretY: number = -100
  private selectedRangeStartOrder: number = -1
  private selectedRangeEndOrder: number = -1
  private lastSelectionUpdateTime: number = 0
  private readonly selectionUpdateInterval: number = 24
  private readonly selectionVisualSyncInterval: number = 32
  private readonly initialSelectionLength: number = 3
  private readonly selectionActionBarWidth: number = 184
  private readonly selectionActionBarHeight: number = 40
  private readonly selectionActionBarSpacing: number = 12
  private readonly selectionActionBarEdgeInset: number = 8
  private selectionVisualSyncTimer: number = 0
  private lastSelectionRootScreenX: number = Number.NaN
  private lastSelectionRootScreenY: number = Number.NaN
  private workerManager: WorkerManager = WorkerManager.getInstance();
  private workerUnion: string = generateRandomString()
  private workerRegistered: boolean = false
  private selectionRootId: string = `md_selection_root_${generateRandomString()}`
  private selectionSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private selectionContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.selectionSettings)
  private rectRangeCache: Map<string, Map<string, common2D.Rect[]>> = new Map()
  @State private selectionLayerWidth: number = 0
  @State private selectionLayerHeight: number = 0
  /**
   * 事件回调
   */
  callback: MdCallback = {
    complete() {
    },
    fail(code: number, message: string) {
    }
  }

  private baseCallback(type: "success" | "fail", code?: number, message?: string) {
    if (type == "success") {
      if (this.callback.complete) {
        this.callback?.complete()
      }
    }
    if (type == "fail") {
      if (this.callback.fail && code && message) {
        this.callback?.fail(code, message)
      }
    }
  }

  aboutToAppear(): void {
    Logger.infoForce(TAG, "Thank you for using.")
    this.markdownUnion = this.controller.getUnion()
    this.registerPlugins()
    TextSelectionController.getInstance(this.selectionUnion)
      .setStartSelectionHandler((info: BlockSelectionStartInfo) => {
        this.startSelection(info)
      })
    TextSelectionController.getInstance(this.selectionUnion)
      .setClearSelectionHandler(() => {
        this.clearSelection()
      })
    this.ensureWorkerRegistered()
    this.handleLodeType()
  }

  aboutToDisappear(): void {
    this.stopSelectionVisualSync()
    MarkdownPluginRegistry.destroy(this.pluginUnion)
    if (this.workerRegistered) {
      this.workerManager.unregister(this.workerUnion)
      this.workerRegistered = false
    }
    TextSelectionController.getInstance(this.selectionUnion).setStartSelectionHandler(undefined)
    TextSelectionController.getInstance(this.selectionUnion).setClearSelectionHandler(undefined)
    TextSelectionController.getInstance(this.selectionUnion).releaseActiveSelection()
    TextSelectionController.destroy(this.selectionUnion)
    // 清理数学公式图片缓存，避免内存泄漏
    LatexUtil.clearCache();
    // MDBaseController.destroyMarkdownUnion(this.markdownUnion)
  }

  private clearSelection() {
    this.selectionActive = false
    this.selectionActionBarVisible = false
    this.stopSelectionVisualSync()
    TextSelectionController.getInstance(this.selectionUnion).releaseActiveSelection()
    this.startCaretInfo.reset()
    this.endCaretInfo.reset()
    this.startCaretX = -100
    this.startCaretY = -100
    this.endCaretX = -100
    this.endCaretY = -100
    this.selectedRangeStartOrder = -1
    this.selectedRangeEndOrder = -1
    this.lastSelectionUpdateTime = 0
    this.selectedTextInfos = []
    this.rectRangeCache.clear()
    this.lastSelectionRootScreenX = Number.NaN
    this.lastSelectionRootScreenY = Number.NaN
    this.selectionContext.reset()
  }

  private registerPlugins() {
    MarkdownPluginRegistry.registerPlugins(this.pluginUnion, this.plugins || [])
  }

  private ensureWorkerRegistered() {
    if (!this.controller.getThreadRenderEnable() || this.workerRegistered) {
      return
    }
    this.workerManager.register(this.workerUnion, (message) => {
      this.handleWorkerMessage(message);
    })
    this.workerRegistered = true
  }

  private handleWorkerMessage(message: WorkerTreeNodeResp | WorkerStringResp) {
    if (message.union !== this.workerUnion) {
      return;
    }

    if (message.key == "readerRawfile") {
      let data = message as WorkerStringResp;
      Logger.info(TAG, 'workerInstance onmessage is: ', data.data);
      this.text = data.data
      this._parseMarkdown()
    }
    if (message.key == "readerSandbox") {
      let data = message as WorkerStringResp;
      Logger.info(TAG, 'workerInstance onmessage is: ', data.data);
      this.text = data.data
      this._parseMarkdown()
    }
    if (message.key == "parse") {
      let data = message as WorkerTreeNodeResp;
      this.renderTreeNodeWithLatex(data.data)
      this.parsingInProgress = false
    }
  }

  private collectLatexTexts(node: TreeNode, latexTextSet: Set<string>) {
    if (node.type == 'latex') {
      const latexText = getLatexText(node as ESObject)
      if (latexText) {
        latexTextSet.add(latexText)
      }
      return
    }

    if (node.type == 'table') {
      const tableNode = node as TableNode
      if (tableNode.header) {
        for (let i = 0; i < tableNode.header.length; i++) {
          this.collectLatexTexts(tableNode.header[i] as TreeNode, latexTextSet)
        }
      }
      if (tableNode.rows) {
        for (let i = 0; i < tableNode.rows.length; i++) {
          this.collectLatexTexts(tableNode.rows[i] as TreeNode, latexTextSet)
        }
      }
      return
    }

    if (!node.children || node.children.length == 0) {
      return
    }
    for (let i = 0; i < node.children.length; i++) {
      this.collectLatexTexts(node.children[i] as TreeNode, latexTextSet)
    }
  }

  private preloadTreeLatex(treeNodes: TreeNode[]): Promise<void> {
    if (!treeNodes || treeNodes.length == 0) {
      return Promise.resolve()
    }

    const latexTextSet: Set<string> = new Set()
    for (let i = 0; i < treeNodes.length; i++) {
      this.collectLatexTexts(treeNodes[i], latexTextSet)
    }
    if (latexTextSet.size == 0) {
      return Promise.resolve()
    }

    let uiContext: UIContext
    try {
      uiContext = this.getUIContext()
    } catch (_err) {
      return Promise.resolve()
    }

    const taskList: Promise<void>[] = []
    latexTextSet.forEach((latexText: string) => {
      taskList.push(preloadLatexImage(this.markdownUnion, latexText, uiContext).then(() => {
      }).catch(() => {
      }))
    })

    return Promise.all(taskList).then(() => {
    })
  }

  private applyTreeNode(treeNodes: TreeNode[]) {
    this.clearSelection()
    try {
      this.getUIContext().animateTo({ duration: 10 }, () => {
        this.treeNode = treeNodes
      })
    } catch (_err) {
      this.treeNode = treeNodes
    }
    Logger.info(TAG, "treeNode data prepared. length: " + this.treeNode.length)
  }

  private renderTreeNodeWithLatex(treeNodes: TreeNode[]) {
    this.preloadTreeLatex(treeNodes).then(() => {
      this.applyTreeNode(treeNodes)
    }).catch(() => {
      this.applyTreeNode(treeNodes)
    })
  }

  private onStreamingChanged() {
    if (!this.streaming) {
      Logger.info(TAG, "Streaming ended, performing final parse.");
      this.parsingInProgress = false
      this.needsReparse = false
      if (this.text) {
        this.doParseMarkdown()
      }
    }
  }

  private handleLodeType() {
    if (this.mode == "rawfile") {
      this._loadRawfile()
    }
    if (this.mode == "sandbox") {
      this._loadSandbox()
    }
  }

  // 1
  private _loadRawfile() {
    if (!this.rawfilePath) {
      this.baseCallback("fail", 50011, "The rawfile resource file is incorrect.")
      return
    }
    if (!this.context) {
      this.baseCallback("fail", 50030, "The context is incorrect.")
      return
    }
    let r: WorkerResTextParam = { ctx: this.context, rawfilePath: this.rawfilePath }
    let handleTask: WorkerParam = {
      key: "readerRawfile",
      data: r,
      union: this.workerUnion
    }
    if (this.controller.getThreadRenderEnable()) {
      this.ensureWorkerRegistered()
      // 发送消息给Worker线程
      this.workerManager.postMessage(handleTask);
    } else {
      MainReader.reader(handleTask).then(res => {
        // 确保返回的结果包含正确的union
        if (res.union === this.workerUnion) {
          this.text = res.data as string
          this._parseMarkdown()
        }
      })
        .catch((err: BusinessError) => {

        })
    }
  }

  // 2
  private _loadSandbox() {
    if (!this.sandboxPath) {
      this.baseCallback("fail", 50021, "The sandbox file is incorrect.")
      return
    }
    let handleTask: WorkerStringResp = {
      key: "readerSandbox",
      data: this.sandboxPath,
      union: this.workerUnion
    }
    if (this.controller.getThreadRenderEnable()) {
      this.ensureWorkerRegistered()
      // 发送消息给Worker线程
      this.workerManager.postMessage(handleTask);
    } else {
      MainReader.reader(handleTask).then(res => {
        // 确保返回的结果包含正确的union
        if (res.union === this.workerUnion) {
          this.text = res.data as string
          this._parseMarkdown()
        }
      })
        .catch((err: BusinessError) => {

        })
    }
  }

  private doParseMarkdown() {
    Logger.info(TAG, "doParseMarkdown")
    this.parsingInProgress = true
    this.needsReparse = false
    this.registerPlugins()
    let handleTask: WorkerParseReq = {
      key: "parse",
      data: {
        text: this.text?.toString() ?? "",
        plugins: toPluginSyntaxManifestList(this.plugins)
      },
      union: this.workerUnion
    }
    if (this.controller.getThreadRenderEnable()) {
      this.ensureWorkerRegistered()
      this.workerManager.postMessage(handleTask);
    } else {
      MainReader.reader(handleTask).then(res => {
        if (res.union === this.workerUnion) {
          this.renderTreeNodeWithLatex(res.data as TreeNode[])
        }
      })
        .catch((err: BusinessError) => {

        })
    }
  }

  private _parseMarkdown() {
    if (this.streaming) {
      this.doParseMarkdown()
      return
    }
    this.doParseMarkdown()
  }

  private getTextIndex(localX: number, localY: number, layoutManager: LayoutManager, maxLength: number,
    cacheKey?: string): number {
    const lineCount = layoutManager.getLineCount()
    if (lineCount <= 0) {
      return 0
    }
    let lineNumber = -1
    for (let i = 0; i < lineCount; i++) {
      const lineMetrics = layoutManager.getLineMetrics(i)
      const top = this.getUIContext().px2vp(lineMetrics.topHeight)
      const bottom = this.getUIContext().px2vp(lineMetrics.topHeight + lineMetrics.height)
      if (localY >= top && localY <= bottom) {
        lineNumber = i
        break
      }
    }
    if (lineNumber < 0) {
      lineNumber = localY < 0 ? 0 : lineCount - 1
    }
    const lineMetrics = layoutManager.getLineMetrics(lineNumber)
    const lineStart = lineMetrics.startIndex
    const lineEnd = Math.min(lineMetrics.endIndex + 1, maxLength)
    if (lineEnd <= lineStart) {
      return lineStart
    }
    if (localX <= this.getUIContext().px2vp(lineMetrics.left)) {
      return lineStart
    }

    const lineRight = this.getUIContext().px2vp(lineMetrics.left + lineMetrics.width)
    if (localX >= lineRight) {
      return lineEnd
    }

    let low = lineStart
    let high = lineEnd - 1
    while (low <= high) {
      const mid = Math.floor((low + high) / 2)
      const rects = this.getRectsForRange(mid, Math.min(mid + 1, maxLength), layoutManager, cacheKey)
      if (rects.length == 0) {
        return mid
      }
      const rect = rects[0]
      const center = (rect.left + rect.right) / 2
      if (localX < center) {
        high = mid - 1
      } else {
        low = mid + 1
      }
    }

    return Math.max(lineStart, Math.min(low, lineEnd))
  }

  private getLayoutTextLength(layoutManager: LayoutManager): number {
    const lineCount = layoutManager.getLineCount()
    if (lineCount <= 0) {
      return 0
    }
    let maxLength = 0
    for (let i = 0; i < lineCount; i++) {
      const lineMetrics = layoutManager.getLineMetrics(i)
      maxLength = Math.max(maxLength, lineMetrics.endIndex + 1)
    }
    return maxLength
  }

  private getRectsForRange(start: number, end: number, layoutManager: LayoutManager,
    cacheKey?: string): common2D.Rect[] {
    const rangeStart = Math.max(0, start)
    const rangeEnd = Math.max(rangeStart, end)
    if (!cacheKey) {
      return this.loadRectsForRange(rangeStart, rangeEnd, layoutManager)
    }
    const blockCache = this.rectRangeCache.get(cacheKey)
    const rangeCacheKey = `${rangeStart}:${rangeEnd}`
    if (blockCache?.has(rangeCacheKey)) {
      return blockCache.get(rangeCacheKey) || []
    }
    const rects = this.loadRectsForRange(rangeStart, rangeEnd, layoutManager)
    if (blockCache) {
      blockCache.set(rangeCacheKey, rects)
    } else {
      const nextBlockCache: Map<string, common2D.Rect[]> = new Map()
      nextBlockCache.set(rangeCacheKey, rects)
      this.rectRangeCache.set(cacheKey, nextBlockCache)
    }
    return rects
  }

  private loadRectsForRange(start: number, end: number, layoutManager: LayoutManager): common2D.Rect[] {
    return layoutManager.getRectsForRange({ start, end }, text.RectWidthStyle.TIGHT,
      text.RectHeightStyle.TIGHT).map((item): common2D.Rect => {
      return {
        left: this.getUIContext().px2vp(item.rect.left),
        right: this.getUIContext().px2vp(item.rect.right),
        top: this.getUIContext().px2vp(item.rect.top),
        bottom: this.getUIContext().px2vp(item.rect.bottom)
      }
    })
  }

  private getCaretInfo(globalX: number, globalY: number, info: CaretInfo) {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const hit = registry.getBlockInfoByPoint(globalX, globalY)
    if (!hit) {
      return false
    }
    const localX = globalX - this.getUIContext().px2vp(hit.info.screenOffset.x)
    const localY = globalY - this.getUIContext().px2vp(hit.info.screenOffset.y)
    const layoutManager = hit.block.controller.getLayoutManager()
    const layoutLength = this.getLayoutTextLength(layoutManager)
    const caretIndex = this.getTextIndex(localX, localY, layoutManager, layoutLength, hit.block.id)
    info.blockOrder = hit.block.order
    info.caretIndex = Math.max(0, Math.min(caretIndex, layoutLength))
    return true
  }

  private buildSelectedTextInfo(order: number, start: CaretInfo, end: CaretInfo,
    registry: TextSelectionController): SelectedTextInfo | undefined {
    const block: RegisteredTextBlock | undefined = registry.getBlockByOrder(order)
    if (!block) {
      return undefined
    }
    try {
      const blockInfo = registry.getBlockRect(block.id)
      if (!blockInfo) {
        return undefined
      }
      const layoutManager = block.controller.getLayoutManager()
      const layoutLength = this.getLayoutTextLength(layoutManager)
      const startIndex = order == start.blockOrder ? start.caretIndex : 0
      const endIndex = order == end.blockOrder ? end.caretIndex : layoutLength
      const rangeStart = Math.max(0, Math.min(startIndex, layoutLength))
      const rangeEnd = Math.max(rangeStart, Math.min(endIndex, layoutLength))
      const rects = this.getRectsForRange(rangeStart, rangeEnd, layoutManager, block.id)
      return new SelectedTextInfo(block, blockInfo, rects, rangeStart, rangeEnd)
    } catch (_err) {
      return undefined
    }
  }

  private rebuildSelectedTextInfos(start: CaretInfo, end: CaretInfo, registry: TextSelectionController) {
    const nextInfos: SelectedTextInfo[] = []
    for (let i = start.blockOrder; i <= end.blockOrder; i++) {
      const info = this.buildSelectedTextInfo(i, start, end, registry)
      if (info) {
        nextInfos.push(info)
      }
    }
    this.selectedTextInfos = nextInfos
    if (nextInfos.length == end.blockOrder - start.blockOrder + 1) {
      this.selectedRangeStartOrder = start.blockOrder
      this.selectedRangeEndOrder = end.blockOrder
    } else {
      this.selectedRangeStartOrder = -1
      this.selectedRangeEndOrder = -1
    }
  }

  private updateSelectedTextInfoAtOrder(order: number, info: SelectedTextInfo | undefined) {
    if (!info) {
      return
    }
    const index = order - this.selectedRangeStartOrder
    if (index < 0 || index >= this.selectedTextInfos.length) {
      return
    }
    this.selectedTextInfos[index] = info
  }

  private refreshSelectedTextInfosComponentInfo(registry: TextSelectionController) {
    for (let i = 0; i < this.selectedTextInfos.length; i++) {
      const blockInfo = registry.getBlockRect(this.selectedTextInfos[i].block.id, true)
      if (blockInfo) {
        this.selectedTextInfos[i].componentInfo = blockInfo
      }
    }
  }

  private hasSelectionGeometryChanged(rootInfo: componentUtils.ComponentInfo,
    registry: TextSelectionController): boolean {
    if (this.lastSelectionRootScreenX != rootInfo.screenOffset.x ||
      this.lastSelectionRootScreenY != rootInfo.screenOffset.y) {
      return true
    }
    for (let i = 0; i < this.selectedTextInfos.length; i++) {
      const currentInfo = registry.getBlockRect(this.selectedTextInfos[i].block.id, true)
      const cachedInfo = this.selectedTextInfos[i].componentInfo
      if (!currentInfo) {
        continue
      }
      if (currentInfo.screenOffset.x != cachedInfo.screenOffset.x ||
        currentInfo.screenOffset.y != cachedInfo.screenOffset.y ||
        currentInfo.size.width != cachedInfo.size.width || currentInfo.size.height != cachedInfo.size.height) {
        return true
      }
    }
    return false
  }

  private startSelectionVisualSync() {
    if (this.selectionVisualSyncTimer > 0) {
      return
    }
    this.selectionVisualSyncTimer = setInterval(() => {
      if (!this.selectionActive || this.selectedTextInfos.length == 0) {
        this.stopSelectionVisualSync()
        return
      }
      try {
        const rootInfo = componentUtils.getRectangleById(this.selectionRootId)
        const registry = TextSelectionController.getInstance(this.selectionUnion)
        if (this.hasSelectionGeometryChanged(rootInfo, registry)) {
          this.refreshSelectionVisuals(rootInfo, registry)
        }
      } catch (_err) {
      }
    }, this.selectionVisualSyncInterval)
  }

  private stopSelectionVisualSync() {
    if (this.selectionVisualSyncTimer > 0) {
      clearInterval(this.selectionVisualSyncTimer)
      this.selectionVisualSyncTimer = 0
    }
  }

  private collectSelectedTextInfos(start: CaretInfo, end: CaretInfo) {
    const rootInfo = componentUtils.getRectangleById(this.selectionRootId)
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const expectedCount = end.blockOrder - start.blockOrder + 1
    const canIncrementallyUpdate = this.selectedTextInfos.length > 0 &&
      this.selectedRangeStartOrder >= 0 &&
      this.selectedRangeEndOrder >= this.selectedRangeStartOrder &&
      this.selectedTextInfos.length == this.selectedRangeEndOrder - this.selectedRangeStartOrder + 1
    if (!canIncrementallyUpdate) {
      this.rebuildSelectedTextInfos(start, end, registry)
    } else {
      const oldStartOrder = this.selectedRangeStartOrder
      const oldEndOrder = this.selectedRangeEndOrder
      const overlapStart = Math.max(oldStartOrder, start.blockOrder)
      const overlapEnd = Math.min(oldEndOrder, end.blockOrder)
      if (overlapStart > overlapEnd) {
        this.rebuildSelectedTextInfos(start, end, registry)
      } else {
        if (oldStartOrder < overlapStart) {
          this.selectedTextInfos.splice(0, overlapStart - oldStartOrder)
        }
        if (oldEndOrder > overlapEnd) {
          const removeCount = oldEndOrder - overlapEnd
          this.selectedTextInfos.splice(this.selectedTextInfos.length - removeCount, removeCount)
        }
        for (let i = overlapStart - 1; i >= start.blockOrder; i--) {
          const info = this.buildSelectedTextInfo(i, start, end, registry)
          if (info) {
            this.selectedTextInfos.unshift(info)
          }
        }
        for (let i = overlapEnd + 1; i <= end.blockOrder; i++) {
          const info = this.buildSelectedTextInfo(i, start, end, registry)
          if (info) {
            this.selectedTextInfos.push(info)
          }
        }
        if (this.selectedTextInfos.length != expectedCount) {
          this.rebuildSelectedTextInfos(start, end, registry)
        } else {
          this.selectedRangeStartOrder = start.blockOrder
          this.selectedRangeEndOrder = end.blockOrder
          const touchedOrders: number[] = [oldStartOrder, oldEndOrder, start.blockOrder, end.blockOrder]
          const updatedOrders: Set<number> = new Set()
          for (let i = 0; i < touchedOrders.length; i++) {
            const order = touchedOrders[i]
            if (order < start.blockOrder || order > end.blockOrder || updatedOrders.has(order)) {
              continue
            }
            updatedOrders.add(order)
            this.updateSelectedTextInfoAtOrder(order, this.buildSelectedTextInfo(order, start, end, registry))
          }
        }
      }
    }
    this.refreshSelectedTextInfosComponentInfo(registry)
    if (this.selectedTextInfos.length == 0) {
      this.startCaretX = -100
      this.startCaretY = -100
      this.endCaretX = -100
      this.endCaretY = -100
      return
    }
    this.updateCaretPositions(rootInfo)
    this.paintSelection(rootInfo)
    this.startSelectionVisualSync()
  }

  private updateCaretPositions(rootInfo: componentUtils.ComponentInfo) {
    if (this.selectedTextInfos.length == 0) {
      this.startCaretX = -100
      this.startCaretY = -100
      this.endCaretX = -100
      this.endCaretY = -100
      return
    }
    const startPosition = this.selectedTextInfos[0].getCaretPosition(rootInfo, false)
    const endPosition = this.selectedTextInfos[this.selectedTextInfos.length - 1].getCaretPosition(rootInfo, true)
    this.startCaretX = typeof startPosition?.x === 'number' ? startPosition.x + 2 : -100
    this.startCaretY = typeof startPosition?.y === 'number' ? startPosition.y : -100
    this.endCaretX = typeof endPosition?.x === 'number' ? endPosition.x + 2 : -100
    this.endCaretY = typeof endPosition?.y === 'number' ? endPosition.y : -100
  }

  private updateSelectionByOrderedCaret(infoA: CaretInfo, infoB: CaretInfo) {
    if (infoA.lessThan(infoB)) {
      this.collectSelectedTextInfos(infoA, infoB)
    } else {
      this.collectSelectedTextInfos(infoB, infoA)
    }
    this.selectionActive = true
  }

  private paintSelection(rootInfo?: componentUtils.ComponentInfo) {
    const rootRect = rootInfo || componentUtils.getRectangleById(this.selectionRootId)
    this.lastSelectionRootScreenX = rootRect.screenOffset.x
    this.lastSelectionRootScreenY = rootRect.screenOffset.y
    this.selectionContext.reset()
    this.selectionContext.fillStyle = '#4C0A59F7'
    for (let i = 0; i < this.selectedTextInfos.length; i++) {
      const info = this.selectedTextInfos[i]
      for (let j = 0; j < info.rects.length; j++) {
        const rect = info.rects[j]
        const x = this.getUIContext().px2vp(info.componentInfo.screenOffset.x) - this.getUIContext().px2vp(rootRect.screenOffset.x) + rect.left
        const y = this.getUIContext().px2vp(info.componentInfo.screenOffset.y) - this.getUIContext().px2vp(rootRect.screenOffset.y) + rect.top
        this.selectionContext.fillRect(x, y, rect.right - rect.left, rect.bottom - rect.top)
      }
    }
  }

  private startSelection(selectionInfo: BlockSelectionStartInfo) {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    if (registry.getOrderedBlocks().length == 0) {
      return
    }
    const block = registry.getBlockById(selectionInfo.blockId)
    const blockRect = registry.getBlockRect(selectionInfo.blockId)
    if (!block || !blockRect) {
      this.clearSelection()
      return
    }
    const localX = selectionInfo.localX
    const localY = selectionInfo.localY
    const layoutManager = block.controller.getLayoutManager()
    const layoutLength = this.getLayoutTextLength(layoutManager)
    this.rectRangeCache.clear()
    const caretIndex = this.getTextIndex(localX, localY, layoutManager, layoutLength, block.id)
    this.startCaretInfo.blockOrder = block.order
    this.startCaretInfo.caretIndex = Math.max(0, Math.min(caretIndex, layoutLength))
    this.endCaretInfo.blockOrder = this.startCaretInfo.blockOrder
    if (layoutLength == 0) {
      this.clearSelection()
      return
    }
    this.endCaretInfo.caretIndex = Math.min(this.startCaretInfo.caretIndex + this.initialSelectionLength, layoutLength)
    if (this.endCaretInfo.caretIndex - this.startCaretInfo.caretIndex < this.initialSelectionLength) {
      this.startCaretInfo.caretIndex = Math.max(0, this.endCaretInfo.caretIndex - this.initialSelectionLength)
    }
    this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    this.showSelectionActionBar()
  }

  private updateCaretByGesture(globalX: number, globalY: number, isStart: boolean) {
    const now = Date.now()
    if (this.lastSelectionUpdateTime > 0 && now - this.lastSelectionUpdateTime < this.selectionUpdateInterval) {
      return
    }
    const target = isStart ? this.startCaretInfo : this.endCaretInfo
    const oldBlockOrder = target.blockOrder
    const oldCaretIndex = target.caretIndex
    const hit = this.getCaretInfo(globalX, globalY, target)
    if (!hit) {
      return
    }
    if (oldBlockOrder == target.blockOrder && oldCaretIndex == target.caretIndex) {
      this.refreshSelectionVisuals()
      this.lastSelectionUpdateTime = now
      return
    }
    this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    this.lastSelectionUpdateTime = now
  }

  private triggerTextSelectionCopy() {
    if (!this.selectionActive) {
      return
    }
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    let textValue = ''
    if (this.startCaretInfo.lessThan(this.endCaretInfo)) {
      textValue = registry.buildCopyText(this.startCaretInfo.blockOrder, this.startCaretInfo.caretIndex,
        this.endCaretInfo.blockOrder, this.endCaretInfo.caretIndex)
    } else {
      textValue = registry.buildCopyText(this.endCaretInfo.blockOrder, this.endCaretInfo.caretIndex,
        this.startCaretInfo.blockOrder, this.startCaretInfo.caretIndex)
    }
    if (!textValue) {
      return
    }
    try {
      this.controller.getTextSelectionCopyListener()(textValue)
    } finally {
      this.clearSelection()
    }
  }

  private triggerTextSelectionSelectAll() {
    const registry = TextSelectionController.getInstance(this.selectionUnion)
    const blocks = registry.getOrderedBlocks()
    if (blocks.length == 0) {
      return
    }
    let firstBlock: RegisteredTextBlock | undefined = undefined
    let lastBlock: RegisteredTextBlock | undefined = undefined
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].renderedLength > 0) {
        firstBlock = blocks[i]
        break
      }
    }
    for (let i = blocks.length - 1; i >= 0; i--) {
      if (blocks[i].renderedLength > 0) {
        lastBlock = blocks[i]
        break
      }
    }
    if (!firstBlock || !lastBlock) {
      return
    }
    this.rectRangeCache.clear()
    this.startCaretInfo.blockOrder = firstBlock.order
    this.startCaretInfo.caretIndex = 0
    this.endCaretInfo.blockOrder = lastBlock.order
    this.endCaretInfo.caretIndex = lastBlock.renderedLength
    this.updateSelectionByOrderedCaret(this.startCaretInfo, this.endCaretInfo)
    this.showSelectionActionBar()
  }

  private showSelectionActionBar() {
    if (!this.selectionActive || this.selectedTextInfos.length == 0) {
      return
    }
    this.selectionActionBarVisible = true
  }

  private hideSelectionActionBar() {
    if (this.selectionActionBarVisible) {
      this.selectionActionBarVisible = false
    }
  }

  private getSelectionBounds(rootInfo: componentUtils.ComponentInfo): common2D.Rect | undefined {
    let left = Number.MAX_VALUE
    let top = Number.MAX_VALUE
    let right = Number.MIN_VALUE
    let bottom = Number.MIN_VALUE
    let hasRect = false
    for (let i = 0; i < this.selectedTextInfos.length; i++) {
      const info = this.selectedTextInfos[i]
      const blockOffsetX = this.getUIContext().px2vp(info.componentInfo.screenOffset.x) - this.getUIContext().px2vp(rootInfo.screenOffset.x)
      const blockOffsetY = this.getUIContext().px2vp(info.componentInfo.screenOffset.y) - this.getUIContext().px2vp(rootInfo.screenOffset.y)
      for (let j = 0; j < info.rects.length; j++) {
        const rect = info.rects[j]
        left = Math.min(left, blockOffsetX + rect.left)
        top = Math.min(top, blockOffsetY + rect.top)
        right = Math.max(right, blockOffsetX + rect.right)
        bottom = Math.max(bottom, blockOffsetY + rect.bottom)
        hasRect = true
      }
    }
    if (!hasRect) {
      return undefined
    }
    return {
      left,
      top,
      right,
      bottom
    }
  }

  private getSelectionActionBarPosition(): Position {
    const rootInfo = componentUtils.getRectangleById(this.selectionRootId)
    const selectionBounds = this.getSelectionBounds(rootInfo)
    const anchorX = this.endCaretX + 10
    const minX = this.selectionActionBarEdgeInset
    const maxX =
      Math.max(minX, this.selectionLayerWidth - this.selectionActionBarWidth - this.selectionActionBarEdgeInset)
    const x = Math.max(minX, Math.min(anchorX - this.selectionActionBarWidth / 2, maxX))
    let y = Math.max(this.selectionActionBarEdgeInset,
      this.endCaretY - this.selectionActionBarHeight - this.selectionActionBarSpacing)
    if (selectionBounds) {
      const aboveY = selectionBounds.top - this.selectionActionBarHeight - this.selectionActionBarSpacing
      const belowY = selectionBounds.bottom + this.selectionActionBarSpacing
      const maxY = Math.max(this.selectionActionBarEdgeInset,
        this.selectionLayerHeight - this.selectionActionBarHeight - this.selectionActionBarEdgeInset)
      if (aboveY >= this.selectionActionBarEdgeInset) {
        y = aboveY
      } else if (belowY <= maxY) {
        y = belowY
      } else {
        const spaceAbove = Math.max(0, selectionBounds.top - this.selectionActionBarEdgeInset)
        const spaceBelow = Math.max(0,
          this.selectionLayerHeight - this.selectionActionBarEdgeInset - selectionBounds.bottom)
        y = spaceAbove >= spaceBelow ? this.selectionActionBarEdgeInset : maxY
      }
    }
    return { x, y }
  }

  private refreshSelectionVisuals(rootInfo?: componentUtils.ComponentInfo, registry?: TextSelectionController) {
    if (!this.selectionActive || this.selectedTextInfos.length == 0) {
      return
    }
    const currentRootInfo = rootInfo || componentUtils.getRectangleById(this.selectionRootId)
    const currentRegistry = registry || TextSelectionController.getInstance(this.selectionUnion)
    this.refreshSelectedTextInfosComponentInfo(currentRegistry)
    this.updateCaretPositions(currentRootInfo)
    this.paintSelection(currentRootInfo)
  }

  private updateSelectionLayerSize(newValue: Area) {
    const nextWidth = Math.max(0, Math.ceil(newValue.width as number))
    const nextHeight = Math.max(0, Math.ceil(newValue.height as number))
    let changed = false
    if (this.selectionLayerWidth != nextWidth) {
      this.selectionLayerWidth = nextWidth
      changed = true
    }
    if (this.selectionLayerHeight != nextHeight) {
      this.selectionLayerHeight = nextHeight
      changed = true
    }
    if (changed && this.selectionActive) {
      this.refreshSelectionVisuals()
    }
  }

  @Builder
  private selectionActionItem(title: string, click: () => void) {
    Button(title)
      .width(60)
      .height(34)
      .fontSize(14)
      .fontColor('#111827')
      .backgroundColor('#FFF')
      .borderRadius(18)
      .onClick(() => {
        click()
      })
  }

  @Builder
  private selectionActionBar() {
    Row() {
      this.selectionActionItem('复制', () => {
        this.triggerTextSelectionCopy()
      })
      this.selectionActionItem('全选', () => {
        this.triggerTextSelectionSelectAll()
      })
      this.selectionActionItem('取消', () => {
        this.clearSelection()
      })
    }
    .padding(4)
    // .width(this.selectionActionBarWidth)
    .height(this.selectionActionBarHeight)
    .borderRadius(26)
    .backgroundColor('#FFFFFF')
    .shadow({
      radius: 28,
      color: '#20000000',
      offsetX: 0,
      offsetY: 10
    })
    .position(this.getSelectionActionBarPosition())
    .zIndex(30)
  }

  build() {
    if (this.treeNode.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        IntactRender({ children: this.treeNode })
          .width('100%')
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.updateSelectionLayerSize(newValue)
          })

        if (this.controller.getTextSelectionEnable()) {
          Canvas(this.selectionContext)
            .width(this.selectionLayerWidth)
            .height(this.selectionLayerHeight)
            .enabled(false)
            .position({ x: 0, y: 0 })
        }

        if (this.controller.getTextSelectionEnable() && this.selectionActive) {
          Column()
            .width(this.selectionLayerWidth)
            .height(this.selectionLayerHeight)
            .backgroundColor(Color.Transparent)
            .zIndex(10)
            .position({ x: 0, y: 0 })
            .onClick(() => {
              this.clearSelection()
            })

          SelectionCaret({
            caretX: this.startCaretX,
            caretY: this.startCaretY,
            isStart: true,
            caretDragStart: () => {
              this.hideSelectionActionBar()
              this.refreshSelectionVisuals()
            },
            caretDragUpdate: (globalX: number, globalY: number, isStart: boolean) => {
              this.updateCaretByGesture(globalX, globalY, isStart)
            },
            caretDragEnd: () => {
              this.refreshSelectionVisuals()
              this.showSelectionActionBar()
            }
          })
          SelectionCaret({
            caretX: this.endCaretX,
            caretY: this.endCaretY,
            isStart: false,
            caretDragStart: () => {
              this.hideSelectionActionBar()
              this.refreshSelectionVisuals()
            },
            caretDragUpdate: (globalX: number, globalY: number, isStart: boolean) => {
              this.updateCaretByGesture(globalX, globalY, isStart)
            },
            caretDragEnd: () => {
              this.refreshSelectionVisuals()
              this.showSelectionActionBar()
            }
          })
          if (this.selectionActionBarVisible) {
            this.selectionActionBar()
          }
        }
      }
      .id(this.selectionRootId)
      .width('100%')
      .onAppear(() => {
        this.baseCallback("success")
      })
    } else if (this.streaming && this.text) {
      Column() {
        Text(this.text)
          .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(HorizontalAlign.Start)
    }
  }
}

@Component
struct SelectionCaret {
  @Prop caretX: number = -100
  @Prop caretY: number = -100
  @Prop isStart: boolean = true
  caretDragStart: () => void = () => {
  }
  caretDragUpdate: (globalX: number, globalY: number, isStart: boolean) => void =
    (_globalX: number, _globalY: number, _isStart: boolean) => {
    }
  caretDragEnd: () => void = () => {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Column()
          .width(1)
          .height(20)
          .backgroundColor('#0A59F7')
        Column()
          .width(16)
          .aspectRatio(1)
          .borderRadius(10)
          .backgroundColor('#FFF')
          .border({ width: 2, color: "#0A59F7" })
      }
      .offset({ x: 12, y: 12 })
    }
    .width(44)
    .height(44)
    .position({ x: this.caretX - 12, y: this.caretY - 12 })
    .zIndex(20)
    .gesture(
      PanGesture({ distance: 1 })
        .onActionStart(() => {
          this.caretDragStart()
        })
        .onActionUpdate((event: GestureEvent) => {
          const finger = event.fingerList[event.fingerList.length - 1]
          this.caretDragUpdate(finger.globalX, finger.globalY, this.isStart)
        })
        .onActionEnd(() => {
          this.caretDragEnd()
        })
    )
  }
}
