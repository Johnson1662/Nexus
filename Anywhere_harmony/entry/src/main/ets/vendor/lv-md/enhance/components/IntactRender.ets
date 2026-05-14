import { IntactImpl } from '../impl/IntactImpl'
import { PluginNode, TreeNode } from '../model/TreeNode'
import { Logger } from '../utils/Logger'
import { BlockquoteRender } from './BlockquoteRender'
import { CodeRender } from './CodeRender'
import { FootnotesRender } from './FootnotesRender'
import { LineRender } from './LineRender'
import { OlRender } from './OlRender'
import { ParagraphRender } from './ParagraphRender'
import { getPluginRenderer, PluginBlockRenderHost } from './PluginRenderHost'
import { TableRender } from './TableRender'
import { TextRender } from './TextRender'
import { UlRender } from './UlRender'

const TAG = "IntactRender"

@Component
export struct IntactRender {
  @Consume markdownUnion: string
  @Consume pluginUnion: string
  @Prop children: TreeNode[] = []

  aboutToAppear(): void {
    Logger.info(TAG, "IntactRender data > " + JSON.stringify(this.children))
  }

  build() {
    Column({ space: IntactImpl.handleBlockSpacing(this.markdownUnion) }) {
      ForEach(this.children, (item: TreeNode) => {
        if (item.type == "hr") {
          LineRender()
        }
        if (item.type == "paragraph") {
          ParagraphRender({ base: item })
        }
        if (item.type == "heading") {
          TextRender({ base: item })
        }
        if (item.type == "blockquote") {
          BlockquoteRender({ base: item })
        }
        if (item.type == "ul") {
          UlRender({ base: item })
        }
        if (item.type == "ol") {
          OlRender({ base: item })
        }
        if (item.type == "table") {
          TableRender({ base: item })
        }
        if (item.type == "codeBlock") {
          CodeRender({ base: item })
        }
        if (item.type == "plugin" && (item as PluginNode).display == 'block') {
          if (getPluginRenderer(this.pluginUnion, item as PluginNode)) {
            PluginBlockRenderHost({
              node: item as PluginNode,
              renderer: getPluginRenderer(this.pluginUnion, item as PluginNode)
            })
          } else {
            Text((item as PluginNode).raw)
          }
        }
        if (item.type == "footnotes") {
          FootnotesRender({ base: item })
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
  }
}
