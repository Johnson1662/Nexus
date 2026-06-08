# TODO

## 全局搜索

### 背景

首页底部已有 `Search chats` 入口，但当前更像占位入口。Anywhere 的核心信息分散在 host、workspace、session、message、tool call、plan 等多层结构中，用户在手机上很难快速找回某次任务、某条回答或某个工作区。

### 目标

做一个统一搜索中心，支持搜索会话、消息、工作区、路径、Agent 输出和工具调用摘要，让用户可以从首页快速回到目标上下文。

### 建议能力

- 搜索最近会话标题、消息正文和工作区名称 / 路径。
- 支持按 host、workspace、agent、时间范围过滤。
- 搜索结果点击后进入对应聊天页，并滚动到相关消息。
- 优先展示最近命中的会话，其次展示工作区和历史消息。
- 对本地缓存数据先做端侧搜索，后续再考虑 Bridge 端全文索引。

### 实现提示

- 先复用 `ChatStore.sessions`、`WorkspaceStore.workspaces` 和本地缓存消息做 MVP。
- 搜索结果项只展示必要摘要，保持首页极简风格。
- 后续可在 Bridge 端维护 SQLite / JSON 索引，支持跨设备和大量历史会话。

## 会话管理增强

### 背景

Anywhere 已经能列出和加载 session，但会话生命周期管理还偏基础。远程编程场景里，用户经常需要区分活跃任务、历史任务、重要任务和可以清理的任务。

### 目标

增强会话列表和详情页，让用户能在手机上管理远程 Agent 会话，而不是只能打开最近记录。

### 建议能力

- 会话重命名。
- 会话置顶 / 取消置顶。
- 会话归档 / 删除。
- 关闭远端 session，释放 Bridge / ACP 资源。
- 按 workspace、agent、model、状态过滤会话。
- 会话项展示当前模型、最后活跃时间、是否有未读事件或待审批请求。

### 实现提示

- 客户端先维护本地置顶 / 归档状态，避免立即扩展 ACP 协议。
- 关闭远端 session 可复用现有 `close_session` handler。
- 删除前区分“仅本地隐藏”和“远端关闭 / 清理”，避免误删有价值历史。

## 权限请求审阅增强

### 背景

当前已有 `PermissionSheet`，可以响应 Agent 的 `permission_request`。但远程审批工具调用时，用户需要知道它将执行什么、影响哪些文件、风险有多大，否则在手机上点 Allow 会缺少安全感。

### 目标

把权限弹窗升级成审阅面板，在批准前展示足够上下文，并支持更细粒度的授权选择。

### 建议能力

- 展示工具名、工具类型、目标路径、命令摘要或 diff 摘要。
- 对高风险操作给出明确提示，例如删除文件、执行 shell、修改大量文件。
- 支持 `Allow once`、`Reject once`、`Allow for workspace` 等策略。
- 支持从通知点击进入对应权限请求。
- 请求过期、重连或 session 结束时自动清理幽灵浮层。

### 实现提示

- Bridge 端通知 payload 不放敏感全文，只传 `requestId` 和摘要。
- App 打开后通过 `sync_request` 拉取当前待审批状态。
- 记住授权策略时要按 host + workspace + agent + tool scope 约束，避免全局放大权限。

## 工具调用审阅面板

### 背景

`ToolCallCard` 已支持工具调用、diff 和 terminal 内容类型，但在手机上审阅远程编程过程还可以更强：用户需要看懂 Agent 做了什么、命令是否成功、修改了哪些文件，以及是否需要介入。

### 目标

把工具调用详情做成可展开的审阅面板，让远程执行过程可追踪、可复制、可复盘。

### 建议能力

- terminal 输出使用等宽字体展示，并区分 stdout / stderr / exit code。
- diff 支持查看完整内容、复制路径、复制 diff 摘要。
- 工具调用失败时显示失败原因，并提供重试或复制错误信息。
- 长输出默认折叠，支持“查看全部”。
- 对文件读写、搜索、执行命令使用不同图标和摘要格式。

### 实现提示

- 优先增强 `ToolCallCard.ets`，不改变消息协议。
- LazyForEach key 继续包含工具内容长度和状态，确保流式更新能刷新 UI。
- 终端长输出需要截断策略，避免列表渲染卡顿。

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
