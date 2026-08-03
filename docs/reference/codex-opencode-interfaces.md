# Codex 与 OpenCode 开放接口对比

> 研究日期：2026-08-03
>
> 目标：寻找比 ACP 更适合 Nexus 这类富客户端/远程 Bridge 的 Agent 宿主接口。
> 证据来自官方文档、官方仓库、官方 SDK 和本机 CLI 探测；版本化结论单独标注。

## 结论

ACP 更像跨厂商互操作的最小公共协议；它解决“客户端如何启动 Agent、发送 Prompt、接收更新”，但不负责完整产品控制面。

Codex 和 OpenCode 都有更厚的官方接口：

- **Codex：`codex app-server`** — 双向 JSON-RPC 2.0，能力面最完整，直接面向 VS Code 等富客户端；但协议私有、CLI 标记 experimental，WebSocket 传输官方明确不建议生产使用。
- **OpenCode：`opencode serve` + `@opencode-ai/sdk`** — HTTP + OpenAPI 3.1 + SSE，接口更容易从远程 Bridge 调用，且有运行时 `/doc` 规范和生成 SDK；工具扩展主要通过 OpenCode 配置、插件和 MCP，而不是一个等价于 Codex `dynamicTools` 的核心 RPC 注册面。

对 Nexus 的建议：**OpenCode 走 `serve`，Codex 走 `app-server`，ACP 只作为兼容兜底；不要再把 ACP 作为内部最高能力模型。**

## 1. Codex app-server

### 启动与传输

```bash
codex app-server                    # 默认 stdio://，JSONL
codex app-server --listen stdio://
codex app-server --listen ws://127.0.0.1:4500
codex app-server --listen unix://
```

协议是双向 JSON-RPC 2.0，线上通常省略 `jsonrpc: "2.0"` 字段：

```json
{"method":"initialize","id":0,"params":{"clientInfo":{"name":"nexus","title":"Nexus","version":"1"}}}
{"method":"initialized","params":{}}
{"method":"thread/start","id":1,"params":{"cwd":"/workspace"}}
{"method":"turn/start","id":2,"params":{"threadId":"thr_123","input":[{"type":"text","text":"检查这个仓库"}]}}
```

必须先 `initialize`，再发送 `initialized`；握手前的请求会被拒绝。

官方文档支持：

- `stdio`：换行分隔 JSONL；
- `ws://` / `wss://`：每个 WebSocket 文本帧一个 JSON-RPC 消息；
- Unix socket：通过 WebSocket Upgrade；
- HTTP 健康探针 `/readyz`、`/healthz`（WebSocket 监听模式）。

CLI 当前把 `app-server` 标为 `[experimental]`；官方文档还明确说 app-server 命令和 WebSocket 传输不支持生产工作负载。对 Nexus 更稳妥的方式是：Bridge 本地用 stdio 启动 Codex，Bridge 自己负责远程 WebSocket。

### 核心模型

```text
Thread  →  Turn  →  Item
会话       回合       消息、工具调用、命令执行、文件变更、进度
```

### 能力面

| 能力 | app-server 支持 |
|---|---|
| 会话 | `thread/start`、`resume`、`read`、`list`、`fork`、归档、删除、恢复、取消订阅 |
| 回合 | `turn/start`、`turn/steer`、`turn/interrupt` |
| 流式 | `thread/*`、`turn/*`、`item/*`、Agent 文本 delta、计划、工具进度、diff |
| 审批 | 命令执行审批、文件变更审批、网络/文件权限审批、工具用户输入 |
| 沙箱 | read-only、workspace-write、full access；支持权限 Profile |
| 文件 | `fs/readFile`、`writeFile`、`createDirectory`、`getMetadata`、`readDirectory`、`remove`、`copy`、`watch` |
| 命令/终端 | `command/exec`、stdin、PTY resize、终止、stdout/stderr 增量 |
| 进程 | `process/spawn`、stdin、PTY、输出、kill；实验 API，运行在 Codex sandbox 外 |
| 模型 | `model/list`、provider capabilities、思考 effort、输入模态 |
| 动态工具 | `dynamicTools` + `item/tool/call`，实验 API；客户端执行后把结果回传 |
| MCP | MCP 状态、OAuth、resource/read、tool/call、elicitation |
| 技能/插件 | skills、hooks、marketplace、插件状态和配置（部分 under development） |
| 多 Agent | collaboration mode、collab tool call、子线程和父子线程过滤 |
| 历史 | thread/turn/item 分页、cursor、归档、fork、session tree |
| 结构化输出 | SDK 和 app-server 的输入/输出模型可表达结构化内容 |

### 官方 SDK

- TypeScript：`@openai/codex-sdk`，支持启动/继续/恢复本地 Codex thread，提供 `run` / `runStreamed` 等高层封装；底层使用 app-server。
- Python：`openai-codex`，控制本地 Codex app-server；官方文档标注 Python SDK 处于 beta。
- CLI 可按当前二进制版本生成协议绑定：

```bash
codex app-server generate-ts --out ./schemas
codex app-server generate-json-schema --out ./schemas
```

