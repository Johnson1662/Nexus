# Kit Integration & UI Enhancement Spec

## Problem Statement

Nexus 的 LiveViewKit 和 NotificationKit 集成链路（Dart → MethodChannel → ArkTS → 系统 Kit）已搭建完成，但实机测试两个 Kit 均无法正常工作：

- **LiveViewKit**：`liveViewManager.startLiveView()` 报 error 401 — `LAYOUT_TYPE_PROGRESS` 要求 `layoutData.nodeIcons` 字段，代码未传。
- **NotificationKit**：通知被系统静默（`silent = 2`）—— `SlotType.SOCIAL_COMMUNICATION` 不适合工具类应用，`addSlot` 失败。且通知无 ActionButton，用户无法在通知栏直接审批权限请求。

此外，权限审批面板展示的 toolCall 是原始 Map.toString() 字符串，可读性差；工具卡片的 diff 类型内容没有着色渲染。

## Solution

1. 修复 LiveViewKit：补全 `nodeIcons` 参数、分离 start/update API、递增 sequence。
2. 修复 NotificationKit：换 SlotType 为 `SERVICE_INFORMATION`、仅后台发通知、增加 ActionButton（允许/拒绝）、通过 WantAgent + onNewWant 回传审批结果到 Flutter。
3. 增强权限审批面板：结构化解析 toolCall、展示风险等级标签。
4. 工具卡片 Diff 着色：逐行解析 unified diff，增行绿底、删行红底、hunk header 灰底。

## User Stories

1. As a developer using Nexus, I want to see a live progress capsule on my lock screen when an AI Agent is executing tools, so that I can glance at progress without unlocking my phone.
2. As a developer, I want the live view capsule to show a progress percentage and current step description, so that I know what the Agent is doing.
3. As a developer, I want the live view to update in real-time as tool calls progress, so that I have continuous feedback.
4. As a developer, I want the live view to disappear when the Agent's turn ends, so that stale information doesn't linger.
5. As a developer, I want to receive a system notification when the Agent requests a dangerous permission while my phone is in the background, so that I don't miss critical approval requests.
6. As a developer, I want the notification to show "Allow" and "Deny" action buttons, so that I can approve or reject directly from the notification bar.
7. As a developer, I want tapping an action button on the notification to send my decision back to the Bridge Server without manually opening the app, so that the Agent can proceed quickly.
8. As a developer, I want the notification to be automatically dismissed when I open the app or after I respond, so that the notification bar stays clean.
9. As a developer, I do NOT want to receive duplicate notifications when I'm already looking at the app (foreground), so that I'm not annoyed by redundant alerts.
10. As a developer, I want the permission approval sheet to show a structured breakdown of the tool name, command, and arguments instead of raw Map.toString(), so that I can understand what I'm approving.
11. As a developer, I want to see a colored risk level chip (high=red, medium=orange, low=green) on the permission sheet, so that I can quickly assess the danger level.
12. As a developer, I want diff content in tool call cards to be syntax-colored (green for additions, red for deletions, gray for hunk headers), so that I can review code changes at a glance.

## Implementation Decisions

### LiveViewKit (ArkTS side: LiveViewHelper)
- Add `nodeIcons: [$r('app.media.app_icon')]` to `layoutData` in LiveView config.
- Maintain `private sequenceCounter: number = 0`, increment on every call.
- First call uses `liveViewManager.startLiveView()`, subsequent calls use `liveViewManager.updateLiveView()`. Track with `private isLiveViewActive: boolean = false`.
- `stopLiveView()` resets `isLiveViewActive = false` and `sequenceCounter = 0`.

### NotificationKit (ArkTS side: NotificationHelper)
- Change `SlotType` from `SOCIAL_COMMUNICATION` to `SERVICE_INFORMATION`.
- Add two `actionButtons` to `NotificationRequest`: "允许" and "拒绝", each with a `WantAgent` whose `want.parameters` carries `{ nexus_action: 'permission_response', requestId, allow: true/false }`.
- `EntryAbility.onNewWant(want)` reads `want.parameters`, if `nexus_action === 'permission_response'`, invokes MethodChannel `onPermissionAction` to push result to Flutter.
- Store `requestId` in NotificationHelper so the WantAgent can reference it.

### NotificationKit (Flutter side)
- `ChatProvider` adds `WidgetsBindingObserver` mixin, tracks `_isInBackground`.
- `permission_request` handler checks `_isInBackground` before calling `NotificationService.showPermissionNotification()`.
- `NotificationService` registers a reverse MethodChannel handler for `onPermissionAction`, which calls back to `ChatProvider.respondPermission()`.
- On `resumed` lifecycle, call `NotificationService.cancel()` to clear stale notifications.

### Permission Sheet Enhancement (Flutter side: permission_sheet.dart)
- Enhance `_displayCommand()` to parse toolCall into structured fields: toolName, command, arguments.
- Add a `_buildRiskChip()` widget that renders colored chip based on `_classifyRisk()`: high=red, medium=orange, low=green.
- Display structured card layout: risk chip → tool name → command → arguments list.

### Diff Rendering (Flutter side: tool_call_card.dart)
- When `toolContentType == 'diff'`, render with `_buildDiffView()` instead of plain Text.
- Split content by lines; prefix-based coloring: `+` → green background `Color(0x1A22C55E)`, `-` → red background `Color(0x1AEF4444)`, `@@` → gray background `Color(0x1A6B7280)`, else → transparent.
- Use monospace font (`fontFamily: 'monospace'`).
- Follows existing ToolCallCard fold/expand behavior.

## Testing Decisions

- No automated test framework is configured for the Flutter OHOS client. Verification is done via real-device deployment and hilog inspection.
- LiveViewKit: deploy, trigger KitTestPage "测试 LiveView" button, verify hilog shows no error 401 and lock screen displays progress capsule.
- NotificationKit: deploy, trigger "测试通知" button while app is in background, verify notification banner appears with action buttons.
- Permission Sheet: visual inspection of structured layout when a real permission_request arrives.
- Diff Rendering: visual inspection of colored diff in tool_call_card when a diff-type tool_call_update arrives.

## Out of Scope

- 编排者视图（多 Agent 状态卡片）— 下一轮。
- Push Kit 后台唤醒 — 下一轮。
- 全局搜索中心 — 下一轮。
- 会话管理增强（重命名/置顶/归档）— 下一轮。
- 近场发现与分布式流转 — 下一轮。

## Further Notes

- LiveViewKit error 401 的根因已通过 hilog 实机验证确认：`The type of layoutData.nodeIcons must be Array<string | image.PixelMap>`.
- NotificationKit `silent = 2` 的根因已通过 hilog 确认：`SetFlags- HandleFlag ... silent = 2` + 持续 `GetNotificationSlot failed`.
- MethodChannel 注册链路已验证正常：`LiveViewHelper registered OK` + `NotificationHelper registered OK`.
- 构建命令：`cd nexus_flutter/ohos && NODE_OPTIONS="" devecocli build --build-mode debug`
- 部署命令：`hdc file send ... /data/local/tmp/nexus.hap && hdc shell bm install -p /data/local/tmp/nexus.hap`
