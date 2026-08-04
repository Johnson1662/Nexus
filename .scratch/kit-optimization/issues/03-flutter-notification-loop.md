# 03 — Flutter 侧 NotificationKit 闭环：后台检测 + 反向 MethodChannel + 自动取消

**What to build:** Flutter 侧完成通知审批闭环。`ChatProvider` 监听 App 生命周期，仅在后台时发送权限通知。`NotificationService` 注册反向 MethodChannel handler 接收 ArkTS 侧推来的审批结果，调用 `ChatProvider.respondPermission()`。回前台时自动取消残留通知。

**Blocked by:** 02-notification-fix（需要 ArkTS 侧 `onPermissionAction` MethodChannel 已就绪）

**Status:** ready-for-agent

- [ ] `ChatProvider` mixin `WidgetsBindingObserver`，维护 `_isInBackground` 标志
- [ ] `permission_request` 处理中，仅 `_isInBackground == true` 时调用 `NotificationService.showPermissionNotification()`
- [ ] `NotificationService` 注册 `setMethodCallHandler` 处理 `onPermissionAction` 方法，收到后调用回调通知 `ChatProvider`
- [ ] `ChatProvider` 在 `AppLifecycleState.resumed` 时调用 `NotificationService.cancel()` 清除残留通知
- [ ] `respondPermission()` 成功后也调用 `NotificationService.cancel()`
