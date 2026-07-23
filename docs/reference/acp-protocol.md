# Agent Client Protocol (ACP) — 完整文档

> 基于 https://agentclientprotocol.com 官方文档整理
> 整理日期：2026-05-13

---

## 目录

1. [概述与架构](#1-概述与架构)
2. [通信模型](#2-通信模型)
3. [初始化 (Initialization)](#3-初始化-initialization)
4. [会话设置 (Session Setup)](#4-会话设置-session-setup)
5. [会话列表 (Session List)](#5-会话列表-session-list)
6. [Prompt Turn (对话核心流程)](#6-prompt-turn-对话核心流程)
7. [内容块 (Content)](#7-内容块-content)
8. [工具调用 (Tool Calls)](#8-工具调用-tool-calls)
9. [文件系统 (File System)](#9-文件系统-file-system)
10. [终端 (Terminals)](#10-终端-terminals)
11. [Agent 计划 (Agent Plan)](#11-agent-计划-agent-plan)
12. [会话模式 (Session Modes)](#12-会话模式-session-modes)
13. [会话配置选项 (Session Config Options)](#13-会话配置选项-session-config-options)
14. [Slash 命令 (Slash Commands)](#14-slash-命令-slash-commands)
15. [可扩展性 (Extensibility)](#15-可扩展性-extensibility)
16. [传输层 (Transports)](#16-传输层-transports)
17. [Schema 完整类型定义](#17-schema-完整类型定义)
18. [ACP Registry (代理注册表)](#18-acp-registry-代理注册表)
19. [已知实现列表](#19-已知实现列表)

---

## 1. 概述与架构

### 1.1 什么是 ACP？

Agent Client Protocol (ACP) 是一个**标准化的通信协议**，用于代码编辑器/IDE 与 AI Coding Agent 之间的交互。它适用于本地和远程场景。

### 1.2 设计哲学

1. **MCP-friendly**：基于 JSON-RPC 2.0，尽可能复用 MCP 的数据类型
2. **UX-first**：专为解决与 AI Agent 交互的 UX 挑战而设计
3. **Trusted**：假设用户在可信的编辑器中使用可信的模型，Agent 可以访问本地文件和 MCP 服务器

### 1.3 架构

```
Client (Editor/IDE)          Agent (Coding Agent)
      │                              │
      │──── initialize ────────────→│
      │←───── 响应 ────────────────│
      │                              │
      │──── session/new ───────────→│
      │←─── sessionId ─────────────│
      │                              │
      │──── session/prompt ────────→│
      │←─── session/update (流式) ──│
      │←─── session/request_permission
      │──── permission_response ───→│
      │←─── session/update (继续) ──│
      │←─── StopReason ────────────│
```

- **Agent 端**：由 Client 作为子进程启动（或远程连接），通过 JSON-RPC 通信
- **每个连接**可以支持多个并发的 Session（多个对话同时进行）
- Agent 可以通过 JSON-RPC **通知（Notification）**实时流式推送更新到 UI
- Agent 可以通过 JSON-RPC **双向请求**向 Client 请求权限（如工具调用）

### 1.4 MCP 集成

如果编辑器配置了 MCP 服务器，在发送 `session/prompt` 时，会将这些 MCP 服务器的配置传递给 Agent，使得 Agent 可以直接连接到 MCP 服务器。

编辑器自身也可以将自己暴露为一个 MCP 服务器，通过一个代理（proxy）将请求隧道回传给自身。

---

## 2. 通信模型

### 2.1 JSON-RPC 2.0

ACP 严格遵循 JSON-RPC 2.0 规范。消息分为两种类型：

| 类型 | 描述 |
|------|------|
| **方法调用 (Method)** | 包含 `id`，接收方必须返回 `result` 或 `error` |
| **通知 (Notification)** | 不包含 `id`，单向发送，接收方不返回任何响应 |

### 2.2 完整消息流（三个阶段）

```
第一阶段：初始化
  Client ── initialize ──────────────────→ Agent
  Client ── authenticate (如果需要) ──────→ Agent

第二阶段：会话设置
  Client ── session/new (新会话) ─────────→ Agent
  Client ── session/load (恢复现有会话) ──→ Agent

第三阶段：Prompt Turn
  Client ── session/prompt ──────────────→ Agent
  Agent  ── session/update (流式) ───────→ Client  (多次)
  Agent  ── session/request_permission ──→ Client  (可选)
  Client ── permission_response ─────────→ Agent  (可选)
  Agent  ── StopReason ──────────────────→ Client
```

### 2.3 重要规则

- **所有文件路径**必须是绝对路径
- **行号**是 1-based（从 1 开始）
- 成功的响应包含 `result` 字段，错误包含 `error` 对象（含 `code` 和 `message`）
- 通知永远不会收到响应

---

## 3. 初始化 (Initialization)

Client **必须**在创建任何会话之前先调用 `initialize` 方法。

### 3.1 Initialize 请求

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": 1,
    "clientCapabilities": {
      "fs": {
        "readTextFile": true,
        "writeTextFile": true
      },
      "terminal": true
    },
    "clientInfo": {
      "name": "nexus",
      "title": "Nexus Bridge",
      "version": "0.2.0"
    }
  }
}
```

#### 参数说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `protocolVersion` | integer | 是 | Client 支持的最新协议主版本号 |
| `clientCapabilities` | object | 否 | Client 的能力声明 |
| `clientCapabilities.fs.readTextFile` | boolean | 否 | 是否支持读取文件 |
| `clientCapabilities.fs.writeTextFile` | boolean | 否 | 是否支持写入文件 |
| `clientCapabilities.terminal` | boolean | 否 | 是否支持终端命令 |
| `clientInfo.name` | string | 否 | 客户端名称 |
| `clientInfo.title` | string | 否 | 客户端标题 |
| `clientInfo.version` | string | 否 | 客户端版本 |

### 3.2 Initialize 响应

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": 1,
    "agentCapabilities": {
      "loadSession": true,
      "promptCapabilities": {
        "image": false,
        "audio": false,
        "embeddedContext": false
      },
      "mcpCapabilities": {
        "http": false,
        "sse": false
      },
      "sessionCapabilities": {
        "close": true,
        "list": true,
        "resume": true
      }
    },
    "agentInfo": {
      "name": "opencode",
      "title": "OpenCode Agent",
      "version": "1.0.0"
    }
  }
}
```

#### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `protocolVersion` | integer | 协商后的协议版本 |
| `agentCapabilities.loadSession` | boolean | 是否支持加载已有会话（默认 false） |
| `agentCapabilities.promptCapabilities` | object | Agent 支持的提示能力 |
| `agentCapabilities.promptCapabilities.image` | boolean | 是否支持图片输入 |
| `agentCapabilities.promptCapabilities.audio` | boolean | 是否支持音频输入 |
| `agentCapabilities.promptCapabilities.embeddedContext` | boolean | 是否支持嵌入上下文 |
| `agentCapabilities.mcpCapabilities.http` | boolean | 是否支持 HTTP 传输的 MCP |
| `agentCapabilities.mcpCapabilities.sse` | boolean | 是否支持 SSE 传输的 MCP（已弃用） |
| `agentCapabilities.sessionCapabilities.close` | boolean | 是否支持关闭会话 |
| `agentCapabilities.sessionCapabilities.list` | boolean | 是否支持列出会话 |
| `agentCapabilities.sessionCapabilities.resume` | boolean | 是否支持恢复会话 |
| `agentInfo.name` | string | Agent 名称 |
| `agentInfo.title` | string | Agent 标题 |
| `agentInfo.version` | string | Agent 版本 |
| `authMethods` | array | 支持的认证方法列表 |

### 3.3 协议版本协商

- `protocolVersion` 是单个整数，表示 MAJOR 版本
- 只在破坏性变更时递增
- Client 发送自己支持的最新版本，Agent 响应时使用相同版本（或它支持的最新版本）
- 如果 Client 无法处理 Agent 响应的版本，应该断开连接

### 3.4 认证

如果 Agent 需要认证，会在 `initialize` 响应中返回 `authMethods` 数组。Client 随后调用：

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "authenticate",
  "params": {
    "methodId": "bearer_token"
  }
}
```

---

## 4. 会话设置 (Session Setup)

### 4.1 创建新会话 (session/new)

Client 必须在初始化完成后才能创建会话。

#### 请求

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "session/new",
  "params": {
    "cwd": "/home/user/project",
    "mcpServers": [
      {
        "name": "filesystem",
        "command": "/path/to/mcp-server",
        "args": ["--stdio"],
        "env": []
      }
    ]
  }
}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cwd` | string | 是 | 工作目录的绝对路径 |
| `mcpServers` | array | 否 | MCP 服务器配置列表 |

#### MCP 服务器传输类型

| 类型 | 协议 | 必填项 | 要求 |
|------|------|--------|------|
| **Stdio** | 标准输入输出 | `name`, `command`, `args`, `env` | 所有 Agent 必须支持 |
| **HTTP** | HTTP 传输 | `type: "http"`, `name`, `url`, `headers` | 需要 `mcpCapabilities.http` |
| **SSE** | SSE 传输 | `type: "sse"`, `name`, `url`, `headers` | 已弃用 |

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "sessionId": "sess_abc123def456"
  }
}
```

#### 响应中的可选字段

Agent 也可以在响应中返回初始状态：

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "sessionId": "sess_abc123def456",
    "modes": {
      "currentModeId": "ask",
      "availableModes": [
        {"id": "ask", "name": "Ask", "description": "Ask questions about code"},
        {"id": "code", "name": "Code", "description": "Write and edit code"}
      ]
    },
    "configOptions": [
      {
        "id": "mode",
        "name": "Session Mode",
        "category": "mode",
        "type": "select",
        "currentValue": "ask",
        "options": [
          {"value": "ask", "name": "Ask"},
          {"value": "code", "name": "Code"}
        ]
      }
    ]
  }
}
```

### 4.2 加载已有会话 (session/load)

需要 Agent 在 `initialize` 响应中声明 `loadSession: true`。

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "session/load",
  "params": {
    "sessionId": "sess_existing_id_123"
  }
}
```

Agent **必须**以 `session/update` 通知的形式回放完整的对话历史，包括：
- `user_message_chunk`
- `agent_message_chunk`

当所有条目流式推送完毕后，Agent 返回 `null`。

### 4.3 恢复会话 (session/resume)

需要 `sessionCapabilities.resume` 能力。与会话加载 (`session/load`) 不同，恢复**不会**回放对话历史。

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "session/resume",
  "params": {
    "sessionId": "sess_existing_id_123"
  }
}
```

响应中可能包含初始的模式、模型或配置状态。

### 4.4 关闭会话 (session/close)

需要 `sessionCapabilities.close` 能力。

```json
{
  "jsonrpc": "2.0",
  "method": "session/close",
  "params": {
    "sessionId": "sess_abc123def456"
  }
}
```

Agent **必须**取消正在进行的任何工作（如同 `session/cancel`）并释放资源。

### 4.5 会话 ID 使用范围

`sessionId` 用于以下方法：`session/prompt`, `session/cancel`, `session/load`, `session/resume`, `session/close`

### 4.6 工作目录 (cwd)

- **必须**是绝对路径
- **必须**用作工具操作的范围边界
- Agent 子进程启动时的实际工作目录可能与此不同

---

## 5. 会话列表 (Session List)

需要 `sessionCapabilities.list` 能力。如果未声明，不要调用 `session/list`。

### 5.1 列出会话

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "session/list",
  "params": {
    "cwd": "/home/user/project"
  }
}
```

#### 可选参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `cwd` | string | 按工作目录筛选 |
| `cursor` | string | 不透明的分页游标 |

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "sessions": [
      {
        "sessionId": "sess_abc123",
        "cwd": "/home/user/project",
        "title": "Refactoring the auth module",
        "updatedAt": "2025-05-13T10:30:00Z"
      }
    ],
    "nextCursor": "opaque_cursor_value"
  }
}
```

#### SessionInfo 字段

| 字段 | 类型 | 必填 |
|------|------|------|
| `sessionId` | string | 是 |
| `cwd` | string | 是 |
| `title` | string | 否 |
| `updatedAt` | string (ISO 8601) | 否 |
| `_meta` | object | 否 |

### 5.2 分页规则

- 基于游标的分页；缺少 `nextCursor` 表示结果已结束
- Client **必须**将游标视为不透明字符串
- Agent **应该**对无效游标返回错误
- Agent **应该**设置合理的页面大小

### 5.3 更新会话元数据

Agent 通过 `session/update` 通知发送 `session_info_update`：

```json
{
  "sessionUpdate": "session_info_update",
  "title": "New title",
  "updatedAt": "2025-05-13T11:00:00Z"
}
```

> 注意：`sessionId` 和 `cwd` 不包含在更新中（cwd 是不可变的）

---

## 6. Prompt Turn (对话核心流程)

### 6.1 完整生命周期

#### 步骤 1：用户发送消息

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_abc123def456",
    "prompt": [
      {
        "type": "text",
        "text": "请帮我检查一下这个代码中的 bug"
      }
    ]
  }
}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sessionId` | string | 是 | 会话 ID |
| `prompt` | ContentBlock[] | 是 | 提示内容块数组 |
| `requestId` | string | 否 | 请求 ID，可用于取消 |

#### 步骤 2：Agent 处理

Agent 处理后发送给语言模型。

#### 步骤 3：Agent 报告输出

Agent 发送一系列 `session/update` 通知：

1. **计划更新**：`sessionUpdate: "plan"`, `entries[]`
2. **文本响应**：`sessionUpdate: "agent_message_chunk"`, `content.type: "text"`
3. **思考过程**：`sessionUpdate: "agent_thought_chunk"`, `content.text`
4. **工具调用**：`sessionUpdate: "tool_call"`, `toolCallId`, `title`, `kind`, `status`

#### 步骤 4：检查是否完成

如果没有待处理的工具调用，Agent 响应 `StopReason`。

#### 步骤 5：工具调用与状态报告

Agent 可能需要请求权限，然后调用工具并报告状态更新：

- `sessionUpdate: "tool_call_update"` — 更新工具状态
- 工具结果送回语言模型，循环继续

#### 步骤 6：完成

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "stopReason": "end_turn"
  }
}
```

### 6.2 StopReason (停止原因)

| 值 | 说明 |
|------|------|
| `end_turn` | 模型完成，不再请求更多工具 |
| `max_tokens` | 达到 token 限制 |
| `max_turn_requests` | 超过最大模型请求次数 |
| `refusal` | Agent 拒绝继续 |
| `cancelled` | Client 取消了对话 |

### 6.3 取消 (session/cancel)

```json
{
  "jsonrpc": "2.0",
  "method": "session/cancel",
  "params": {
    "sessionId": "sess_abc123def456",
    "requestIds": ["pending_msg_1"]
  }
}
```

#### 取消规则

- Client **应该**预先将所有未完成的工具调用标记为 `cancelled`
- Client **必须**响应所有待处理的 `session/request_permission` 请求，结果为 `cancelled`
- Agent **应该**停止所有 LM 请求和工具调用
- Agent **必须**响应原始的 `session/prompt`，使用 `cancelled` 停止原因
- Agent **可以**在收到取消后发送 `session/update`，但**必须**在响应之前完成

---

## 7. 内容块 (Content)

ACP 使用与 MCP 规范相同的 `ContentBlock` 结构。

### 7.1 文本内容

```json
{
  "type": "text",
  "text": "What's the weather like today?"
}
```

**所有 Agent 必须支持**。
- `text` (必填)：文本内容
- `annotations` (可选)：注释

### 7.2 图片内容

```json
{
  "type": "image",
  "mimeType": "image/png",
  "data": "iVBORw0KGgo..."
}
```

需要 `promptCapabilities.image = true`。
- `data` (必填)：base64 编码
- `mimeType` (必填)：图片 MIME 类型
- `uri` (可选)：URI 引用
- `annotations` (可选)

### 7.3 音频内容

```json
{
  "type": "audio",
  "mimeType": "audio/wav",
  "data": "UklGRiQAAAB..."
}
```

需要 `promptCapabilities.audio = true`。
- `data` (必填)：base64 编码
- `mimeType` (必填)：音频 MIME 类型
- `annotations` (可选)

### 7.4 嵌入资源 (Embedded Resource)

```json
{
  "type": "resource",
  "resource": {
    "uri": "file:///home/user/script.py",
    "mimeType": "text/x-python",
    "text": "def hello():\n    print('Hello, world!')"
  }
}
```

需要 `promptCapabilities.embeddedContext = true`。这是包含上下文（如 @-提及）的首选方式。资源可以是 Text 或 Blob 类型。

### 7.5 资源链接 (Resource Link)

```json
{
  "type": "resource_link",
  "uri": "file:///home/user/document.pdf",
  "name": "document.pdf",
  "mimeType": "application/pdf",
  "size": 1024000
}
```

- `uri` (必填)：资源 URI
- `name` (必填)：资源名称
- `mimeType`, `title`, `description`, `size`, `annotations` (可选)

---

## 8. 工具调用 (Tool Calls)

### 8.1 创建工具调用

```json
{
  "sessionUpdate": "tool_call",
  "toolCallId": "call_001",
  "title": "Reading configuration file",
  "kind": "read",
  "status": "pending",
  "content": [
    {
      "type": "content",
      "content": {
        "type": "text",
        "text": "Checking the config file..."
      }
    }
  ],
  "locations": [
    {
      "path": "/home/user/project/config.json",
      "line": 10
    }
  ]
}
```

#### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `toolCallId` | string | 是 | 工具调用唯一 ID |
| `title` | string | 是 | 人类可读的标题 |
| `kind` | ToolKind | 否 | 工具分类 |
| `status` | ToolCallStatus | 否 | 状态（默认 pending） |
| `content` | ToolCallContent[] | 否 | 内容块 |
| `locations` | ToolCallLocation[] | 否 | 文件位置 |

### 8.2 ToolKind (工具分类)

| 值 | 说明 |
|------|------|
| `read` | 读取文件/资源 |
| `edit` | 编辑文件 |
| `delete` | 删除文件 |
| `move` | 移动/重命名文件 |
| `search` | 搜索操作 |
| `execute` | 执行命令 |
| `think` | Agent 思考过程 |
| `fetch` | 网络请求 |
| `switch_mode` | 切换模式 |
| `other` | 其他（默认值） |

### 8.3 更新工具调用

```json
{
  "sessionUpdate": "tool_call_update",
  "toolCallId": "call_001",
  "status": "in_progress",
  "content": [
    {
      "type": "content",
      "content": {
        "type": "text",
        "text": "Found 3 files matching the pattern..."
      }
    }
  ]
}
```

所有字段除了 `toolCallId` 都是可选的。

### 8.4 ToolCallContent 类型

| 类型值 | 说明 | 关键字段 |
|--------|------|---------|
| `content` | 标准内容块 | `content` (ContentBlock) |
| `diff` | 文件差异 | `path` (必填), `oldText`, `newText` (必填) |
| `terminal` | 终端输出 | `terminalId` (必填) |

### 8.5 请求权限

Agent 可以请求用户授权：

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "session/request_permission",
  "params": {
    "sessionId": "sess_abc123def456",
    "requestId": "perm_001",
    "toolCall": {
      "toolCallId": "call_001",
      "title": "Reading file: config.json",
      "kind": "read"
    },
    "options": [
      {"optionId": "allow_once", "name": "Allow once", "kind": "allow_once"},
      {"optionId": "allow_always", "name": "Always allow", "kind": "allow_always"},
      {"optionId": "reject_once", "name": "Reject once", "kind": "reject_once"},
      {"optionId": "reject_always", "name": "Always reject", "kind": "reject_always"}
    ]
  }
}
```

Client 响应：

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "outcome": "selected",
    "optionId": "allow_once"
  }
}
```

#### PermissionOptionKind

| 值 | 说明 |
|------|------|
| `allow_once` | 仅允许一次 |
| `allow_always` | 始终允许 |
| `reject_once` | 仅拒绝一次 |
| `reject_always` | 始终拒绝 |

### 8.6 工具调用状态

| 状态 | 说明 |
|------|------|
| `pending` | 待处理 |
| `in_progress` | 执行中 |
| `completed` | 已完成 |
| `failed` | 失败 |

### 8.7 Agent 位置跟踪

工具调用可以报告 `locations`，用于跟踪 Agent 当前工作的位置：

```json
"locations": [
  {
    "path": "/home/user/project/src/main.py",
    "line": 42
  }
]
```

- `path` (必填)：绝对路径
- `line` (可选)：0-based 最小行号

---

## 9. 文件系统 (File System)

需要 Client 在 `initialize` 中声明 `clientCapabilities.fs.readTextFile` 和/或 `clientCapabilities.fs.writeTextFile`。

### 9.1 读取文件

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "fs/read_text_file",
  "params": {
    "sessionId": "sess_abc123def456",
    "path": "/home/user/project/src/main.py",
    "line": 10,
    "limit": 50
  }
}
```

#### 参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sessionId` | string | 是 | 会话 ID |
| `path` | string | 是 | 文件绝对路径 |
| `line` | integer | 否 | 起始行号（1-based） |
| `limit` | integer | 否 | 读取行数限制 |

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": "def hello():\n    print('Hello, world!')"
  }
}
```

### 9.2 写入文件

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "fs/write_text_file",
  "params": {
    "sessionId": "sess_abc123def456",
    "path": "/home/user/project/config.json",
    "content": "{\"debug\": true}"
  }
}
```

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": null
}
```

> 如果文件不存在，Client **必须**创建它。

---

## 10. 终端 (Terminals)

需要 Client 在 `initialize` 中声明 `terminal: true`。

### 10.1 创建终端

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "terminal/create",
  "params": {
    "sessionId": "sess_abc123def456",
    "command": "npm",
    "args": ["run", "build"],
    "env": [
      {"name": "NODE_ENV", "value": "production"}
    ],
    "cwd": "/home/user/project",
    "outputByteLimit": 100000
  }
}
```

#### 参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sessionId` | string | 是 | 会话 ID |
| `command` | string | 是 | 命令 |
| `args` | string[] | 否 | 参数 |
| `env` | EnvVariable[] | 否 | 环境变量 |
| `cwd` | string | 否 | 工作目录 |
| `outputByteLimit` | number | 否 | 输出字节限制 |

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "terminalId": "term_xyz789"
  }
}
```

> Agent **必须**在完成时调用 `terminal/release` 释放终端资源。

### 10.2 输出字节限制

当输出超过 `outputByteLimit` 时，Client **必须**从开始处截断，且截断**必须**在字符边界进行。

### 10.3 嵌入终端到工具调用

```json
{
  "type": "terminal",
  "terminalId": "term_xyz789"
}
```

Client 会实时显示 `terminalId` 对应的终端输出。

### 10.4 获取输出

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "terminal/output",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "output": "Build succeeded!\n",
    "truncated": false,
    "exitStatus": {
      "exitCode": 0,
      "signal": null
    }
  }
}
```

- `output` (必填)：终端输出
- `truncated` (必填)：是否被截断
- `exitStatus` (可选，仅在已退出时存在)：`exitCode` (integer|null), `signal` (string|null)

### 10.5 等待退出

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "terminal/wait_for_exit",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

#### 响应

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "exitCode": 0,
    "signal": null
  }
}
```

### 10.6 终止命令

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "terminal/kill",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

> 终止后终端仍然有效，可以继续调用 `terminal/output` 和 `terminal/wait_for_exit`。Agent **必须**仍然要调用 `terminal/release`。

### 10.7 超时模式示例

1. 创建终端
2. 启动计时器
3. 等待计时器或 `wait_for_exit`
4. 如果计时器到期：`terminal/kill`, `terminal/output`, 将输出包含到响应中
5. `terminal/release`

### 10.8 释放终端

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "terminal/release",
  "params": {
    "sessionId": "sess_abc123def456",
    "terminalId": "term_xyz789"
  }
}
```

如果终端仍在运行则终止它，并释放所有资源。终端 ID 对所有其他方法变为无效。

---

## 11. Agent 计划 (Agent Plan)

Agent 可以在执行任务前发送执行计划。

### 11.1 创建计划

```json
{
  "sessionUpdate": "plan",
  "entries": [
    {
      "content": "Analyze existing codebase to understand current architecture",
      "priority": "high",
      "status": "in_progress"
    },
    {
      "content": "Implement new authentication module",
      "priority": "high",
      "status": "pending"
    },
    {
      "content": "Write unit tests for the new module",
      "priority": "medium",
      "status": "pending"
    }
  ]
}
```

### 11.2 计划条目字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `content` | string | 是 | 人类可读的描述 |
| `priority` | string | 是 | `high`, `medium`, `low` |
| `status` | string | 是 | `pending`, `in_progress`, `completed` |

### 11.3 更新计划

Agent 每次发送**所有条目的完整列表**及其当前状态。Client **必须**完全替换当前计划。

---

## 12. 会话模式 (Session Modes)

> **注意**：新版本推荐使用 Session Config Options 替代。专用的 Session Mode 方法将在未来版本中移除。

### 12.1 初始状态

在 Session Setup 期间，Agent 可以在响应中返回模式信息：

```json
{
  "modes": {
    "currentModeId": "ask",
    "availableModes": [
      {"id": "ask", "name": "Ask", "description": "Ask questions about code"},
      {"id": "code", "name": "Code", "description": "Write and edit code"}
    ]
  }
}
```

### 12.2 SessionModeState

| 字段 | 类型 | 必填 |
|------|------|------|
| `currentModeId` | string | 是 |
| `availableModes` | SessionMode[] | 是 |

### 12.3 SessionMode

| 字段 | 类型 | 必填 |
|------|------|------|
| `id` | string | 是 |
| `name` | string | 是 |
| `description` | string | 否 |

### 12.4 Client 设置模式

```json
{
  "method": "session/set_mode",
  "params": {
    "sessionId": "sess_abc123def456",
    "modeId": "code"
  }
}
```

### 12.5 Agent 设置模式

Agent 通过 `session/update` 发送 `current_mode_update` 通知。

---

## 13. 会话配置选项 (Session Config Options)

Config Options 是比 Session Modes 更灵活的配置方案。

### 13.1 初始状态

Agent 可以在 `session/new` 响应中返回：

```json
{
  "configOptions": [
    {
      "id": "mode",
      "name": "Session Mode",
      "category": "mode",
      "type": "select",
      "currentValue": "ask",
      "options": [
        {"value": "ask", "name": "Ask", "description": "Ask questions"},
        {"value": "code", "name": "Code", "description": "Write code"}
      ]
    },
    {
      "id": "model",
      "name": "Model",
      "category": "model",
      "type": "select",
      "currentValue": "gpt-4",
      "options": [
        {"value": "gpt-4", "name": "GPT-4"},
        {"value": "claude-3", "name": "Claude 3"}
      ]
    }
  ]
}
```

### 13.2 ConfigOption 字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 配置项 ID |
| `name` | string | 是 | 人类可读名称 |
| `description` | string | 否 | 描述 |
| `category` | string | 否 | 分类（语义分类） |
| `type` | string | 是 | 目前仅支持 `select` |
| `currentValue` | string | 是 | 当前值 |
| `options` | ConfigOptionValue[] | 是 | 可选值列表 |

### 13.3 选项分类

| 值 | 说明 |
|------|------|
| `mode` | 会话模式选择器 |
| `model` | 模型选择器 |
| `thought_level` | 推理/思考级别选择器 |
| `_custom` | 自定义（以下划线开头） |

> 所有以下划线开头的分类是自定义的，其他值保留给 ACP 规范。

### 13.4 Client 设置配置

```json
{
  "method": "session/set_config_option",
  "params": {
    "sessionId": "sess_abc123def456",
    "configId": "mode",
    "value": "code"
  }
}
```

> 响应包含**完整**的配置状态（以支持依赖变更）。

### 13.5 Agent 更新配置

Agent 通过 `session/update` 发送 `config_option_update` 通知，包含完整状态。

### 13.6 与 Session Modes 的关系

- Config Options 取代 Session Modes API
- 过渡期间，Agent **应该**同时发送 `configOptions` 和 `modes`
- 支持 Config Options 的 Client **应该**专门使用它们，忽略 `modes`
- Agent **应该**使两者保持同步

---

## 14. Slash 命令 (Slash Commands)

Agent 可以向 Client 公布可用的 slash 命令。

### 14.1 公布命令

Agent 通过 `session/update` 发送 `available_commands_update`：

```json
{
  "sessionUpdate": "available_commands_update",
  "availableCommands": [
    {
      "name": "web",
      "description": "Search the web",
      "input": {
        "hint": "query to search for"
      }
    },
    {
      "name": "test",
      "description": "Run tests"
    },
    {
      "name": "plan",
      "description": "Create implementation plan",
      "input": {
        "hint": "description of what to plan"
      }
    }
  ]
}
```

### 14.2 AvailableCommand 字段

| 字段 | 类型 | 必填 |
|------|------|------|
| `name` | string | 是 |
| `description` | string | 是 |
| `input` | AvailableCommandInput | 否 |

`AvailableCommandInput` 目前只支持非结构化文本，通过 `hint` 字段提供提示。

### 14.3 更新命令

Agent 可以随时通过另一个 `available_commands_update` 更新命令列表。

### 14.4 运行命令

命令作为普通的用户消息通过 `session/prompt` 发送：

```json
{
  "prompt": [
    {
      "type": "text",
      "text": "/web agent client protocol"
    }
  ]
}
```

Agent 通过命令前缀识别。命令可以与其他内容类型一起发送。

---

## 15. 可扩展性 (Extensibility)

### 15.1 `_meta` 字段

可在协议中的所有类型上使用。类型为 `{ [key: string]: unknown }`。

#### 规则

1. 实现**不得**在规范类型的根部添加自定义字段
2. 根级别的 `_meta` 键保留给 W3C Trace Context：`traceparent`, `tracestate`, `baggage`
3. 其他位置的 `_meta` 键是自由格式

### 15.2 自定义扩展方法

以下划线开头的任何方法名都保留给自定义扩展：

- **自定义请求**：包含 `id`，期待响应。未识别的方法应返回 "Method not found" (-32601)
- **自定义通知**：省略 `id`，单向。未识别的通知**应该**被忽略

遵循标准 JSON-RPC 2.0 语义。

### 15.3 声明自定义能力

在初始化期间，在能力对象中使用 `_meta`：

```json
{
  "_meta": {
    "zed.dev": {
      "workspace": true,
      "fileNotifications": true
    }
  }
}
```

---

## 16. 传输层 (Transports)

### 16.1 JSON-RPC 消息格式

- JSON-RPC 消息**必须**是 UTF-8 编码
- 消息之间用换行符 (`\n`) 分隔
- 消息内**不得**包含嵌入式换行符

### 16.2 stdio 传输

这是 ACP 的基本传输方式：

```
Client ── 启动子进程 ──→ Agent
       stdin (JSON-RPC)  ──→ Agent
       stdout (JSON-RPC) ←── Agent
       stderr (日志)     ←── Agent
```

#### 规则

- Client 启动 Agent 作为子进程
- Agent 从 stdin 读取 JSON-RPC，写入 stdout
- Agent **可以**向 stderr 写入 UTF-8 日志（仅供人类消费）
- Agent **不得**向 stdout 写入除有效 ACP 消息之外的任何内容
- Client **不得**向 stdin 写入除有效 ACP 消息之外的任何内容

### 16.3 Streamable HTTP

处于讨论阶段，草案正在进行中。

### 16.4 自定义传输

实现**可以**实现额外的传输方式。必须保留 JSON-RPC 消息格式和生命周期。**应该**记录模式。

---

## 17. Schema 完整类型定义

### 17.1 Agent 方法

| 方法 | 类型 | 能力要求 | 说明 |
|------|------|---------|------|
| `initialize` | Request → Response | 必选 | 协商版本和能力 |
| `authenticate` | Request → Response | 可选 | 认证 |
| `session/new` | Request → Response | 必选 | 创建新会话 |
| `session/load` | Request → Response | `loadSession` | 加载已有会话 |
| `session/resume` | Request → Response | `sessionCapabilities.resume` | 恢复会话 |
| `session/close` | Request → Response | `sessionCapabilities.close` | 关闭会话 |
| `session/list` | Request → Response | `sessionCapabilities.list` | 列出会话 |
| `session/prompt` | Request → Response | 必选 | 发送提示 |
| `session/cancel` | Notification | 必选 | 取消操作 |
| `session/set_mode` | Request → Response | 可选 | 设置模式 |
| `session/set_config_option` | Request → Response | 可选 | 设置配置选项 |

### 17.2 Client 方法

| 方法 | 类型 | 能力要求 | 说明 |
|------|------|---------|------|
| `session/request_permission` | Request → Response | 必选 | 请求用户授权 |
| `session/update` | Notification | 必选 | 发送会话更新 |
| `fs/read_text_file` | Request → Response | `fs.readTextFile` | 读取文件 |
| `fs/write_text_file` | Request → Response | `fs.writeTextFile` | 写入文件 |
| `terminal/create` | Request → Response | `terminal` | 创建终端 |
| `terminal/output` | Request → Response | `terminal` | 获取终端输出 |
| `terminal/wait_for_exit` | Request → Response | `terminal` | 等待终端退出 |
| `terminal/kill` | Request → Response | `terminal` | 终止终端命令 |
| `terminal/release` | Request → Response | `terminal` | 释放终端资源 |

### 17.3 SessionUpdate 类型联合

| 类型值 | 渲染内容 | 关键字段 |
|--------|---------|---------|
| `user_message_chunk` | 用户消息 | `content.text` |
| `agent_message_chunk` | Agent 消息 | `content.text` |
| `agent_thought_chunk` | Agent 思考 | `content.text` |
| `tool_call` | 工具调用卡片 | `toolCallId`, `title` |
| `tool_call_update` | 工具调用更新 | `toolCallId`, `status` |
| `plan` | 计划视图 | `entries[]` |
| `available_commands_update` | Slash 命令列表 | `availableCommands[]` |
| `current_mode_update` | 模式更新 | — |
| `config_option_update` | 配置更新 | — |
| `session_info_update` | 会话信息 | `title` |

### 17.4 错误码

| 码值 | 说明 |
|------|------|
| -32000 | `auth_required` — 需要认证 |
| -32601 | `Method not found` — 方法未找到 |
| (其他) | 标准 JSON-RPC 错误码 |

---

## 18. ACP Registry (代理注册表)

ACP Registry 是一个方便开发者分发其 ACP 兼容 Agent 的机制，也是客户端发现可用 Agent 的途径。

### 18.1 获取注册表

```bash
curl https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json
```

返回的 JSON 包含所有 Agent 的元数据，包括分发信息。

### 18.2 注册表中的 Agent（已鉴权的）

以下 Agent 已通过鉴权并收录在官方注册表中：
Agoragentic、Amp、Auggie CLI、Autohand Code、Claude Agent、Cline、Codebuddy Code、Codex CLI、Cortex Code、Corust Agent、crow-cli、Cursor、DeepAgents、DimCode、Dirac、Factory Droid、fast-agent、Gemini CLI、GitHub Copilot、GLM Agent、Goose、Junie、Kilo、Kimi CLI、Minion Code、Mistral Vibe、Nova、OpenCode、pi ACP、Poolside、Qoder CLI、Qwen Code、siGit Code、Stakpak、VT Code

### 18.3 提交自己的 Agent

1. Fork [registry repository](https://github.com/agentclientprotocol/registry)
2. 创建以 Agent ID 命名的文件夹
3. 添加 `agent.json` 文件（遵循 [schema](https://github.com/agentclientprotocol/registry/blob/main/agent.schema.json)）
4. 可选：添加 `icon.svg`（推荐 16x16）
5. 提交 Pull Request

---

## 19. 已知实现列表

### 19.1 实现 ACP 的 Agent（不完全列表）

AgentPool、Augment Code、AutoDev、Blackbox AI、Claude Agent (via Zed adapter)、Cline、Codex CLI (via Zed adapter)、Code Assistant、crow-cli、Cursor、Docker's cagent、fast-agent、Factory Droid、fount、Gemini CLI、GitHub Copilot、Goose、Hermes Agent、Junie、Kimi CLI、Kiro CLI、Minion Code、Mistral Vibe、OpenClaw、OpenCode、OpenHands、Pi (via pi-acp adapter)、Poolside、Qoder CLI、Qwen Code、Stakpak、stdio Bus、VT Code

### 19.2 实现 ACP 的 Client（不完全列表）

**编辑器/IDE**：JetBrains、Zed、neovim (via CodeCompanion/agentic.nvim/avante.nvim)、VS Code (via vscode-acp)、Obsidian (via obsidian-agent-client)、Emacs (via agent-shell.el)、Unity
**独立客户端**：ACP UI、acpx (CLI)、DeepChat、Jockey、Lody、RayClaw、Toad 等
**移动端**：Agmente (iOS)、Ferngeist (Android)、Happy (iOS/Android/Web)、Mobvibe (iOS/Android/Web)
**消息平台**：ACP Discord、Telegram ACP Bot、WeChat ACP 等
**框架**：AgentPool、fast-agent、Koog、LangChain/LangGraph、LlamaIndex、LLMling-Agent

---

> 本文档基于 https://agentclientprotocol.com 官方文档整理，涵盖了 ACP 协议的核心规范。对于最新 RFC 和 RFD（Requests for Dialog），请参考官方网站。