生成的 schema 与运行的 Codex 版本绑定，适合避免手写协议类型。

### Codex 其他接口

```bash
codex mcp-server
```

Codex 也可作为 MCP Server，官方当前暴露两个工具：`codex` 和 `codex-reply`。这条路径更适合让另一个 Agent 编排 Codex，不适合需要细粒度会话、审批、工具事件和文件控制的客户端。

### Codex 限制

1. app-server 不是 ACP/MCP 那样的跨厂商开放标准，而是 Codex 私有协议。
2. CLI 和 WebSocket 目前带 experimental 标记；协议升级可能需要重新生成 schema 并适配。
3. 认证依赖 ChatGPT 登录或 Codex API key。
4. `process/*`、`dynamicTools`、部分插件/协作 API 需要 `experimentalApi: true`。
5. 远程 WebSocket 必须使用 TLS 和认证；非 loopback 监听不能默认当作安全通道。
6. `command/exec` 有 sandbox 语义，`process/spawn` 则是 sandbox 外显式进程控制，权限边界不能混淆。

## 2. OpenCode Server

### 启动与传输

```bash
opencode serve --hostname 127.0.0.1 --port 4096
```

OpenCode Server 是无头 HTTP 服务：

- OpenAPI 3.1 规范：`GET /doc`；
- SSE 事件：`GET /event`，第一条事件是 `server.connected`；
- 全局 SSE：`GET /global/event`；
- 可用 `--cors`、`--hostname`、`--mdns`；
- 可通过 `OPENCODE_SERVER_PASSWORD` / `OPENCODE_SERVER_USERNAME` 开启 HTTP Basic Auth。

官方文档默认端口写为 `4096`，但本机 `opencode 1.18.4` 的 `opencode serve --help` 显示 `--port` 默认值为 `0`。集成时应始终显式传端口，不要依赖文档默认值。

### 核心 API

| 领域 | 关键接口 |
|---|---|
| 服务 | `GET /global/health`、`GET /global/event`、`GET /event`、`GET /doc` |
| 项目 | `/project`、`/project/current`、`/path`、`/vcs` |
| 配置/模型 | `/config`、`/config/providers`、`/provider`、OAuth auth/callback |
| 会话 | `GET/POST /session`、详情、状态、子会话、todo、fork、abort、share、diff、summarize、revert、delete |
| 消息 | 同步 `POST /session/:id/message`、异步 `POST /session/:id/prompt_async`、slash command、shell |
| 权限 | `POST /session/:id/permissions/:permissionID` |
| 文件 | `/find`、`/find/file`、`/find/symbol`、`/file`、`/file/content`、`/file/status` |
| 工具 | 实验性的 `/experimental/tool/ids`、`/experimental/tool`，按模型返回工具 schema |
| Agent | `GET /agent` |
| LSP/MCP | `/lsp`、`/formatter`、`/mcp`，支持动态添加 MCP Server |
| TUI 控制 | `/tui/append-prompt`、submit、clear、execute-command、toast、control request/response |

`prompt_async` 返回 `204 No Content`，客户端通过 SSE 接收执行进度；这比“发送 Prompt 后轮询一次完整结果”更适合远程 UI。

### 官方 SDK

```bash
npm install @opencode-ai/sdk
```

```ts
import { createOpencodeClient } from "@opencode-ai/sdk"

const client = createOpencodeClient({
  baseUrl: "http://127.0.0.1:4096",
})

const session = await client.session.create({
  body: { title: "Nexus" },
})

await client.session.prompt({
  path: { id: session.data.id },
  body: { parts: [{ type: "text", text: "检查仓库" }] },
})

const events = await client.event.subscribe()
for await (const event of events.stream) {
  console.log(event.type, event.properties)
}
```

SDK 是从 OpenAPI 规范生成的，包含完整 TypeScript 类型；既可以 `createOpencode()` 启动服务，也可以 `createOpencodeClient()` 连接已有服务。SDK 还支持 JSON Schema structured output。

### OpenCode 权限模型

权限规则可设为：

- `allow`：直接执行；
- `ask`：请求用户批准；
- `deny`：阻止。

可按工具和参数模式细分 `read`、`edit`、`bash`、`task`、`websearch`、`external_directory` 等权限。OpenCode Server 的 API 明确提供权限响应接口，适合移动端审批 UI。

### OpenCode Agent/子代理

OpenCode 有 primary agent 和 subagent；内置 `Build`、`Plan`、`General`、`Explore`、`Scout`，可在配置文件中指定模型、Prompt、工具权限和最大步数。会话 API 支持 child sessions。

### OpenCode 限制

1. `serve` 的核心扩展面是插件/MCP/配置，不像 Codex app-server `dynamicTools` 那样在会话启动时直接注册客户端执行工具；这一点在官方 Server/SDK API 中未看到等价核心接口。
2. 事件具体字段属于 OpenCode 自己的 bus/OpenAPI 类型，客户端应从运行时 `/doc` 或生成 SDK 获取，不要手写猜测。
3. HTTP Basic Auth 只解决认证，不自动提供 TLS；跨 LAN/公网应放在 TLS/reverse proxy 后面，或只让 Nexus Bridge 本机访问。
4. Server API 是 OpenCode 自有接口，不是跨 Agent 标准；与 OpenCode 版本同步升级。

