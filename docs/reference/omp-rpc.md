# OMP `--mode rpc` 能力研究

> 研究日期：2026-08-03
>
> 结论基于 OMP 内置文档、`omp v17.2.4` 本机 CLI 帮助与最小 JSONL stdio 探测；不是对 HTTP/WebSocket 服务的研究。

## 结论

`omp --mode rpc` 是一个**无交互界面的本地 Agent 控制平面**：宿主进程通过 stdin 写入 JSONL 命令，通过 stdout 读取 JSONL 响应、Agent 流式事件、扩展 UI 请求和宿主能力回调。

它不只是“把回答转成 JSON”，而是覆盖了：

- 多轮 Prompt、流式事件、转向/追问、取消；
- 会话、历史、分支、导出、交接；
- 模型、思考级别、队列、自动压缩、重试；
- Agent 内置 Bash 的并发执行与取消；
- 宿主自定义工具和虚拟 URI 文件系统；
- 扩展的选择/确认/输入/编辑器交互；
- 子代理事件订阅和消息读取；
- 登录提供商发现与登录。

因此它适合被 Nexus 这类远程客户端后端封装：手机端只需与一个 Bridge 通信，Bridge 再以 RPC 宿主身份运行 OMP；设备专属能力可通过 host tools 或 host URI 回调给 Bridge。

## 1. 启动与传输

```text
omp --mode rpc [常规 CLI 选项]
stdin  -> JSONL 命令、扩展 UI 响应、host tool 更新/结果、host URI 结果
stdout -> ready、响应、Agent 事件、扩展 UI 请求、host tool/URI 请求
```

### 必须处理的传输规则

1. 启动后先收到 `ready`，再处理命令。当前帧声明 `protocolVersion: 1`，并可声明支持 `[1, 2]`。
2. 支持协议 v2 的宿主应发送：

   ```json
   {"id":"protocol-1","type":"negotiate_protocol","protocolVersion":2}
   ```

3. v1 每个物理 JSONL 帧上限为 1 MiB；v2 对超大 stdout 对象使用连续 `rpc_chunk`，逻辑重组上限由 `maxReassembledFrameBytes` 声明，当前文档示例为 64 MiB。
4. v2 宿主必须校验 `chunkId`、`index`、`count`、`byteLength`，拒绝交错/中断序列，并按严格 UTF-8 重组后再解析 JSON。
5. 命令响应可能乱序，必须用 `id` 关联，不能依赖 stdout 顺序；`bash` 明确并发执行。
6. stdin 关闭时，未完成的 host tool/URI 请求会被拒绝，进程正常以退出码 0 结束。
7. `@file` CLI 参数在 RPC 模式被拒绝。

## 2. 命令面

### Prompt 与生命周期

| 命令 | 能力 |
|---|---|
| `prompt` | 发送文本，可带图片；流式期间通过 `streamingBehavior: steer/followUp` 指定队列语义 |
| `steer` | 转向当前运行中的 Agent |
| `follow_up` | 排队到当前回合结束后发送 |
| `abort` | 取消当前 Agent 回合 |
| `abort_and_prompt` | 先取消再排入新 Prompt |
| `new_session` | 创建新会话，可指定父会话 |
| `negotiate_protocol` | 协商 RPC v2 |

**关键语义**：`prompt` 和 `abort_and_prompt` 的成功响应只表示“已接受”，不表示模型回合完成。正常完成看 `agent_end`；只执行本地 slash command 时，看响应里的 `data.agentInvoked: false` 或后续 `prompt_result`。

Agent 正在流式输出时，`prompt` 必须显式给 `streamingBehavior`；否则命令失败。

### 状态、模型与思考

| 命令 | 能力 |
|---|---|
| `get_state` | 当前模型、思考级别、流式/压缩状态、队列、会话、Token 速率、Todo、工具、上下文用量等 |
| `set_fast_mode` | 开关快速模式；`enabled` 与实际 `active` 分开返回 |
| `get_available_commands` | 获取当前 slash command 元数据 |
| `set_todos` | 替换当前内存 Todo 状态 |
| `set_model` / `cycle_model` / `get_available_models` | 设置、轮换、查询模型 |
| `set_thinking_level` / `cycle_thinking_level` | 设置或轮换思考级别 |
| `get_login_providers` / `login` | 查询登录提供商并发起登录 |

`get_available_models` 返回的不只是名称，可能含 provider、API、上下文窗口、能力和兼容性字段。**实测当前环境的模型元数据中出现过 Authorization 头字段；宿主不要把原始响应无审计地转发或记录。**

