# 02 — NotificationKit 修复：SlotType + ActionButton + WantAgent 回传

**What to build:** 修复 ArkTS 侧 `NotificationHelper.ets` 使通知能正常弹出横幅，并增加"允许"和"拒绝"两个 ActionButton。用户点击按钮后，通过 WantAgent 拉起 EntryAbility，`onNewWant` 解析参数并通过 MethodChannel 将审批结果推回 Flutter 侧。同时修改 `EntryAbility.ets` 添加 `onNewWant` 处理逻辑。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `SlotType` 改为 `SERVICE_INFORMATION`
- [ ] `NotificationRequest` 包含两个 `actionButtons`："允许"（绿色）和"拒绝"（红色），各自绑定不同 `WantAgent`
- [ ] `WantAgent` 的 `want.parameters` 携带 `{ nexus_action: 'permission_response', requestId, allow: true/false }`
- [ ] `EntryAbility.onNewWant(want)` 检查 `nexus_action`，通过 `NotificationHelper.channel.invokeMethod('onPermissionAction', ...)` 推给 Flutter
- [ ] `NotificationHelper` 保存当前 `requestId` 以便 WantAgent 引用
- [ ] hilog 中不再出现 `silent = 2` 或 `GetNotificationSlot failed`（针对我们的 app）
