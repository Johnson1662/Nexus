# ACP v1/v2 扩展与迁移研究

> 研究日期：2026-08-03

## 结论

ACP v2 的扩展机制可以用于 Nexus 的私有能力，但它不能把第三方 Agent 的原生控制面自动“变出来”。

可用的扩展点有三类：

1. 任意协议类型上的 `_meta` 元数据；
2. 以 `_` 开头的自定义 JSON-RPC request/notification；
3. 枚举/tagged union 中以 `_` 开头的自定义变体。

因此可以定义 `_nexus/...` 私有 RPC，例如远程文件、Bridge 能力、UI 状态和诊断；但 Agent 和 Client 两端都必须实现该扩展。未知自定义 request 返回标准 `-32601 Method not found`，未知自定义 notification 应忽略。标准 ACP 客户端不会自动理解 `_nexus/...`。

## 扩展规则

### `_meta`

所有协议类型都带 `_meta: { [key: string]: unknown }`，可用于追踪、关联 ID、供应商元数据和自定义能力声明。

不能把字段直接添加到规范类型根部；规范保留所有根字段名给未来版本。能力建议用命名空间：

```json
{
  "capabilities": {
    "_meta": {
      "nexus": {
        "hostTools": true,
        "fileSync": true
      }
    }
  }
}
```

`traceparent`、`tracestate`、`baggage` 应保留给 W3C Trace Context。

### 自定义方法

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "_nexus/host/readFile",
  "params": { "path": "src/main.ts" }
}
```

request 带 `id` 并返回结果；notification 不带 `id`，只发送一次。方法名必须以 `_` 开头，不能使用未加前缀的自定义名称。

### 自定义枚举值

只有 schema 明确允许扩展的 enum/tagged union 才能使用 `_` 前缀值，例如 `_nexus/custom_state`。未知但不以 `_` 开头的值属于未来 ACP 版本，不能当成自定义扩展处理。

代理、缓存和转发层应保留未知值及原始 tagged-union payload；UI 遇到未知值应使用通用降级渲染。

## v1 与 v2 的关系

v2 不是 v1 的无缝小版本，而是一次带破坏性变化的 consolidation release。底层仍是 JSON-RPC，同一连接在初始化后只选择一个版本。

协商规则：

```text
Client initialize(protocolVersion: 2)
    ├─ Agent 支持 v2 → 本连接使用 v2
    └─ Agent 只支持 v1 → Agent 返回 v1，本连接使用 v1 或断开
```

v2 文档和 schema 在 2026-07-20 发布为 Draft。官方要求 v2 先放在显式版本协商和 feature flag 后面，同时继续支持 v1；不能因为实现 v2 就删除 v1。

### 重要破坏性变化

| 领域 | v1 | v2 |
|---|---|---|
| 初始化 | `clientCapabilities` / `clientInfo`；`agentCapabilities` / `agentInfo` | 双方统一为 `capabilities` / `info`，`info` 必填 |
| Prompt 响应 | `session/prompt` 挂起到回合结束并返回 `stopReason` | 立即确认接收；运行/结束通过 `state_update` |
| 会话加载 | `session/load` | 删除；用 `session/resume` + `replayFrom` |
| 模式 | `session/set_mode` | 删除；使用 `session/set_config_option` |
| Client 文件系统 | `fs/read_text_file`、`fs/write_text_file` | 删除；需要 Client 工具时使用 Client 提供的 MCP Server |
| Client 终端 | `terminal/*` | 删除；Agent-owned terminal 仅作为显示/回放数据 |
| Tool call | `tool_call` + `tool_call_update` | 首个 `tool_call_update` 创建，统一 upsert |
| 计划 | `plan` | `plan_update` + `planId` |
| 消息 | 主要依赖 chunk | 全消息和 chunk 都以稳定 `messageId` 做 upsert |
| 能力标记 | bool 与 object 混用 | 支持标记统一为 object，存在即支持 |
| 认证 | `authenticate` / `logout` | `auth/login` / `auth/logout` |

其中最容易影响 Nexus 的不是字段改名，而是：

- v2 的 Prompt response 不再代表回合完成；
- v2 移除了 Client 文件系统和终端执行接口；
- v2 需要用 MCP 提供 Client-side tools；
- v2 的 `session/update` 变成可在回合外持续发生的状态流。

## 对 Nexus 的落地建议

### 可以直接采用的部分

1. **保留 v1/v2 双栈协商**：初始化时尝试 v2，失败回落 v1。
2. **立即采用 `_meta` 命名空间**：`_meta.nexus` 放 trace、Bridge session、设备信息和能力声明，不影响 v1。
3. **定义私有 `_nexus/...` 方法**：只用于 Nexus Bridge 两端都能控制的功能，例如远程诊断、文件同步、设备通知和 UI 扩展。
4. **保留未知扩展数据**：WS Bridge 不要 parse 后丢弃未知 `_meta`、扩展 enum 和更新 payload。
5. **将 v2 state/update 归一化到内部事件**：`running`、`requires_action`、`idle` 应成为内部会话状态，而不是继续依赖 prompt Promise 是否结束。

### 不能指望它解决的部分

- OpenCode Server 或 Codex app-server 的原生 API 不会因为 ACP `_meta` 自动出现；需要它们自身支持，或在中间增加适配 Proxy。
- `_nexus/host/readFile` 只有 Nexus Agent/Proxy 知道如何调用时才有作用；普通 OpenCode/Codex ACP Agent 不会凭空调用它。
- `_meta` 适合元数据和能力协商，不适合承载大文件、完整终端流或复杂控制平面。
- 自定义 RPC 不会自动给其他 ACP Client 带来跨厂商互操作。

### 当前仓库状态

当前 Bridge 使用 `@agentclientprotocol/sdk` `0.21.1`，本地 `PROTOCOL_VERSION` 为 `1`。`server/src/acp/client.mts` 的初始化仍发送 v1 的：

```ts
protocolVersion: PROTOCOL_VERSION,
clientCapabilities: {
  fs: { readTextFile: true, writeTextFile: true },
  terminal: true,
},
clientInfo: { name: "nexus-bridge", version: "0.3.0" }
```

`SessionManager`、`SessionState`、`temp-client` 和多个 handler 也直接依赖 `AcpClient`。因此不能只把 `protocolVersion` 改成 `2`；需要 v2 schema/SDK、双版本初始化、双版本事件解析，以及对 v2 移除的 filesystem/terminal 面重新设计。

推荐顺序：

```text
第一步：v1 上先加 _meta.nexus 和扩展数据透传
第二步：抽出版本无关的内部 SessionEvent / SessionState
第三步：增加 v2 ACP adapter，v1/v2 按连接协商
第四步：真正需要时再定义 _nexus/* 请求；不要把大控制面塞进 _meta
第五步：Codex/OpenCode 原生能力仍由独立 adapter/proxy 实现
```

## 官方来源

- [ACP v2 Extensibility](https://agentclientprotocol.com/protocol/v2/extensibility)
- [ACP v1 Extensibility](https://agentclientprotocol.com/protocol/v1/extensibility)
- [ACP v2 Migration](https://agentclientprotocol.com/protocol/v2/migration)
- [ACP v2 Draft Announcement](https://agentclientprotocol.com/announcements/acp-v2-draft)
- [ACP v2 Schema](https://agentclientprotocol.com/protocol/v2/schema)
- [ACP v2 Overview](https://agentclientprotocol.com/protocol/v2/overview)