### 队列、压缩与重试

| 命令 | 能力 |
|---|---|
| `set_steering_mode` | `all` 或 `one-at-a-time` |
| `set_follow_up_mode` | `all` 或 `one-at-a-time` |
| `set_interrupt_mode` | `immediate` 或 `wait` |
| `compact` | 主动压缩，可附自定义指令 |
| `set_auto_compaction` | 开关自动压缩 |
| `set_auto_retry` | 开关自动重试 |
| `abort_retry` | 取消重试 |

默认值是 steering/follow-up `one-at-a-time`、interrupt `immediate`。

### Bash

| 命令 | 能力 |
|---|---|
| `bash` | 在 OMP 会话工作目录执行命令；异步执行，不阻塞后续 RPC 命令读取 |
| `abort_bash` | 取消正在运行的 Bash |

多个 Bash 可以并发，因此完成响应与发送顺序无关，必须按 `id` 关联。

### 会话与消息

| 命令 | 能力 |
|---|---|
| `get_session_stats` | 会话统计 |
| `export_html` | 导出 HTML，可给输出路径 |
| `switch_session` | 切换到指定会话文件 |
| `branch` | 从指定 entry 创建分支 |
| `get_branch_messages` | 读取当前分支消息 |
| `get_last_assistant_text` | 读取最后一条 Agent 文本 |
| `set_session_name` | 设置会话名，空字符串会失败 |
| `handoff` | 生成交接 |
| `get_messages` | 获取消息快照 |
| `get_messages_page` | 游标分页读取历史 |

`get_messages_page` 是大历史的推荐入口：返回稳定的时间顺序页、总数和 `nextCursor`；每页最多 256 条，游标绑定会话/叶节点/消息数，遇到 `session_busy` 或 `stale_cursor` 时宿主应重新开始分页。

### 子代理

| 命令 | 能力 |
|---|---|
| `set_subagent_subscription` | `off`、`progress`、`events` 三档订阅级别 |
| `get_subagents` | 查询子代理 |
| `get_subagent_messages` | 查询指定子代理或 session 文件中的消息，可按字节偏移读取 |

RPC 命令表没有独立的 `spawn_subagent` 命令；子代理通常由 Agent 使用 `task` 工具启动，RPC 侧负责订阅/观察/读取其生命周期。此句是基于命令表和 OMP task 文档的边界判断。

## 3. stdout 事件与旁路帧

除 `response` 外，宿主必须能处理以下无请求帧：

- `agent_start`、`agent_end`；
- `turn_start`、`turn_end`；
- `message_start`、`message_update`、`message_end`；
- `tool_execution_start`、`tool_execution_update`、`tool_execution_end`；
- `auto_compaction_*`、`auto_retry_*`、`ttsr_triggered`；
- `todo_reminder`、`todo_auto_clear`；
- `extension_error`；
- `available_commands_update`；
- `command_output`、`session_info_update`、`config_update`；
- `prompt_result`；
- `subagent_lifecycle`、`subagent_progress`、`subagent_event`；
- 扩展 UI 请求、host tool/URI 请求及取消。

`message_update.assistantMessageEvent` 可携带文本增量、思考增量和工具调用增量，适合直接驱动移动端流式渲染。

## 4. 宿主扩展能力

### Host tools：把宿主能力暴露给 Agent

宿主发送 `set_host_tools` 注册工具定义，之后 Agent 需要调用时，RPC 输出：

```json
{
  "type":"host_tool_call",
  "id":"host_1",
  "toolCallId":"toolu_123",
  "toolName":"echo_host",
  "arguments":{"message":"hello"}
}
```

宿主可返回进度：

```json
{"type":"host_tool_update","id":"host_1","partialResult":{"content":[{"type":"text","text":"working"}]}}
```

完成：

```json
{"type":"host_tool_result","id":"host_1","result":{"content":[{"type":"text","text":"done"}]}}
```

取消时收到 `host_tool_cancel`；失败时在结果中设置顶层 `isError: true`。重新调用 `set_host_tools` 会替换整组宿主工具。

**适合 Nexus 的用途**：把设备通知、权限确认、远程终端、项目索引、Bridge 专属操作等封装成最小、可审计的 Agent 工具；不要直接暴露任意 shell。

### Host URI：把虚拟文件/资源映射给 Agent

宿主用 `set_host_uri_schemes` 注册 URI scheme，例如 `db://`。Agent 读取或写入该 URI 时，RPC 通过 `host_uri_request` 回调宿主：

