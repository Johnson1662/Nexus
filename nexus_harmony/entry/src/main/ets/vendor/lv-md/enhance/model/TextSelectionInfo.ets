import { common2D } from '@kit.ArkGraphics2D'
import { componentUtils } from '@kit.ArkUI'

export class TextSelectionSegment {
  renderedLength: number = 0
  copyText: string = ""

  constructor(renderedLength: number, copyText: string) {
    this.renderedLength = renderedLength
    this.copyText = copyText
  }
}

export class RegisteredTextBlock {
  id: string
  order: number
  controller: TextController
  segments: TextSelectionSegment[]
  renderedLength: number

  constructor(id: string, order: number, controller: TextController, segments: TextSelectionSegment[]) {
    this.id = id
    this.order = order
    this.controller = controller
    this.segments = segments
    this.renderedLength = segments.reduce((sum: number, item: TextSelectionSegment) => sum + item.renderedLength, 0)
  }
}

export class SelectedTextInfo {
  block: RegisteredTextBlock
  componentInfo: componentUtils.ComponentInfo
  rects: common2D.Rect[]
  startIndex: number
  endIndex: number

  constructor(block: RegisteredTextBlock, componentInfo: componentUtils.ComponentInfo, rects: common2D.Rect[],
    startIndex: number, endIndex: number) {
    this.block = block
    this.componentInfo = componentInfo
    this.rects = rects
    this.startIndex = startIndex
    this.endIndex = endIndex
  }

  getCaretPosition(rootInfo: componentUtils.ComponentInfo, isEnd: boolean = true): Position | undefined {
    if (this.rects.length == 0) {
      return undefined
    }
    const rect = isEnd ? this.rects[this.rects.length - 1] : this.rects[0]
    const x = px2vp(this.componentInfo.screenOffset.x) - px2vp(rootInfo.screenOffset.x) +
      (isEnd ? rect.right : rect.left) - 10
    const y = px2vp(this.componentInfo.screenOffset.y) - px2vp(rootInfo.screenOffset.y) + rect.top
    return { x, y }
  }
}

export class BlockHitInfo {
  block: RegisteredTextBlock
  info: componentUtils.ComponentInfo

  constructor(block: RegisteredTextBlock, info: componentUtils.ComponentInfo) {
    this.block = block
    this.info = info
  }
}

export class BlockSelectionStartInfo {
  blockId: string
  localX: number
  localY: number

  constructor(blockId: string, localX: number, localY: number) {
    this.blockId = blockId
    this.localX = localX
    this.localY = localY
  }
}

export class CaretInfo {
  blockOrder: number = -1
  caretIndex: number = -1

  lessThan(another: CaretInfo): boolean {
    return !(this.blockOrder > another.blockOrder) &&
      (this.blockOrder < another.blockOrder || this.caretIndex < another.caretIndex)
  }

  reset() {
    this.blockOrder = -1
    this.caretIndex = -1
  }
}
