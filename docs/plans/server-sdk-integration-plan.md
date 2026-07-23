# Server SDK 集成计划：替换手写 ACP 为 `@agentclientprotocol/sdk`

## 现状分析

当前 `server.js`（~892 行）手动实现了 ACP 协议的 JSON-RPC 通信。存在以下问题：

| 问题 | 后果 |
|------|------|
| 全局 `nextRpcId` / `pendingRequests`（非 per-session） | 多 Agent 并发时响应串号 |
| `\n` 切分 stdout 消息帧 | 大 JSON 或 code block 导致解析错误 |
| `handleLoadSession` 中 `OPENCODE_BIN` 未定义 | 加载历史会话直接崩溃 |
| 大量 if/else 链处理消息 | 维护成本高，容易遗漏新协议类型 |
| 协议能力声明后无后端实现（fs、terminal） | Client 虽声明了能力但实际不支持 |
| `session/set_config_option` 被 MCP 配置代码调用但 agent 不识别 | stderr 报错 |

## SDK 优势

`@agentclientprotocol/sdk` 的 `ClientSideConnection` 提供：

- JSON-RPC 2.0 自动消息分帧 + ID 匹配
- 类型安全的事件监听：`connection.on("session/update", handler)`
- 内置 session 管理
- 两侧（Client 端 + Agent 端）都支持，正好匹配 server 的角色

## 实施步骤

### 第 1 步：安装依赖 + 准备 TypeScript 环境

```bash
cd Nexus
npm install @agentclientprotocol/sdk
npm install -D typescript @types/node
npx tsc --init
```

`tsconfig.json` 关键配置：
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true
  },
  "include": ["src/**/*"]
}
```

### 第 2 步：新建 `src/server.ts`（层次结构）

```
src/
  server.ts          ← 入口：WebSocket 监听 + 路由
  session.ts         ← Session 生命周期管理
  handlers/
    start.ts          ← handleStart 逻辑
    input.ts          ← handleInput 逻辑
    load-session.ts   ← handleLoadSession 逻辑
    list-sessions.ts  ← handleListSessions 逻辑
    list-models.ts    ← handleListModels 逻辑
    set-mode.ts       ← handleSetMode 逻辑
    switch-model.ts   ← handleSwitchModel 逻辑
    permission.ts     ← handlePermissionResponse 逻辑
    cancel.ts         ← handleCancel 逻辑
  acp/
    client.ts         ← ClientSideConnection 封装
    types.ts          ← 与 ACP 类型对齐的本地类型
  discovery/
    agents.ts         ← Agent 发现（PATH 扫描）
    mcp-config.ts     ← MCP 配置加载
```

### 第 3 步：`ClientSideConnection` 封装层

```typescript
import { ClientSideConnection } from "@agentclientprotocol/sdk";
import { ChildProcess } from "child_process";

export class AcpClient {
  private conn: ClientSideConnection;
  public agentInfo: AgentInfo | null = null;
  public capabilities: AgentCapabilities | null = null;

  constructor(proc: ChildProcess) {
    // SDK 自动处理 stdin/stdout 的 JSON-RPC
    this.conn = new ClientSideConnection({
      stdout: proc.stdout!,
      stdin: proc.stdin!,
    });
  }

  async initialize(clientInfo: ClientInfo): Promise<InitializeResult> {
    const result = await this.conn.sendRequest("initialize", {
      protocolVersion: 1,
      clientCapabilities: {
        fs: { readTextFile: true, writeTextFile: true },
        terminal: true,
      },
      clientInfo,
    });
    this.agentInfo = result.agentInfo;
    this.capabilities = result.agentCapabilities;
    return result;
  }

  async createSession(params: {
    cwd: string;
    mcpServers?: McpServer[];
  }): Promise<{ sessionId: string }> {
    return this.conn.sendRequest("session/new", params);
  }

  async prompt(sessionId: string, prompt: ContentBlock[]): Promise<{ stopReason: string }> {
    return this.conn.sendRequest("session/prompt", { sessionId, prompt });
  }

  onNotification(handler: (method: string, params: any) => void) {
    this.conn.onNotification(handler);
  }

  onRequest(handler: (method: string, params: any) => Promise<any>) {
    this.conn.onRequest(handler);
  }

