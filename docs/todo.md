# TODO

## 通知与后台唤醒

### 背景

Anywhere 目前依赖手机端 WebSocket 与 Bridge / Relay 保持连接。App 不在前台、进程被挂起或被系统回收后，手机端无法继续通过 WebSocket 接收 `permission_request`、`turn_ended`、`error` 等事件，也就无法自行发布本地通知。

### 目标

接入 HarmonyOS Push Kit，让系统推送通道在 App 不运行时也能提醒用户。通知点击后拉起 Anywhere，App 再重连 Relay / Bridge，并通过 `sync_request` 补齐会话状态。

### 推荐链路

```text
Bridge / Relay 发现重要事件
        ↓
云端 Notifier 调用 Push Kit REST API
        ↓
HarmonyOS 系统推送服务下发通知
        ↓
用户点击通知打开 Anywhere
        ↓
App 根据通知 data 进入对应 host / workspace / session
        ↓
WSClient 重连并 sync_request 补齐消息和权限状态
```

### 需要通知的事件

- `permission_request`：Agent 等待用户审批工具调用。
- `turn_ended`：远程任务完成。
- `error`：Agent / Bridge / Relay 出错。
- 连接断开或重连失败超过阈值。
- Agent 长时间等待用户输入。

### 客户端任务

- 请求通知授权：`notificationManager.requestEnableNotification()`。
- 接入 Push Kit 获取 Push Token。
- 将 Push Token 绑定到当前用户 / 设备 / hostId，并上报给 Relay 或 Bridge。
- 支持通知点击参数，读取 `hostId`、`workspaceId`、`sessionId`、`requestId` 等 data。
- 点击通知后进入对应聊天页，触发自动重连和 `sync_request`。
- 前台时不要重复弹系统通知，可改为应用内提示。

### 服务端任务

- Relay 或 Bridge 保存 hostId / deviceId / Push Token 映射。
- Bridge 收到关键事件后生成通知 payload。
- Relay / 云端 Notifier 调用 Push Kit REST API 发送通知。
- `permission_request` 需要在 Bridge 端挂起等待，直到 App 回传 `permission_response`。
- 通知 payload 中不要包含敏感 diff / 命令全文，只放摘要和跳转所需 ID。

### 注意事项

- 不能依赖普通 WebSocket 在后台长期存活。
- Push Kit 通知消息适合用户可感知提醒；后台消息不展示通知，且可能延迟或只缓存最新一条，不适合紧急审批。
- 长时任务只能用于用户明确开启的“保持当前会话监控”模式，需要常驻通知和符合系统校验的业务类型，不能作为无感保活方案。