- `operation: read`：宿主返回 `content`、`contentType`、`notes`、`immutable`；
- `operation: write`：宿主接收完整替换内容；
- 可收到 `host_uri_cancel`；
- scheme 大小写不敏感，注册前转小写；重复注册会替换整组；`security://` 保留给 OMP，不能被 RPC 宿主抢占。

限制：OMP 的 `edit` 工具不直接作用于 host URI；若要修改虚拟文件，应暴露可写 scheme，让模型使用 `write` 工具。

## 5. 扩展 UI 子协议

扩展向宿主发 `extension_ui_request`：

- 需要响应：`select`、`confirm`、`input`、`editor`；
- 旁路通知：`notify`、`setStatus`、`setWidget`、`set_editor_text`；
- `setTitle` 默认被抑制，设置 `PI_RPC_EMIT_TITLE=1` 才发出；
- 登录流程还可能出现 `open_url`。

宿主对话框响应格式为 `extension_ui_response`，可携带值、布尔确认或取消/超时。

RPC 不支持或为空操作的交互包括终端输入、custom overlay、footer/header、编辑器组件、自动补全、working message、主题切换和工具展开控制。不要把 RPC 当成完整 TUI 替代品。

## 6. 启动参数与隔离

`omp --mode rpc` 可组合普通 CLI 参数，常用的宿主控制项：

```text
--cwd <path>              工作目录
--profile <name>          隔离认证、会话、设置与缓存
--session-dir <path>      会话目录
--no-session              临时会话，不保存
--model <pattern>         固定模型/模糊选择
--thinking <level>        初始思考级别
--tools <list>            工具白名单
--no-tools                禁用内置工具
--no-lsp                  禁用 LSP、格式化和诊断
--no-extensions           禁用扩展发现
--no-skills               禁用 skills 发现
--no-rules                禁用 rules 发现
--add-dir <path>          增加工作区目录
--approval-mode <mode>    always-ask / write / yolo
```

RPC 启动时默认关闭自动会话标题，以免额外模型调用；并将会改变工作流的 `todo.*`、`task.*`、`memory.*`、`advisor.*`、`async.*` 和 `bash.autoBackground.*` 设置重置到 RPC 内置默认值。

## 7. 推荐的最小宿主流程

```text
1. spawn `omp --mode rpc --cwd <workspace>`
2. 读取 ready，不要假设下一帧就是 response
3. 协商 protocolVersion 2
4. 注册 set_host_tools / set_host_uri_schemes
5. 启动独立 JSONL decoder，接受所有 stdout frame 类别
6. 发 prompt；立即 ack 后继续消费事件
7. 用 agent_end/turn_end 判断回合结束，不用 prompt response 判断结束
8. 所有 response 按 id 归属；所有工具/URI 回调按 id 完成或取消
9. 历史优先用 get_messages_page；大对象走 v2 chunk 重组
10. 关闭 stdin，等待退出码 0
```

## 8. 实测证据

本机命令：

```text
omp --help
```

结果：`omp v17.2.4`，`--mode` 支持 `text`、`json`、`rpc`、`rpc-ui`。

最小 RPC 探测使用：

```text
omp --mode rpc --no-session --no-tools --no-extensions --no-skills --no-rules --cwd D:\Development\Anywhere
```

stdin 发送 `negotiate_protocol`、`get_state`、`get_available_commands`、`get_available_models`，观察到：

- 收到 `ready`，声明 v1/v2 与帧上限；
- 收到无请求的 `extension_ui_request` 和 `available_commands_update`；
- v2 协商成功；
- 状态、命令、模型查询均返回 `success: true`。

第二次探测发送 `get_messages`、`get_messages_page`、`get_session_stats`，均返回 `success: true`，stdin EOF 后退出码为 `0`。

第三次探测注册 `echo_host` 和 `db` scheme，分别收到：

```json
{"command":"set_host_tools","success":true,"data":{"toolNames":["echo_host"]}}
{"command":"set_host_uri_schemes","success":true,"data":{"schemes":["db"]}}
```

## 来源

- OMP 内置 RPC 规范：`omp://rpc.md`
- OMP 扩展能力与 RPC UI 限制：`omp://extensions.md`
- OMP SDK 与 AgentSession 事件/工具/会话模型：`omp://sdk.md`
- OMP task agent 发现、启动和深度限制：`omp://task-agent-discovery.md`
- 本机 CLI：`omp --help`，版本 `17.2.4`
- 本机 stdio 探测：2026-08-03，命令与结果见本节
