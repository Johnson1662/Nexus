# 04 — 权限审批面板增强：结构化解析 + 风险等级标签

**What to build:** 增强 `permission_sheet.dart`，将原始 toolCall Map.toString() 字符串解析为结构化卡片（工具名、命令、参数），并在顶部显示风险等级 chip（高=红色、中=橙色、低=绿色）。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `_displayCommand()` 重构为返回结构化数据（toolName, command, arguments map），而非单一字符串
- [ ] 审批面板显示结构化布局：风险等级 chip → 工具名 → 命令内容 → 参数列表
- [ ] 风险等级 chip 使用 `_classifyRisk()` 的结果：high → 红底白字「高风险」、medium → 橙底白字「中风险」、low → 绿底白字「低风险」
- [ ] 长命令/长参数值在卡片内自动换行，不溢出
