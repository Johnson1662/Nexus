# Remaining ACP Feature Implementation Plan

> 基于 `docs/acp-protocol.md` 完整文档对照，列出客户端尚未实现的 ACP 协议功能及其实现方案。
> 日期：2026-05-18

---

## 1. File System (fs/read_text_file & fs/write_text_file)

**ACP 协议位置**：Chapter 9
**需要能力声明**：`clientCapabilities.fs.readTextFile` / `clientCapabilities.fs.writeTextFile`

### 当前状态

**✅ 已实现。** Bridge 在 `initialize` 中声明了 `fs.readTextFile: true` 和 `fs.writeTextFile: true`，并且在 `server/src/handlers/start.mts` 和 `server/src/handlers/load-session.mts` 的 `AcpClient` 构造函数中已通过 `onReadTextFile` 和 `onWriteTextFile` 回调实现了完整的文件读写功能。

特点：
- 路径安全检查（`isPathWithinCwd` 限制在 cwd 范围内）
- `ReadTextFile` 支持 `line`（1-based）和 `limit` 参数
- `WriteTextFile` 自动创建父目录（`fs.mkdir({ recursive: true })`）
- 两个 Session 创建入口（`start` 和 `load_session`）都有相同实现

**App 端变化**：无需变化 — Agent 直接通过 ACP 调用 Bridge，Bridge 在本地执行文件操作。

### 实现方案

~~无需新增 — 已实现。~~

---

## 2. Terminal (terminal/create / output / wait_for_exit / kill / release)

**ACP 协议位置**：Chapter 10
**需要能力声明**：`clientCapabilities.terminal: true`

### 当前状态

**✅ Bridge 端已完全实现。** `server/src/handlers/start.mts` 和 `server/src/handlers/load-session.mts` 中的 `AcpClient` 回调已包含：
- `onCreateTerminal`：spawn 子进程，捕获 stdout/stderr，实现 `outputByteLimit` 截断
- `onTerminalOutput`：返回当前 output + truncated + exitStatus
- `onWaitForTerminalExit`：Promise 等待进程退出
- `onKillTerminal`：使用 `tree-kill` 终止进程
- `onReleaseTerminal`：终止并清理终端资源

**App 端未实现**：终端输出在 App 上无展示。Agent 发送的工具调用（`tool_call`）中如果包含 `content.type === "terminal"`，App 端未处理此内容类型。

### 实现方案

#### App 端 — 终端输出展示

在 `MessageCard.ets` 或 `ToolCallCard.ets` 中处理 `ToolCallContent.type === "terminal"` 的情况：
- 等宽字体展示终端输出
- 暗色背景终端风格
- 实时更新（通过 `tool_call_update` 刷新）

**工作量**：~80 行 App 端代码
**注意**：终端命令确实会执行，只是输出不在 App 上显示。

---

## 3. Permission Request (session/request_permission)

**ACP 协议位置**：Chapter 8.5
**需要能力声明**：无（Agent 端主动发起）

### 当前状态

**Bridge 端已实现转发**，`server/src/handlers/start.mts` 和 `server/src/handlers/load-session.mts` 中的 `onPermissionRequest` 回调会：
1. 生成 `requestId`
2. 通过 WS 发送 `permission_request` 消息给 App
3. 等待 App 的 `permission_response` 回复
4. 将结果返回给 Agent

**✅ App 端已完整实现**：
- `WSClient.ets`：`case 'permission_request'` 解析 `msg.toolCall` 和 `msg.options`，保存到 `ChatStore.pendingPermission`；提供 `sendPermissionResponse()` 方法。
- `ChatView.ets`：`PermissionSheet` 组件浮层展示，含 Allow once / Reject once 等选项按钮。
- 无需新增代码。

---

## 4. Rich Content Input (Image / Audio / Resource / Resource Link)

**ACP 协议位置**：Chapter 7.2-7.5
**需要能力声明**：`promptCapabilities.image` / `promptCapabilities.audio` / `promptCapabilities.embeddedContext`

### 当前状态

App 仅支持纯文本输入（`{ type: "text", text: "..." }`）。图片和音频按钮有 placeholder UI 但无功能。

### 实现方案

#### App 端 — 图片输入

1. **ChatInputBar 新增图片选择按钮**
   - 点击后调用系统图片选择器（`PhotoAccessHelper`）
   - 选中图片后读取为 base64
   - 构建 `{ type: "image", mimeType: "...", data: "..." }` 内容块
   - 存入 `pendingImages` 数组
   - 发送 prompt 时与文本组合：`prompt: [{ type: "text", text: "..." }, { type: "image", ... }]`

2. **ChatPage / sendMessage 修改**
   - 发送时检查是否有 pending 的多媒体内容
   - 构建 `ContentBlock[]` 数组而非纯文本

#### App 端 — 音频输入

1. **录音按钮**
   - 调用 `AudioCapturer` API 录制音频
   - 转 base64
   - 构建 `{ type: "audio", mimeType: "audio/wav", data: "..." }` 内容块

#### Bridge 端

- 无变化 — Bridge 已将 prompt 内容块原样转发给 ACP

**工作量**：图片输入 ~200 行，音频输入 ~250 行
**注意**：需要 `promptCapabilities.image` 和 `promptCapabilities.audio` 在 `initialize` 响应中为 `true` 才生效（取决于 Agent）

---

## 5. Session Info Update (session_info_update)

**ACP 协议位置**：Chapter 5.3
**通知类型**：`sessionUpdate: "session_info_update"`

### 当前状态

**App 端已实现基础处理**（`OnboardingView.ets` line 119），更新 `ChatStore.sessionTitle` 和 `ChatStore.sessions[i].title`。

### 实现方案

~~已实现 — 2026-05-18 补充了 sessions 列表中的 title 同步更新。~~

---

## 6. Feature-Level auth (authenticate)

**ACP 协议位置**：Chapter 3.4

### 当前状态

Bridge 的 `initialize` 处理中已支持解析 `authMethods`，但 **如果 Agent 要求认证则没有后续处理**。目前已知的所有常用 Agent（Claude Code、Codex CLI 等）均不要求 OAuth，此功能优先級最低。

### 实现方案（低优先級）

Bridge 端：如果 `initialize` 响应中包含 `authMethods`，自动调用 `authenticate` 方法。对于 OAuth flow（如 `bearer_token`），需要弹出浏览器或展示 URL。

**工作量**：~100 行
**优先級**：P4 — 等有实际需要的 Agent 再实现

---

## 实现优先級排序

| 优先級 | 功能 | 状态 |
|--------|------|------|
| ✅ | File System (`fs/read*, fs/write*`) | Bridge 端已完成（start.mts / load-session.mts） |
| ✅ | Terminal (`terminal/*`) | Bridge 端已完成（start.mts / load-session.mts） |
| ✅ | Session Info Update | App 端已完成（OnboardingView.ets） |
|| ✅ | Permission Request | Bridge 转发 + App PermissionSheet 已完整实现 |
| **P2** | Terminal 输出 App 端展示 | ToolCall terminal 内容类型未处理 |
| **P3** | Image / Audio Input | 取决于 Agent 能力声明 |
| **P4** | Auth (authenticate) | 尚无 Agent 需要 |

---

## 实施顺序建议

1. ✅ **Phase 1 (P1)**：Permission Request — 已完整实现
2. **Phase 2 (P2)**：Terminal 输出 App 端展示 — ToolCall terminal 内容类型未处理
3. **Phase 3 (P3 + P4)**：富媒体输入 + Auth — 低频需求