  destroy() {
    this.conn.close();
  }
}
```

### 第 4 步：按 ACP 协议方法逐一实现

从 `acp-protocol.md` 整理当前 server.js 覆盖率：

| ACP 方法 | 当前状态 | SDK 后方案 | 备注 |
|----------|---------|-----------|------|
| `initialize` | 手动实现 | `conn.sendRequest("initialize", ...)` | SDK 自动处理 |
| `authenticate` | 未实现 | `conn.sendRequest("authenticate", ...)` | 新增 |
| `session/new` | 手动实现 | `conn.sendRequest("session/new", ...)` | — |
| `session/load` | 有 OPENCODE_BIN bug | `conn.sendRequest("session/load", ...)` | 修复 bug |
| `session/resume` | 未实现 | `conn.sendRequest("session/resume", ...)` | 新增 |
| `session/close` | 未实现 | `conn.sendRequest("session/close", ...)` | 新增 |
| `session/list` | 未实现（用 list_sessions 包装） | `conn.sendRequest("session/list", ...)` | 标准化 |
| `session/prompt` | 手动实现 | `conn.sendRequest("session/prompt", ...)` | — |
| `session/cancel` | 手动实现 notification | `conn.sendNotification("session/cancel", ...)` | — |
| `session/set_mode` | 手动实现 | `conn.sendRequest("session/set_mode", ...)` | — |
| `session/set_config_option` | 手动调用但 agent 不识别 | `conn.sendRequest(...)`，错误由 SDK 主流程处理 | 统一 error 处理 |
| `session/update` (agent→client) | if/else 解析 | `conn.on("session/update", handler)` | SDK 事件驱动 |
| `session/request_permission` (agent→client) | 手动解析 | `conn.onRequest(...)` | SDK 自动处理 |
| `fs/read_text_file` | Client 声明支持但未实现 | 新增 handler 转发给手机端 | 新增 |
| `fs/write_text_file` | 同上 | 新增 | 新增 |
| `terminal/create` | 同上 | 新增 | 新增 |
| `terminal/output` | 同上 | 新增 | 新增 |
| `terminal/wait_for_exit` | 同上 | 新增 | 新增 |
| `terminal/kill` | 同上 | 新增 | 新增 |
| `terminal/release` | 同上 | 新增 | 新增 |

### 第 5 步：session 管理重构

每个 WebSocket 连接的 Session 容器：

```typescript
interface SessionState {
  ws: WebSocket;
  client: AcpClient;       // ← SDK ClientSideConnection
  sessionId: string;        // server 端 session ID
  acpSessionId: string;     // ACP 端 session ID
  process: ChildProcess;
  agents: string;           // "opencode" | "gemini" | ...
  pendingPermission: PermissionRequest | null;
}
```

`session/request_permission` 处理：

```typescript
client.onRequest(async (method, params) => {
  if (method === "session/request_permission") {
    // 存 pending 状态，发到手机端
    session.pendingPermission = { id, params };
    ws.send(JSON.stringify({
      type: "permission_request",
      sessionId: session.sessionId,
      requestId: params.requestId,
      toolCall: params.toolCall,
      options: params.options,
    }));
    // 不 resolve，等待手机端通过 permission_response 决定
    return new Promise((resolve) => {
      session.resolvePermission = resolve;
    });
  }
  throw new Error("unknown method");
});
```

### 第 6 步：WebSocket 协议消息适配

现有 WebSocket message type 保持兼容，但内部实现替换：

| WS type (client→server) | 当前 | SDK 后 |
|-------------------------|------|--------|
| `start` | 手动 spawn + init + session/new + prompt | `new AcpClient()` + `client.initialize()` + `client.createSession()` + `client.prompt()` |
| `input` | 直接发送 prompt JSON-RPC | `client.prompt(sessionId, prompt)` |
| `list_agents` | PATH 扫描 | 不变（与 SDK 无关） |
| `list_models` | 手动实现 | 不变（与 SDK 无关） |
| `list_sessions` | 手动实现 | `client.sendRequest("session/list", {cwd})` |
| `switch_model` | 手动实现 | `client.sendRequest("session/set_config_option", ...)` |
| `set_mode` | 手动实现 | `client.sendRequest("session/set_mode", ...)` |
| `load_session` | 有 bug | `new AcpClient()` + `initialize` + `client.sendRequest("session/load", ...)` |
| `permission_response` | 手动发 response | 手动发 response（不变） |

### 第 7 步：错误处理与优雅退出

SDK 集成后，统一错误处理：

```typescript
client.onError((err) => {
  ws.send(JSON.stringify({ type: "error", text: err.message }));
  cleanupSession(session);
});
```

进程退出处理（`tree-kill` 推荐）：

```typescript
import kill from "tree-kill";

function killSession(sess: SessionState) {
  if (sess.process && !sess.process.killed) {
    kill(sess.process.pid!, "SIGTERM");
  }
  sess.client.destroy();
}
```

### 第 8 步：测试切换

```bash
# 两版共存测试
node dist/server.js              # SDK 版
node server.js                    # 旧版（回退）

# 验证
# 1. 手机端连接正常
# 2. sendMessage → agent 响应完整无截断
# 3. 权限弹窗正常
# 4. 多 session 切换无误
# 5. MCP 配置加载无报错
```

## 与现有手机端的兼容性

SDK 集成**不影响手机端代码**。`server.js` → 手机端的 WebSocket 消息格式保持不变：

- `agent_event` / `session_started` / `turn_ended` 等消息类型不变
- 手机端 `Index.ets` / `handleUpdate` / `appendText` 无需修改
- 手机端的 `@ObservedV2 + @Trace + 原地修改` 数据流保持原样

## 集成后的预期改善

1. ✅ 消除 `OPENCODE_BIN` crash
2. ✅ 消除多 session RPC ID 串号
3. ✅ 消除 stderr MCP 报错
4. ✅ 支持 `session/list`（历史会话列表标准化）
5. ✅ 支持 `session/close` / `session/resume`
6. ✅ 支持 `fs/read_text_file` + `fs/write_text_file`（手机端远程编辑 PC 文件）
7. ✅ 支持 `terminal/*` 系列（手机端查看远程终端输出）
8. ✅ 代码量从 ~892 行精简到 ~500 行
9. ✅ TypeScript 类型安全保障

## 风险与回退

- SDK 可能不兼容某些 Agent 的 ACP 实现 → 保留旧版 `server.js` 作为回退
- SDK 的 `ClientSideConnection` 内部使用 stream 解析，如果 Agent stdout 非标准可能需要配置
- 迁移期间新旧两版共存，通过不同端口或启动参数切换
