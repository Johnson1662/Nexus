# Remaining ACP Feature Implementation Plan

> 基于 `docs/acp-protocol.md` 完整文档对照，列出客户端尚未实现的 ACP 协议功能及其实现方案。
> 日期：2026-05-18

---

## 1. File System (fs/read_text_file & fs/write_text_file)

**ACP 协议位置**：Chapter 9
**需要能力声明**：`clientCapabilities.fs.readTextFile` / `clientCapabilities.fs.writeTextFile`

### 当前状态

Bridge 在 `initialize` 中声明了 `fs.readTextFile: true` 和 `fs.writeTextFile: true`，但 **Bridge 的 server.mts 路由表中没有 `fs/read_text_file` 和 `fs/write_text_file` 的处理入口**。Agent 发来的文件读写请求会收到 `Method not found` 错误。

### 实现方案

#### Bridge 端（server/src/）

1. **新增 `server/src/handlers/fs-read.mts`**
   - 监听来自 ACP 的 `fs/read_text_file` JSON-RPC 请求
   - 从 WS 消息中接收 agent 的请求：`{ method: "fs/read_text_file", params: { sessionId, path, line?, limit? } }`
   - 直接用 Node.js `fs.readFile()` 读取文件内容
   - 返回 `{ content: "..." }`
   - 如果 `line` 和 `limit` 有值，从指定行开始截取 `limit` 行

2. **新增 `server/src/handlers/fs-write.mts`**
   - 监听来自 ACP 的 `fs/write_text_file` JSON-RPC 请求
   - 直接用 Node.js `fs.writeFile()` 写入文件
   - 如果文件不存在则创建
   - 返回 `{ result: null }`

3. **server.mts 注册路由**
   - 在 `handleAcpMessage()` 中添加 `case "fs/read_text_file"` 和 `case "fs/write_text_file"` 分支

**工作量**：~100 行代码，两个新 handler 文件
**App 端变化**：无需变化 — Agent 直接通过 ACP 调用 Bridge，Bridge 在本地执行文件操作

---

## 2. Terminal (terminal/create / output / wait_for_exit / kill / release)

**ACP 协议位置**：Chapter 10
**需要能力声明**：`clientCapabilities.terminal: true`

### 当前状态

Bridge 在 `initialize` 中声明了 `terminal: true`，但 **没有终端相关的处理代码**。

### 实现方案

#### Bridge 端（server/src/）

1. **新增 `server/src/terminals.ts`** — 终端状态管理
   ```typescript
   class TerminalState {
     terminalId: string;
     sessionId: string;
     childProcess: ChildProcess;
     outputBuffer: string;
     exitStatus?: { exitCode: number | null; signal: string | null };
   }
   const terminals: Map<string, TerminalState> = new Map();
   ```

2. **新增 `server/src/handlers/terminal-create.mts`**
   - 使用 `spawn(command, args, { cwd, env, shell: true })` 启动子进程
   - 捕获 `stdout` / `stderr` 写入 `outputBuffer`
   - 实现 `outputByteLimit` 截断（每收到数据就检查，超出限制时从开头截断）
   - 进程退出时记录 `exitStatus`
   - 返回 `{ terminalId }`

3. **新增 `server/src/handlers/terminal-output.mts`**
   - 返回当前 output buffer + 是否截断 + exitStatus（如已退出）

4. **新增 `server/src/handlers/terminal-wait-for-exit.mts`**
   - Promise 封装的等待逻辑，监听 `childProcess.on('exit')`

5. **新增 `server/src/handlers/terminal-kill.mts`**
   - `childProcess.kill('SIGTERM')`

6. **新增 `server/src/handlers/terminal-release.mts`**
   - Kill 进程 + 清理资源 + 从 Map 中移除

