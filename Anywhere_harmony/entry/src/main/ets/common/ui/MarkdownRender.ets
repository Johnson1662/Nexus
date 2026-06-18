import { MDBaseController } from '../../vendor/lv-md/enhance/controller/BaseController';
import { MarkdownController } from '../../vendor/lv-md/enhance/controller/MarkdonwController';
import { MarkdownPluginRegistry } from '../../vendor/lv-md/enhance/controller/PluginRegistry';
import { IntactRender } from '../../vendor/lv-md/enhance/components/IntactRender';
import { TreeNode } from '../../vendor/lv-md/enhance/model/TreeNode';
import { MarkdownPlugin, toPluginSyntaxManifestList } from '../../vendor/lv-md/enhance/model/MarkdownPlugin';
import { parseMarkdown } from '../../vendor/lv-md/enhance/utils/ast';
import { generateRandomString } from '../../vendor/lv-md/enhance/utils/RandomString';
import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';

/**
 * Self-contained markdown renderer with streaming optimizations.
 *
 * Stage 1 — Adaptive debounce: plain text renders instantly (0ms),
 *   complex syntax (code blocks, tables, math) defers 16ms to batch.
 * Stage 2 — (see ChatPage for scroll anchoring)
 * Stage 3 — Code block placeholder: detects unclosed fencing during
 *   streaming and renders a visual placeholder to prevent layout jumps.
 * Stage 4 — Incremental memo: suppresses re-renders when the parsed
 *   tree is identical to the previous frame (deep-equality check).
 */
@Component
export struct MarkdownRender {
  @Prop @Watch('onTextChange') text: string = '';
  @Prop streaming: boolean = false;

  @Provide markdownUnion: string = '';
  @Provide pluginUnion: string = '';
  @Provide selectionUnion: string = '';
  @State treeNodes: TreeNode[] = [];
  @State private codeBlockPlaceholder: boolean = false;

  private controller: MarkdownController = new MarkdownController();
  private plugins: MarkdownPlugin[] = [];
  private parseTimeout: number = -1;
  private lastSnapshot: string = ''; // Stage 4 cache key

  aboutToAppear(): void {
    this.controller.setTextColor(Colors.foreground);
    this.controller.setTextSize(16);
    this.controller.setTextLineHeight(26);
    this.controller.setTitleColor(Colors.foreground);
    this.controller.setCodeBlockTheme('light');
    this.controller.setCodeBlockIdxState(false);
    this.controller.setCodeBlockBorderRadius(8);
    this.controller.setInlineCodeBackgroundColor('rgba(110, 118, 129, 0.2)');
    this.controller.setInlineCodeBackgroundRadius(4);
    this.controller.setTableBackgroundColor('transparent');
    this.controller.setTableInterleaveBackgroundColor('transparent');
    this.controller.setTableBorderRadius(8);
    this.controller.setQuoteBackgroundColor('transparent');
    this.controller.setQuoteBorderColor(Colors.accent);
    this.controller.setHyperlinkTextColor(Colors.accent);
    this.controller.setHyperlinkUnderlineState(false);
    this.controller.setThreadRenderEnable(false);
    this.controller.setBlockSpacing(16);

    this.markdownUnion = this.controller.getUnion();
    this.pluginUnion = generateRandomString();
    this.selectionUnion = generateRandomString();
    MDBaseController.setMarkdownController(this.controller);
    this.controller.setUIContext(this.getUIContext());
    MarkdownPluginRegistry.registerPlugins(this.pluginUnion, this.plugins);

    if (this.text.length > 0) {
      this.doParse(this.text);
    }
  }

  // Stage 1 — adaptive debounce
  onTextChange(): void {
    if (this.streaming) {
      clearTimeout(this.parseTimeout);
      if (this.containsComplexSyntax(this.text)) {
        // batch complex syntax within one frame
        this.parseTimeout = setTimeout(() => { this.doParse(this.text); }, 16);
      } else {
        // plain text renders instantly
        this.doParse(this.text);
      }
    } else {
      this.doParse(this.text);
    }
  }

  aboutToDisappear(): void {
    clearTimeout(this.parseTimeout);
    MarkdownPluginRegistry.destroy(this.pluginUnion);
    MDBaseController.destroyMarkdownUnion(this.markdownUnion);
  }

  /** Stage 1 — only debounce for syntax that causes layout-shift on partial parse. */
  private containsComplexSyntax(text: string): boolean {
    return text.includes('```') || (text.includes('|') && text.includes('-')) || text.includes('$$');
  }

  /** Stage 3 — detect unclosed fenced code block. */
  private hasUnclosedFence(text: string): boolean {
    let parts = text.split('```');
    // odd count = unclosed: ``` opens, but no matching close yet
    return parts.length > 1 && parts.length % 2 === 0;
  }

  private doParse(md: string): void {
    if (md.length === 0) {
      this.treeNodes = [];
      this.codeBlockPlaceholder = false;
      this.lastSnapshot = '';
      return;
    }

    this.codeBlockPlaceholder = this.streaming && this.hasUnclosedFence(md);

    const manifests = toPluginSyntaxManifestList(this.plugins);
    let newNodes = parseMarkdown(md, manifests) as TreeNode[];

    // Stage 4 — skip re-render when tree unchanged (deep compare via JSON snapshot)
    let snap = JSON.stringify(newNodes);
    if (this.streaming && snap === this.lastSnapshot) {
      return;
    }
    this.lastSnapshot = snap;
    this.treeNodes = newNodes;
  }

  build() {
    Column() {
      if (this.treeNodes.length > 0) {
        IntactRender({ children: this.treeNodes })
          .width('100%')
      }
      // Stage 3: visual placeholder for unclosed code block
      if (this.codeBlockPlaceholder) {
        Row() {
          LoadingProgress()
            .width(14).height(14).color(Colors.foregroundMuted)
            .margin({ right: Spacing.xs })
          Text('...')
            .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .padding({ left: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
        .backgroundColor(Colors.surface1)
        .borderRadius(Radius.sm)
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
  }
}
