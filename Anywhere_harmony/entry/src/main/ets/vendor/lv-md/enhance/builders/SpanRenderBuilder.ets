import { TextImpl } from '../impl/TextImpl'
import { LatexNode, PluginNode, TextNode, TreeNode } from '../model/TreeNode'
import {
  getCachedLatexImage,
  getLatexText,
  LatexBlockSpanBuilder,
  LatexInlineSpanBuilder,
  LatexTextFallbackSpanBuilder
} from './LatexBuilder'
import { hasPluginInlineOverlay, PluginInlinePlaceholderSpan } from '../components/PluginRenderHost'

/**
 * ParagraphRender need use
 * @param data
 */
@Builder
export function SpanRenderBuilder(markdownUnion: string, pluginUnion: string, data: ESObject, ctx: UIContext,
  _refreshKey?: number) {
  if (data?.type == "text" || data?.type == "inlineCode" || data?.type == "footnoteRef" ||
    data?.type == "inlineHtmlFont") {
    BaseSpanRenderBuilder(markdownUnion, data)
  } else if (data?.type == 'plugin') {
    if (hasPluginInlineOverlay(pluginUnion, data as PluginNode)) {
      PluginInlinePlaceholderSpan(pluginUnion, data as PluginNode)
    } else {
      BaseSpanRenderBuilder(markdownUnion, { text: (data as PluginNode).raw, type: 'text' })
    }
  } else if (data?.type == "latex") {
    if (!getCachedLatexImage(markdownUnion, getLatexText(data))) {
      LatexTextFallbackSpanBuilder(getLatexText(data))
    } else if ((data as LatexNode).block) {
      LatexBlockSpanBuilder(markdownUnion, getLatexText(data),
        getCachedLatexImage(markdownUnion, getLatexText(data))!, ctx)
    } else {
      LatexInlineSpanBuilder(markdownUnion, getLatexText(data),
        getCachedLatexImage(markdownUnion, getLatexText(data))!, ctx)
    }
  } else {
    ForEach(data?.children, (item: TreeNode) => {
      if (item.type == "text") {
        BaseSpanRenderBuilder(markdownUnion, {
          text: item.text,
          type: data?.type,
          url: data?.type == "link" ? data?.url : undefined
        }, data)
      } else if (item.type == 'plugin') {
        if (hasPluginInlineOverlay(pluginUnion, item as PluginNode)) {
          PluginInlinePlaceholderSpan(pluginUnion, item as PluginNode)
        } else {
          BaseSpanRenderBuilder(markdownUnion, { text: (item as PluginNode).raw, type: 'text' }, data)
        }
      } else {
        if (item?.type == "inlineCode") {
          BaseSpanRenderBuilder(markdownUnion, item, data)
        } else {
          // 被其他语法包裹的文本
          ForEach(item.children, (item2: TreeNode) => {
            if (item2.type == 'plugin') {
              if (hasPluginInlineOverlay(pluginUnion, item2 as PluginNode)) {
                PluginInlinePlaceholderSpan(pluginUnion, item2 as PluginNode)
              } else {
                BaseSpanRenderBuilder(markdownUnion, { text: (item2 as PluginNode).raw, type: 'text' }, data)
              }
            } else {
              BaseSpanRenderBuilder(markdownUnion, {
                text: (item2 as TextNode).text,
                type: item.type,
                url: item.type == "link" ? item.url : undefined
              }, data)
            }
          })
        }
      }
    })
  }
}

/**
 * 根文本渲染
 * @param data 节点数据
 * @param baseType 根节点类型
 */
@Builder
export function BaseSpanRenderBuilder(markdownUnion: string, data: ESObject, base?: TreeNode) {
  if (TextImpl.handleText(markdownUnion, data)) {
    Span(TextImpl.handleText(markdownUnion, data))
      .fontWeight(TextImpl.handleFontWeight(markdownUnion, data, base))
      .fontStyle(TextImpl.handleFontStyle(markdownUnion, data, base))
      .fontColor(TextImpl.handleFontColor(markdownUnion, data, base))
      .textBackgroundStyle({
        color: TextImpl.handleBackgroundColor(markdownUnion, data),
        radius: TextImpl.handleBackgroundRadius(markdownUnion, data)
      })
      .decoration(TextImpl.handleDecoration(markdownUnion, data))
      .lineHeight(TextImpl.handleLineHeight(markdownUnion, base))
      .fontSize(TextImpl.handleFontSize(markdownUnion, data, base))
      .fontFamily(TextImpl.handleFontFamily(markdownUnion, data, base))
      .onClick(() => {
        TextImpl.handleClick(markdownUnion, data)
      })
  }
}
