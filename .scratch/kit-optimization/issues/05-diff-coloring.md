# 05 — 工具卡片 Diff 着色渲染

**What to build:** 在 `tool_call_card.dart` 中，当 `toolContentType == 'diff'` 时，用逐行着色替代纯文本显示：`+` 开头绿底、`-` 开头红底、`@@` 开头灰底，其余行无背景。使用等宽字体。沿用现有折叠/展开逻辑。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] 新增 `_buildDiffView(String content)` 方法，返回着色后的 Widget
- [ ] `+` 行背景 `Color(0x1A22C55E)`，`-` 行背景 `Color(0x1AEF4444)`，`@@` 行背景 `Color(0x1A6B7280)`
- [ ] 使用 monospace 字体（`fontFamily: 'monospace'`）
- [ ] 折叠/展开行为与现有 ToolCallCard 逻辑一致，无额外折叠控件
- [ ] diff 内容水平可滚动（长行不截断）