**工作量**：~300 行代码，5 个新 handler + 1 个状态管理文件
**App 端变化**：Agent 发送 `tool_call` 时如果 `content.type === "terminal"`，MessageCard 需要渲染终端输出。可先做纯文本展示，后续再做终端样式（等宽字体、颜色）

#### App 端 — 终端输出展示

在 `MessageCard.ets` 中处理 `ToolCallContent.type === "terminal"` 的情况：
- 读取 `tool_call_update` 中的 `content.terminalId` 和 `content.output`
- 用等宽字体（`fontFamily('monospace')`）展示终端输出
- 黑色背景 + 白色文字的终端风格

---

## 3. Permission Request (session/request_permission)

**ACP 协议位置**：Chapter 8.5
**需要能力声明**：无（Agent 端主动发起）

### 当前状态

**完全未实现。** 当 Agent 需要请求用户授权时（如文件写入），Bridge 收到 `session/request_permission` 后无法处理，导致工具调用卡在 `pending` 状态。

### 实现方案

#### Bridge 端（server/src/）

1. **新增 `server/src/handlers/permission-request.mts`**
   - 监听来自 ACP 的 `session/request_permission` 请求
   - 将权限请求通过 WS 转发给 app：`{ type: "permission_request", toolCall: { ... }, options: [ ... ] }`
   - 等待 app 的响应（通过 WS `permission_response` 消息）
   - 将用户选择通过 ACP 返回给 Agent

#### App 端

1. **在 `WSClient.ets` 中新增消息处理**
   - `case "permission_request"`: 设置 `ChatStore.pendingPermission` 状态
   - 新增 `sendPermissionResponse()` 方法：`ws.send({ type: "permission_response", ... })`

2. **新增 `PermissionDialog` 组件**
   - 显示在消息流顶部或覆盖层
   - 展示工具调用标题和描述
   - 四个按钮：Allow once / Always allow / Reject once / Reject always
   - 点击后自动发送 `permission_response`

3. **ChatState.ets 新增状态字段**
   - `pendingPermission: { requestId: string; toolCall: { ... }; options: PermissionOption[] } | null`
   - 权限回复后清空

**工作量**：Bridge 端 ~80 行，App 端 ~150 行（WSClient + 新组件 + state）

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

Agent 可以通过 `session/update` 通知发送会话标题更新，但 **App 端未处理 `session_info_update`**。

### 实现方案

#### App 端

1. **OnboardingView.ets — `handleUpdate()` 方法新增处理**
   ```typescript
   else if (u.sessionUpdate === 'session_info_update') {
     if (u.title) {
       // 更新 sessions 列表中的 title
       for (let i = 0; i < ChatStore.sessions.length; i++) {
         if (ChatStore.sessions[i].sessionId === ChatStore.loadedSessionId) {
           ChatStore.sessions[i].title = u.title;
           break;
         }
       }
     }
   }
   ```

**工作量**：~10 行代码

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

| 优先級 | 功能 | 原因 |
|--------|------|------|
| **P1** | File System (`fs/read*, fs/write*`) | Agent 最常请求的操作，缺失会导致大量工具调用失败 |
| **P2** | Permission Request | 安全关键；没有它 Agent 的所有操作都是隐式授权 |
| **P3** | Terminal (`terminal/*`) | 高频使用（run tests、build 等），但 Agent 通常有内置终端兜底 |
| **P4** | Session Info Update | 小改动，体验提升明显 |
| **P5** | Image / Audio Input | 取决于 Agent 能力声明；多数 Agent 不支持 |
| **P6** | Auth (authenticate) | 尚无 Agent 需要 |

---

## 实施顺序建议

1. **Phase 1 (P1 + P4)**：File System + Session Info Update — 最小改动，最大效果
2. **Phase 2 (P2)**：Permission Request — 安全必备
3. **Phase 3 (P3)**：Terminal — 桥接层重头戏
4. **Phase 4 (P5 + P6)**：富媒体输入 + Auth — 低频需求，等有需要再做