## 3. 与 ACP/OMP RPC 的取舍

| 维度 | ACP | OMP RPC | Codex app-server | OpenCode Server |
|---|---|---|---|---|
| 目标 | 跨 Agent 互操作 | OMP 宿主控制 | Codex 富客户端 | OpenCode 多客户端 |
| 传输 | stdio JSON-RPC | stdio JSONL | stdio JSONL、WS、Unix | HTTP + SSE |
| 会话/历史 | 基础会话能力 | 丰富但私有 | 极丰富、分页/fork/archive | 丰富、fork/share/revert |
| 审批 | 基础权限/请求 | 扩展 UI + host tool | 命令/文件/网络/权限 Profile | 工具权限 + permission API |
| 文件/终端 | 能力声明后使用 | 主要由 Agent 工具完成 | 原生 fs、sandbox、PTY、process | 原生文件 API、shell、文件状态 |
| 宿主工具 | Client 能力模型较有限 | `set_host_tools`、host URI | dynamic tools、MCP、文件/进程 | 插件/MCP 为主 |
| 远程接入 | 通常需自建 Bridge | 需自建 Bridge | WS 实验且有认证坑 | HTTP/SSE 原生友好 |
| 类型契约 | 标准 schema | 内置 RpcTypes | 可从二进制生成 TS/JSON Schema | `/doc` OpenAPI + SDK |
| 跨厂商 | 最强 | 仅 OMP | 仅 Codex | 仅 OpenCode |
| 稳定性风险 | 标准演进风险 | OMP 版本演进 | experimental/private | API 随版本演进 |

## 4. Nexus 建议

### 推荐落地顺序

1. **短期：增加 OpenCode Server adapter**
   - Bridge 启动 `opencode serve`；
   - 绑定显式 loopback 端口；
   - 使用 `/event` SSE + `/session/:id/prompt_async`；
   - 将 permission、message parts、file diff 映射到现有 Flutter UI。

2. **中期：增加 Codex app-server adapter**
   - Bridge 通过 stdio 启动 `codex app-server`；
   - 按 `initialize → thread/start → turn/start` 驱动；
   - 用本机 Codex 版本生成 TS/JSON Schema；
   - 把 `item/permissions/requestApproval`、`item/fileChange/requestApproval`、`item/commandExecution/outputDelta` 直接映射到 UI。

3. **内部模型改为能力超集**

```text
AgentBackend
  ├─ AcpBackend          # 兼容层
  ├─ OmpRpcBackend       # OMP
  ├─ OpenCodeServer      # HTTP/SSE
  └─ CodexAppServer      # JSON-RPC
```

内部事件至少应容纳：`thread/session`、`turn`、`message`、`plan`、`tool`、`permission`、`fileChange`、`command`、`terminal`、`diff`、`usage`、`childSession`。ACP 只能填充其中的子集，不能反过来限制其他后端。

### 选择结论

- **要最快接入 Nexus 远程架构**：OpenCode Server 更合适，HTTP/OpenAPI/SSE/SDK 天然适配 Bridge。
- **要最完整的富客户端控制能力**：Codex app-server 更强，尤其审批、沙箱、文件、PTY、进程、动态工具和分页。
- **要跨厂商统一**：ACP 仍然必要，但应被视为最低能力适配层，而不是唯一内部协议。

## 5. 本机验证

执行版本：

```text
codex --version       -> codex-cli 0.146.0   (exit 0)
opencode --version    -> 1.18.4              (exit 0)
```

帮助命令均返回 `exit 0`：

```text
codex --help
codex app-server --help
codex app-server generate-ts --help
codex app-server generate-json-schema --help
opencode --help
opencode serve --help
```

Codex app-server 最小握手（未发送 Prompt，未触发模型调用）：

```text
codex app-server --listen stdio://
```

发送 `initialize`、`initialized`、`model/list` 后，观察到 `initialize` 返回成功，随后收到配置/远程控制状态通知；stdin EOF 后进程 `exit 0`。本次未把 `model/list` 作为成功依据，只把协议握手作为本机验证结果。

## 官方来源

### OpenAI Codex

- App Server：https://developers.openai.com/codex/app-server/
- Codex SDK：https://developers.openai.com/codex/sdk/
- Codex MCP Server：https://developers.openai.com/codex/mcp-server/
- app-server 源码与协议 README：https://github.com/openai/codex/tree/main/codex-rs/app-server
- TypeScript SDK：https://github.com/openai/codex/tree/main/sdk/typescript
- Python SDK：https://github.com/openai/codex/tree/main/sdk/python

### OpenCode

- Server：https://opencode.ai/docs/server/
- SDK：https://opencode.ai/docs/sdk/
- Permissions：https://opencode.ai/docs/permissions/
- Agents：https://opencode.ai/docs/agents/
- 官方仓库：https://github.com/anomalyco/opencode
