# Nexus Bridge Server

Nexus Bridge Server 是 Nexus 手机端与桌面 AI 编程 Agent 之间的桥接服务。

它在 PC 上启动 WebSocket 服务，接收手机端的会话、输入、模型、权限和文件操作请求，再通过 [Agent Client Protocol（ACP）](https://agentclientprotocol.com/) 与 OpenCode、Claude、Codex 等 Agent 通信。

```text
Nexus 手机端
    │  WebSocket / JSON
    ▼
Bridge Server :12138
    │  ACP / JSON-RPC
    ▼
桌面 AI Agent
(OpenCode / Claude / Codex / 其他 ACP Agent)
```

## 目录

- [功能概览](#功能概览)
- [运行要求](#运行要求)
- [快速开始](#快速开始)
- [启动、停止和状态管理](#启动停止和状态管理)
- [构建产物](#构建产物)
- [Agent 注册与安装](#agent-注册与安装)
- [WebSocket 协议](#websocket-协议)
- [会话使用流程](#会话使用流程)
- [工作区文件 API](#工作区文件-api)
- [MCP 配置发现](#mcp-配置发现)
- [运行数据和持久化文件](#运行数据和持久化文件)
- [日志与故障排查](#日志与故障排查)
- [安全边界](#安全边界)
- [开发与测试](#开发与测试)

## 功能概览

Bridge Server 当前负责以下工作：

1. **WebSocket 桥接**
   - 默认监听 `12138` 端口。
   - 支持局域网、手机热点和 Relay 等网络路径。
   - 传输 JSON 文本消息，兼容直接消息格式和分层消息格式。
   - 连接后立即发送主机信息，提供主机名、IPv4 地址、主机 ID 和公钥。

2. **ACP Agent 管理**
   - 从内置注册表读取 ACP Agent 元数据。
   - 根据 `~/.nexus/installed-agents.json` 判断用户已安装的 Agent。
   - 支持注册表 Agent 和自定义 Agent。
   - Agent 二进制文件仍需用户自行安装并放入 `PATH`，Bridge Server 不会自动下载第三方 Agent。

3. **会话生命周期管理**
   - 创建、加载、恢复、关闭 ACP 会话。
   - 管理 Agent 子进程和会话连接。
   - 支持断线后的会话回收和重新绑定。
   - 对 Agent 输出进行事件缓冲，客户端可使用游标补齐断线期间的消息。
   - 空闲会话会被自动清理，单个 Prompt 连续 5 分钟无输出时会超时。

4. **实时 Agent 事件转发**
   - 转发文本消息、思考过程、工具调用、工具调用更新、计划和用户消息事件。
   - 将文件读写、终端创建和终端输出统一映射为工具更新。
   - 将 Agent 的错误和 `turn_ended` 状态转发给手机端。

5. **权限审批**
   - 接收 ACP Agent 的权限请求。
   - 转发 `permission_request` 到手机端。
   - 支持 `allow`、`deny` 和 `selected` 三种审批结果。
   - 未收到有效审批前，ACP 请求会保持等待状态。

6. **工作区浏览**
   - 获取工作区文件列表和 Git 状态。
   - 查看文件 diff、文件历史和文件内容。
   - 文件列表最大递归深度为 3，并忽略隐藏文件和 `node_modules`。

## 运行要求

### 必需环境

- Node.js，建议使用 Node.js 20 或更高版本。
- npm。
- Git。如果需要使用工作区文件状态、diff 和 log，必须能在 PATH 中执行 `git`。
- 至少一个可执行的 ACP Agent。
- PC 防火墙允许手机访问 Bridge Server 端口。

### 推荐检查

```powershell
node --version
npm --version
git --version
```

安装的 Agent 也应能直接从终端启动，例如：

```powershell
opencode --help
claude --help
codex-acp --help
```

不同 Agent 的实际安装命令由 Agent 自己决定。Bridge Server 只负责按照注册表中的命令和参数启动它们。

## 快速开始

所有命令均在项目根目录执行，不要在 `server/` 目录单独运行 TypeScript 编译命令。

### 1. 安装依赖

```powershell
npm install
```

### 2. 构建 Bridge Server

```powershell
npm run build
```

构建命令会完成以下操作：

1. 使用根目录 `tsconfig.json` 编译 `server/src`。
2. 输出 JavaScript 到 `server/dist`。
3. 将 `server/src/registry/agents.json` 复制到 `server/dist/registry/agents.json`。
4. 确保 `server/dist/cli.mjs` 具有 Node.js 可执行脚本头。

### 3. 启动后台服务

```powershell
npm start
```

默认行为：

- WebSocket Bridge 监听 `12138`。
- 服务在后台运行。
- 日志追加到 `%USERPROFILE%\.nexus\daemon.log`。
- 手机端连接地址通常为：

```text
ws://<PC局域网IPv4地址>:12138
```

例如：

```text
ws://192.168.137.1:12138
```

### 4. 查询状态

```powershell
npm run status
```

服务运行时会输出类似信息：

```json
{
  "pid": 12345,
  "port": 12138,
  "uptime": 42,
  "activeSessions": 0
}
```

`activeSessions` 当前由守护进程状态接口提供，若需要精确的活动会话信息，应以 WebSocket 会话和事件为准。

### 5. 停止服务

```powershell
npm run stop
```

## 启动、停止和状态管理

### CLI 命令

编译后可以直接运行 CLI：

```powershell
node server/dist/cli.mjs start
node server/dist/cli.mjs stop
node server/dist/cli.mjs status
node server/dist/cli.mjs restart
```

### 指定端口

```powershell
node server/dist/cli.mjs start --port=12139
```

默认启动在后台。如需前台运行并直接查看日志：

```powershell
node server/dist/cli.mjs start --port=12139 --foreground
```

使用 npm 传递参数时：

```powershell
npm start -- --port=12139
npm start -- --foreground
```

### 重启

```powershell
node server/dist/cli.mjs restart --port=12138
```

CLI 守护进程使用 `%USERPROFILE%\.nexus\daemon.lock` 防止重复启动，并使用仅监听 `127.0.0.1` 的控制服务处理停止请求。控制服务端口和令牌由守护进程自动生成，不需要手动配置。

### 直接运行兼容模式

也可以绕过守护进程直接运行 Bridge：

```powershell
node server/dist/server.mjs
```

直接运行时读取环境变量 `PORT`：

```powershell
$env:PORT="12139"
node server/dist/server.mjs
```

直接运行适合调试，不建议作为常驻服务方式。常规使用优先采用 `npm start`。

## 健康检查和主机发现

Bridge 的 HTTP 接口只提供探测接口：

```powershell
curl http://127.0.0.1:12138/probe
```

返回示例：

```json
{
  "ok": true,
  "kind": "bridge",
  "hostId": "主机唯一标识",
  "hostname": "PC名称",
  "ips": ["192.168.137.1", "HOST:主机唯一标识"],
  "ts": 1760000000000
}
```

注意：

- `/probe` 只接受 `GET`。
- 未知 HTTP 路径返回 `WebSocket only`。
- 正常业务通信必须使用 WebSocket，而不是 HTTP POST。
- WebSocket 连接建立后，服务端会主动发送：

```json
{
  "type": "server_info",
  "hostId": "...",
  "ed25519PublicKeyHex": "...",
  "hostname": "...",
  "ips": ["..."]
}
```

## Agent 注册与安装

### 注册表

内置注册表位于：

```text
server/src/registry/agents.json
```

常见 Agent ID 包括：

| Agent ID | 显示名称 | 默认启动命令 |
|---|---|---|
| `opencode` | OpenCode | `opencode acp` |
| `claude-agent-acp` | Claude Agent (ACP) | `claude-agent-acp` |
| `claude` | Claude CLI | 以注册表配置为准 |
| `codex-acp` | Codex CLI | `codex-acp` |
| `gemini` | Gemini CLI | `gemini --acp` |
| `cline` | Cline | `cline --acp` |
| `kimi` | Kimi CLI | `kimi acp` |
| `qwen-code` | Qwen Code | 以注册表配置为准 |

注册表只描述 Agent，不代表对应二进制已经安装。

### 已安装 Agent 存储

```text
Windows: %USERPROFILE%\.nexus\installed-agents.json
macOS/Linux: ~/.nexus/installed-agents.json
```

首次读取时，服务会尝试写入默认 Agent：

```text
opencode
claude
codex-acp
```

只有在注册表中存在的 Agent 才会被写入默认列表。

### 通过 WebSocket 管理 Agent

查询已安装 Agent：

```json
{"type":"list_agents"}
```

服务端返回：

```json
{
  "type": "agent_list",
  "agents": [
    {
      "name": "opencode",
      "title": "OpenCode",
      "version": "latest",
      "source": "registry",
      "binaryPath": "",
      "installed": true
    }
  ]
}
```

查询完整注册表：

```json
{"type":"list_registry_agents"}
```

安装注册表 Agent：

```json
{"type":"install_agent","agentId":"opencode"}
```

成功返回：

```json
{"type":"install_agent_done","agentId":"opencode","ok":true}
```

卸载 Agent：

```json
{"type":"uninstall_agent","agentId":"opencode"}
```

安装自定义 Agent：

```json
{
  "type": "install_custom_agent",
  "name": "my-agent",
  "command": "C:/tools/my-agent.exe",
  "args": ["--acp"]
}
```

自定义 Agent 的 `command`、`args` 会写入 `installed-agents.json`。安装完成后，必须确认命令可执行，并且输出符合 ACP 协议。

## WebSocket 协议

### 连接方式

```text
ws://127.0.0.1:12138
ws://192.168.x.x:12138
```

服务端同时接受两种消息格式。

直接格式：

```json
{"type":"list_agents"}
```

分层格式：

```json
{
  "type": "session",
  "message": {
    "type": "list_agents"
  }
}
```

消息必须是合法 JSON 文本。解析失败时返回：

```json
{"type":"error","text":"invalid json"}
```

### 连接保活

客户端可以发送：

```json
{"type":"ping"}
```

服务端返回：

```json
{"type":"pong"}
```

也可以发送：

```json
{"type":"heartbeat","ts":1760000000000}
```

服务端会原样返回时间戳，或在缺少时间戳时使用服务端当前时间：

```json
{"type":"heartbeat","ts":1760000000000}
```

服务端还会定期发送 WebSocket 原生 ping 和 JSON ping，客户端应保持连接事件循环正常工作。

### 客户端请求类型

| 类型 | 主要字段 | 用途 |
|---|---|---|
| `list_agents` | 无 | 查询已安装 Agent |
| `list_registry_agents` | 无 | 查询完整 Agent 注册表 |
| `install_agent` | `agentId` | 安装注册表 Agent |
| `uninstall_agent` | `agentId` | 卸载 Agent 配置 |
| `install_custom_agent` | `name`, `command`, `args` | 安装自定义 ACP Agent |
| `start` | `agent`, `cwd`, `model`, `prompt` | 创建新会话，可选立即发送 Prompt |
| `input` | `sessionId`, `text` | 向当前会话发送输入 |
| `cancel` | `sessionId` | 取消当前 Agent 回合 |
| `list_models` | `agent`, `refresh` | 查询模型和模式列表 |
| `list_sessions` | `cwd`, `agent` | 查询会话列表 |
| `load_session` | `sessionId`, `cwd`, `agent`, `model`, `lastMessageId` | 加载历史会话 |
| `resume_session` | `sessionId`, `cwd`, `agent`, `model` | 恢复历史会话 |
| `close_session` | `sessionId` | 关闭会话和 Agent 进程 |
| `switch_model` | `sessionId`, `model` | 切换模型 |
| `set_mode` | `sessionId`, `modeId` | 切换 Agent 模式 |
| `set_config` | `sessionId`, `configId`, `value` | 设置 ACP 配置项 |
| `permission_response` | `sessionId`, `requestId`, `outcome`, `optionId` | 回复权限请求 |
| `authenticate` | `sessionId`, `methodId` | 调用 Agent 登录/认证方法 |
| `sync_request` | `sessionId`, `lastMessageId` | 补齐断线期间的事件 |
| `list_workspace_files` | `cwd` | 获取工作区文件列表 |
| `get_file_diff` | `cwd`, `path` | 获取文件 diff |
| `get_file_log` | `cwd`, `path` | 获取文件最近提交记录 |
| `get_file_content` | `cwd`, `path` | 读取文件内容 |

### 创建会话

```json
{
  "type": "start",
  "agent": "opencode",
  "cwd": "D:/Development/Anywhere",
  "model": "可选模型 ID",
  "prompt": "分析当前项目的 WebSocket 连接流程"
}
```

服务端会先立即返回：

```json
{"type":"start_ack"}
```

Agent 会话初始化完成后返回：

```json
{
  "type": "session_started",
  "sessionId": "ACP会话ID",
  "agent": "opencode",
  "title": "分析当前项目的 WebSocket 连接流程",
  "prompt": "分析当前项目的 WebSocket 连接流程"
}
```

如果 `start` 没有 `prompt`，客户端需要在收到 `session_started` 后发送 `input`：

```json
{
  "type": "input",
  "sessionId": "ACP会话ID",
  "text": "继续检查断线重连的边界情况"
}
```

### Agent 事件

实时事件统一使用：

```json
{
  "type": "agent_event",
  "sessionId": "ACP会话ID",
  "event": {
    "sessionUpdate": "agent_message_chunk",
    "content": "..."
  }
}
```

常见 `event.sessionUpdate`：

- `agent_message_chunk`：Agent 回复文本片段。
- `agent_thought_chunk`：思考过程片段。
- `tool_call`：工具调用开始。
- `tool_call_update`：工具状态、文件内容、diff 或终端输出更新。
- `plan`：计划更新。
- `user_message_chunk`：用户消息回显。

Prompt 结束时通常会收到：

```json
{
  "type": "turn_ended",
  "sessionId": "ACP会话ID",
  "stopReason": "end_turn"
}
```

异常时会收到 `type: "error"`，常见原因包括 Agent 未安装、模型权限不足、ACP 进程退出和连续 5 分钟没有输出。

### 权限审批

服务端收到 ACP 权限请求后发送：

```json
{
  "type": "permission_request",
  "sessionId": "ACP会话ID",
  "requestId": "请求唯一 ID",
  "toolCall": {
    "toolCallId": "工具调用 ID",
    "title": "执行命令"
  },
  "options": [
    {"optionId":"allow_once","name":"允许一次","kind":"allow"},
    {"optionId":"deny","name":"拒绝","kind":"deny"}
  ]
}
```

允许：

```json
{
  "type": "permission_response",
  "sessionId": "ACP会话ID",
  "requestId": "请求唯一 ID",
  "outcome": "allow"
}
```

拒绝：

```json
{
  "type": "permission_response",
  "sessionId": "ACP会话ID",
  "requestId": "请求唯一 ID",
  "outcome": "deny"
}
```

选择 Agent 提供的具体选项：

```json
{
  "type": "permission_response",
  "sessionId": "ACP会话ID",
  "requestId": "请求唯一 ID",
  "outcome": "selected",
  "optionId": "allow_once"
}
```

`requestId` 必须与当前待处理请求完全一致。合法的 `outcome` 只有 `allow`、`deny` 和 `selected`。

### 会话列表和模型列表

建议客户端始终带上 Agent 和工作目录：

```json
{
  "type": "list_sessions",
  "agent": "opencode",
  "cwd": "D:/Development/Anywhere"
}
```

返回：

```json
{
  "type": "session_list",
  "sessions": [
    {
      "sessionId": "...",
      "title": "修复连接问题",
      "agent": "opencode",
      "cwd": "D:/Development/Anywhere",
      "status": "idle",
      "createdAt": 1760000000000
    }
  ]
}
```

查询模型和模式：

```json
{
  "type": "list_models",
  "agent": "opencode",
  "refresh": false
}
```

返回：

```json
{
  "type": "model_list",
  "models": [
    {"modelId":"provider/model-id","name":"Model Name"}
  ],
  "modes": [
    {"value":"default","name":"Default"}
  ]
}
```

模型列表会按 Agent、工作目录和启动参数缓存。需要强制刷新时发送 `refresh: true`。

### 断线恢复和事件同步

客户端应保存最后收到的 `messageId`。重连并重新绑定会话后发送：

```json
{
  "type": "sync_request",
  "sessionId": "ACP会话ID",
  "lastMessageId": "最后一条消息 ID"
}
```

返回：

```json
{
  "type": "sync_response",
  "sessionId": "ACP会话ID",
  "entries": [
    {
      "messageId": "...",
      "payload": {"sessionUpdate":"agent_message_chunk"},
      "timestamp": 1760000000000
    }
  ],
  "overflow": false
}
```

如果 `overflow` 为 `true`，说明客户端游标之前的缓冲内容已经被淘汰，应重新加载会话或刷新会话状态。消息缓冲有数量上限，不是永久日志。

## 会话使用流程

一个完整的移动端流程通常如下：

```text
1. 连接 ws://<host>:12138
2. 接收 server_info
3. list_agents
4. list_sessions(agent, cwd)
5. list_models(agent)
6. start(agent, cwd, model)
7. 接收 session_started
8. input(sessionId, text)
9. 处理 agent_event
10. 遇到 permission_request 时展示审批 UI
11. 发送 permission_response
12. 接收 turn_ended
13. 断线后 resume_session 或 load_session
14. sync_request 补齐遗漏事件
15. close_session
```

## 工作区文件 API

### 获取文件列表

```json
{
  "type": "list_workspace_files",
  "cwd": "D:/Development/Anywhere"
}
```

返回的文件项包含：

```json
{
  "path": "server/src/server.mts",
  "name": "server.mts",
  "type": "file",
  "status": "M"
}
```

`status` 来自 `git status --porcelain -u`，常见值包括 `M`、`A`、`D`、`??` 和空字符串。

### 获取 diff

```json
{
  "type": "get_file_diff",
  "cwd": "D:/Development/Anywhere",
  "path": "server/src/server.mts"
}
```

服务端优先获取 `git diff HEAD`，必要时尝试 staged diff。新建且尚未提交的文件会返回文件全文作为 diff 内容。

### 获取提交历史

```json
{
  "type": "get_file_log",
  "cwd": "D:/Development/Anywhere",
  "path": "server/src/server.mts"
}
```

最多返回最近 20 条记录。

### 读取文件

```json
{
  "type": "get_file_content",
  "cwd": "D:/Development/Anywhere",
  "path": "server/src/server.mts"
}
```

ACP 文件回调会检查路径是否位于会话工作目录内，并拒绝目录穿越路径。客户端仍应只把可信工作目录发送给服务端。

## MCP 配置发现

创建 ACP 会话时，Bridge 会按 Agent 尝试发现 MCP 配置，并转成 ACP 的 `mcpServers` 参数。

当前支持的配置位置包括：

| Agent | 配置位置 |
|---|---|
| OpenCode | 工作目录或用户目录下的 `.commandcode/mcp.json` |
| Claude | `%APPDATA%\Claude\claude_desktop_config.json`、`%APPDATA%\Claude Code\config.json`、`%USERPROFILE%\.claude\claude_desktop_config.json` |
| Cursor | 工作目录或用户目录下的 `.cursor/mcp.json` |
| Cline | Code - OSS、Cursor、Windsurf 的 Cline 配置 |
| Goose | `~/.config/goose/config.yaml` 或 `config.json` |

MCP 配置中禁用项不会传给 Agent。HTTP、SSE 和 stdio 类型均会被转换。

## 运行数据和持久化文件

默认数据目录：

```text
Windows: %USERPROFILE%\.nexus
macOS/Linux: ~/.nexus
```

主要文件：

| 文件 | 用途 |
|---|---|
| `daemon.lock` | 守护进程 PID、端口和启动时间锁 |
| `daemon.port` | 预留的守护进程端口文件 |
| `daemon.control.port` | 本地控制服务端口 |
| `daemon.token` | 本地控制服务 Bearer Token |
| `daemon.log` | 后台启动时的标准输出和错误日志 |
| `host-identity.json` | 主机 ID、X25519 密钥和 Ed25519 密钥 |
| `installed-agents.json` | 已安装 Agent 配置 |
| `agent-prefs.json` | 每个 Agent 最近使用的模型 |

`host-identity.json` 和 `daemon.token` 属于敏感数据，不要提交到 Git，也不要发送给不可信设备。

如需轮换主机密钥，启动前设置：

```powershell
$env:NEXUS_ROTATE_KEYS="1"
npm start -- --foreground
```

轮换完成后应清除该环境变量，并重新在移动端完成主机信任或配对流程。

## 日志与故障排查

### 查看后台日志

```powershell
Get-Content "$env:USERPROFILE\.nexus\daemon.log" -Wait
```

查看最近日志：

```powershell
Get-Content "$env:USERPROFILE\.nexus\daemon.log" -Tail 100
```

前台调试：

```powershell
npm start -- --foreground
```

### 端口已占用

```powershell
netstat -ano | findstr :12138
```

可以换端口启动：

```powershell
npm start -- --port=12139
```

然后让手机端连接新的 WebSocket 地址。

### `agent_list` 为空

按顺序检查：

1. `list_registry_agents` 是否能返回注册表。
2. `%USERPROFILE%\.nexus\installed-agents.json` 是否包含目标 Agent。
3. Agent 的命令是否在 PATH 中。
4. `server/dist/registry/agents.json` 是否存在。
5. 重新执行 `npm run build`，确保注册表已复制到 `dist`。

### Agent 启动失败

常见原因：

- Agent 二进制未安装。
- Agent 命令不在 PATH 中。
- 自定义 Agent 的 `command` 路径错误。
- Agent 没有以 ACP 模式启动。
- 工作目录不存在。

不存在的 `cwd` 会回退到 `%USERPROFILE%\.nexus`，不会自动创建或使用一个不存在的工作区目录。

### 模型列表为空

检查：

- `list_models` 是否带了正确的 `agent`。
- 当前会话的 `cwd` 是否正确。
- Agent 是否返回 ACP 的 `models`、`modes` 或 `configOptions`。
- 是否需要发送 `refresh: true`。
- 前台日志中是否出现 `list_models error`。

Bridge 会优先读取 ACP 返回的 `models.availableModels` 和 `modes.availableModes`；如果为空，会从 `configOptions` 中提取 `category: "model"` 或 `category: "mode"` 的选择项。

### 权限请求一直等待

确认：

- 手机端是否收到 `permission_request`。
- 回复中的 `sessionId` 是否正确。
- `requestId` 是否与请求完全一致。
- `outcome` 是否为 `allow`、`deny` 或 `selected`。
- `selected` 是否同时携带有效的 `optionId`。

### Prompt 五分钟后超时

Bridge 使用滑动无活动超时。如果连续 5 分钟没有收到 Agent 输出、工具回调或其他活动，会：

1. 取消 ACP Prompt。
2. 发送 `turn_ended`，`stopReason` 为 `timeout`。
3. 发送一条 `error` 消息。

这通常表示 Agent 已卡住、模型请求未返回、网络认证失败或 Agent 进程没有继续输出。

### 手机断线后消息不完整

客户端应保存每条实时事件的 `messageId`，重新连接后按以下顺序处理：

1. 使用 `resume_session` 或 `load_session` 重新绑定。
2. 发送 `sync_request`。
3. 如果 `overflow: true`，重新调用 `list_sessions` 或加载完整历史。

## 安全边界

Bridge Server 执行的是本机 Agent 命令和工作区操作，必须按本地高权限服务对待。

- 默认使用 `ws://`，不是公网安全传输协议。
- `/probe` 无需认证，会暴露主机名、局域网地址和主机 ID。
- 不要直接把 `12138` 端口暴露到公网。
- 远程访问应使用可信网络、VPN、防火墙或已配置的 Relay 方案。
- 只安装和运行可信的 ACP Agent。
- Agent 子进程会继承服务进程的大部分环境变量，环境变量中的 API Key 可能被 Agent 读取。
- 不要把 `%USERPROFILE%\.nexus`、`host-identity.json`、`daemon.token` 或 Agent 配置提交到代码仓库。
- 工作区路径应由可信客户端提供，客户端不要把敏感目录作为 `cwd` 暴露给不可信设备。
- 权限审批只能降低误操作风险，不能替代操作系统权限、网络隔离和 Agent 本身的安全控制。

## 开发与测试

### 重新编译

```powershell
npm run build
```

编译产物位于：

```text
server/dist/
```

源码采用 ESM 和 NodeNext 模块解析，源码导入通常使用 `.mjs` 后缀，这是 TypeScript 编译到 ESM 的既定约定。

### Session Watcher 测试

先构建，再运行：

```powershell
npm run build
node server/test-session-watcher.mjs
```

该测试覆盖本地会话扫描、运行状态分类、增删改 diff、Watcher 回调和 WebSocket 状态广播。

### E2EE 单元测试

```powershell
npm run build
node server/test-e2ee-unit.mjs
```

该测试在进程内验证加密通道握手、版本协商和签名校验。

### E2EE 握手测试

```powershell
npm run build
node server/test-e2ee-handshake.mjs
```

### OpenCode 实时测试

```powershell
npm run build
node server/test-live-opencode.mjs
```

该测试需要本机已经安装并可执行 OpenCode，适合联调，不适合作为无依赖的 CI 单元测试。

### 最小 WebSocket 客户端

使用 Node.js 测试连接：

```powershell
node --input-type=module -e "import WebSocket from 'ws'; const ws = new WebSocket('ws://127.0.0.1:12138'); ws.on('open', () => ws.send(JSON.stringify({type:'list_agents'}))); ws.on('message', data => { console.log(data.toString()); if (JSON.parse(data).type === 'agent_list') ws.close(); });"
```

## 相关源码

| 模块 | 文件 | 职责 |
|---|---|---|
| 入口和路由 | `server/src/server.mts` | HTTP `/probe`、WebSocket、消息分发和主机信息 |
| CLI | `server/src/cli.mts` | start、stop、restart、status |
| 守护进程 | `server/src/daemon/` | PID 锁、后台生命周期、本地控制服务 |
| 会话管理 | `server/src/session-manager.mts` | ACP 进程池、超时、重启、事件缓冲 |
| ACP 客户端 | `server/src/acp/client.mts` | ACP 初始化、Prompt、文件、终端和权限回调 |
| Agent 发现 | `server/src/discovery/agents.mts` | 已安装 Agent 发现和启动参数解析 |
| Agent 注册表 | `server/src/registry/` | Agent 元数据和默认命令 |
| Agent 存储 | `server/src/agents-store.mts` | `installed-agents.json` 读写 |
| 文件 API | `server/src/handlers/workspace-files.mts` | 文件列表、diff、log、内容读取 |
| 会话状态扫描 | `server/src/discovery/session-watcher.mts` | 本地会话状态发现和广播 |
| MCP 发现 | `server/src/discovery/mcp-config.mts` | Agent MCP 配置读取和转换 |

## 版本与变更注意事项

- 修改 `server/src/registry/agents.json` 后必须重新执行 `npm run build`，否则运行中的 `dist` 仍使用旧注册表。
- 修改 TypeScript 源码后必须重新构建，`npm start` 不会自动编译。
- 修改 Agent 安装配置后，重新发送 `list_agents` 验证，不需要重启 Bridge。
- 修改主机身份、Relay 或网络配置后，应重新连接手机端并检查 `server_info`。
- 不要手动编辑 `daemon.lock`、`daemon.token` 和 `daemon.control.port`，异常状态优先执行 `npm run status` 和 `npm run stop`。
