# Anywhere — HarmonyOS 远程 AI 编程助手客户端

## 永远用中文回答，并用中文输出思考链

## 使用 hmdev-cli skill 查鸿蒙官方文档、构建部署项目

## 项目概述

Anywhere 是一个 HarmonyOS App，通过混合中继架构连接到 PC 端 Bridge Server，Bridge Server 再通过 ACP (Agent Client Protocol) 协议与 AI 编程 Agent (如 OpenCode、Claude Code) 通信。App 充当手机上的移动开发工作区。

```
手机 (HarmonyOS)                     GCloud VM (转发器)            Cloudflare Worker + DO        PC (Node.js Bridge)
                                    (Python websockets)           (anywhere-relay)               (server/dist/server.mjs)
┌──────────────┐     WS (无代理)     ┌──────────────────┐   WS    ┌────────────────────┐   WS    ┌─────────────────────┐
│ Phone App    │ ─────────────────→ │ ws_forwarder.py  │ ──────→ │ Durable Object     │ ──────→ │ serve:12138         │
│ (HarmonyOS)  │ ←───────────────── │ :12138           │ ←────── │ (配对双向转发)      │ ←────── │ + ACP Agent 子进程  │
└──────────────┘                     └──────────────────┘         └────────────────────┘         └─────────────────────┘
                                                                                                            │
                                                                                               Clash 代理 (127.0.0.1:7890)
                                                                                                            │
                                                                                                    ┌───────┴───────┐
                                                                                                    │ OpenCode       │
                                                                                                    │ Claude Agent   │
                                                                                                    │ codex-acp      │
                                                                                                    │ ...            │
                                                                                                    └───────────────┘
```

---

## ⚠️ 网络连接问题排查

### Server 监听配置

**当前实现：** `server/dist/server.mjs` 使用 `new WebSocketServer({ port: 12138 })`，不指定 host，自动启用 IPv4+IPv6 双栈。不要设置 `host: "::"` 或 `host: "0.0.0.0"`，否则只能监听单栈。

### 客户端 IPv6 URL 格式

`OnboardingView.ets` 的 `normalizeServerUrl()` 会自动将裸 IPv6 地址包裹方括号（例：`fe80::1:12138` → `ws://[fe80::1]:12138`）。IPv6 地址在 URL 中必须用 `[ ]` 包裹才能被 WebSocket API 正确解析。

### 防火墙

Windows 防火墙规则必须匹配实际运行的 node.exe 路径。本项目运行的是 `D:\nvm4w\nodejs\node.exe`（nvmw4 管理的 Node），不是 DevEco Studio 自带的 Node。如果加规则时绑定了错误的程序路径，外部连接会被拦截。

### Clash/代理干扰

clash-verge 的**全局模式**会劫持所有网络流量，导致手机热点连不上 PC 的桥接服务。解决方案：
- 关闭全局模式
- 或在 clash 配置中 bypass 局域网地址段 (`192.168.0.0/16`、`10.0.0.0/8` 等)

### Tailscale 连接注意事项

| 场景 | IPv4 (`100.x.x.x`) | IPv6 (`fd7a::...`) | 原因 |
|------|:---:|:---:|---|
| 手机连热点 WiFi | ✅ | ✅ | 两端直连 |
| 手机用移动数据 | ✅ | ❌ | Android 蜂窝网 IPv6 栈与 VPN IPv6 路由冲突，ULA 地址路由不完整 |

**建议始终用 Tailscale IPv4 地址连接**，所有网络环境都可靠。

### 排查流程

1. `netstat -an | findstr "12138"` — 确认 server 监听 `0.0.0.0` 和 `[::]`
2. 本机 `node -e "new (require('ws'))('ws://地址:12138')"` — 测试 server 可达性
3. `hdc shell ping <PC_IP>` — 确认手机到 PC 的网络连通性（ICMP 不通不代表 TCP 不通，但至少能排查基本网络问题）
4. `netsh advfirewall firewall show rule name=all dir=in` — 检查防火墙规则
5. 关闭 clash 全局模式重试



---

## ⚠️ Relay 中继架构（国内直连方案）

### 现状

```
手机 (HarmonyOS)                     GCloud VM (转发器)            Cloudflare Worker + DO        PC Bridge
┌──────────────┐     WS (无代理)     ┌──────────────────┐   WS    ┌────────────────────┐   WS    ┌─────────────┐
│ ws://relay   │ ─────────────────→ │ Python websockets │ ──────→ │ Durable Object     │ ──────→ │ WSS to CF   │
│ .anywhere1213│                    │ ws_forwarder.py   │ ←────── │ (配对双向转发)      │ ←────── │             │
│ 8.lat:12138  │ ←───────────────── │ :12138            │ ←────── │                    │ ←────── │             │
└──────────────┘                     └──────────────────┘         └────────────────────┘         └─────────────┘
```

国内手机 → GCloud 转发器（直连，不经过 CF）→ CF Worker DO → PC Bridge。

PC Bridge 通过 Clash 代理直接连 CF（`wss://cf-relay.anywhere12138.lat/ws`）。

### 为什么需要 Durable Object

Cloudflare Worker 的 `fetch` handler 返回后 WebSocket 连接即被操作系统销毁（~30s 超时）。DO 的 `state.acceptWebSocket(ws)` 将 WebSocket 接入 DO 的内存生命周期，使 DO 能同时持有两个 WebSocket 连接并做消息配对转发。

理论上可以去掉 CF/DO，直接在 GCloud VM 上跑一个 WebSocket server 做中心 relay，但 GCloud 200GB 免费流量对当前场景够用，暂不折腾。

### 已知问题 — Python websockets 引号剥离

GCloud 转发器（`ws_forwarder.py`，使用 Python `websockets` v16.0）在转发文本帧时会**去掉 JSON 引号**：

```
发送:  {"type":"list_agents","sessionId":"abc"}
到达:  {type:list_agents,sessionId:abc}
```

这会导致以下故障链：

|环节|表现|原因|解决方案|
|---|---|---|---|
|**JSON 解析失败**|`handlePlaintextMessage` 收到无效 JSON，`JSON.parse` 抛异常|键值引号丢失|Bridge 端正则修复（`server.mts` `handlePlaintextMessage` 的 `catch` 分支）|
|**E2EE 握手失败**|E2EE 检测 `"e2ee_hello"` 字符串匹配不到→不创建加密通道→无心跳→45s 断连|引号丢失，`includes('"e2ee_hello"')` 为 false|增加 `indexOf('type:e2ee_hello') >= 0` 检测无引号变体|
|**心跳丢失→断连循环**|手机 45s 超时→重连→再次触发 `relay_client_connected`→周期循环|无 E2EE 心跳|引号修复后心跳恢复正常|

**根因未完全定位**：可能是 Python `websockets` v16.0 在 CF Worker DO 场景下的文本帧编码问题。手机 App 端没有此问题（正常发送带引号的 JSON）。

### DNS 与流量路径

|域名|指向|方式|用途|
|---|---|---|---|
|`relay.anywhere12138.lat`|`35.212.155.17`|A 记录，proxied=false|手机直连 GCloud 转发器|
|`cf-relay.anywhere12138.lat`|Cloudflare Edge|CF proxy + Worker route|PC Bridge 通过代理连 CF|
---

## ⚠️ Golden Rule: 优先使用原生 ArkUI 组件

优先使用 ArkUI 内置组件（SideBarContainer、bindSheet、Navigation 等），而非手写浮层/弹窗。原生组件自带系统级行为：动画、无障碍、多渲染器生命周期和系统升级兼容。在 `animateTo()` 中包裹状态变更以确保平滑过渡。

---

## 关键设计决策

### 视觉设计
- **风格：** ChatGPT 风格，黑白灰单色调
- **消息气泡：** 用户消息右对齐浅灰气泡 (`Colors.userBubble`)，Agent 消息全宽无背景
- **字体：** 正文系统 sans-serif，品牌标题衬线体 (`fontFamily('serif')`)
- **Thinking/ToolCall：** 斜体灰色文本，无图标/边框/背景，呼吸透明度动画 (0.4↔1.0)
- **配色：** `#202123`, `#F4F4F4`, `#6B7280` 等

### 图标 — SymbolGlyph（关键）

尽量使用 `SymbolGlyph($r('sys.symbol.xxx'))`。

已验证可用的 symbol 名：`ohos_trash`、`ohos_wifi`、`ohos_folder_badge_plus`、`ohos_folder`、`checkmark`、`circle`、`chevron_down`、`xmark`、`xmark_circle`、`ellipsis_message_1`、`arrow_up_circle_fill`、`paperclip`、`mic`、`waveform`、`clock`、`doc`、`AI`、`square`

**不存在**的常见名：`sparkles`, `terminal`, `gear`, `ellipsis`, `rectangle_fill`, `ohos_command`

`fontColor` 必须是数组：`fontColor([Colors.accent])`，不是 `fontColor(Colors.accent)`。

参考：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

**如果系统图标库中不存在我们需要的图标，就用svg自己写一个，或者去别的地方找现成的**

### 导航
- `Navigation(NavPathStack)` + `.navDestination(this.PagesMap)` — `PagesMap` 是 `@Builder` 引用，不是 lambda
- 每个目的地必须是根节点为 `NavDestination()` 的 `@Component`
- 启用 `NavigationMode.Stack`

### 状态管理
- Model 类用 `@ObservedV2`/`@Trace`（V2）
- UI 组件用 `@Component`/`@State`/`@Prop`（V1）
- 全局单例：`ChatStore`、`WorkspaceStore`、`HostStore`
- 持久化：`StorageService`（基于 `@kit.ArkData` preferences）
- 跨组件状态：`AppStorage`（如 `serverUrl`、`lastAgent`）

### ChatStore 关键字段
- `messages` — MessageData 数组
- `streamingThinking` — 流式 thinking 独立字段（不在 LazyForEach 中），避免列表重渲染闪烁
- `turnActive`, `sessionId`, `connected`
- `sessions`, `models`, `modes`, `planEntries`
- `availableCommands` — 斜杠命令补全列表

**LazyForEach key 必须用 `msg.id + msg.content.length`**，不能只用 `msg.id`。流式传输时 content 在变化，只用 id 不会触发 UI 更新。

### Markdown 渲染
使用 `@luvi/lv-markdown-in` (v3.4.1)。`turnActive` 期间用纯 `Text()`，`turn_ended` 后切换 `MarkdownRender`。

### 工作区管理
`SideBarContainer` 侧边栏 + `WorkspaceStore` 全局单例。工作区按设备名持久化（同 PC 的所有 IP 共享），`getWorkspaceScopes()` 提供回退链。

### 设备分组 (HostStore)
`server_info` 消息按 hostname 合并 IP 为 `DeviceEntry[]`。`connectBest(urls[])` 并行探测选最低延迟。兼容旧 `HostInfo[]` 格式自动迁移。

### 自动重连
指数退避 (1s → 2s → 4s → ... → 30s 上限)，后台保活约 3 分钟。

### 动画
- 页面切换：`TransitionEffect.OPACITY + translate({ y: 20 })`
- 消息卡片：`TransitionEffect.OPACITY + translate({ y: 12 })`
- 按钮反馈：`@State scale` + `TouchType.Down/Up`
- Agent 列表：交错入场 `delay: index * 50`

---

## ⚠️ ArkTS 语法陷阱

### 类型系统
| 规则 | 错误 | 正确 |
|------|------|------|
| 禁 `any`/`unknown` | `x as unknown as string` | `String(x)` |
| 禁 `this` 类型标注 | `this: Type` | 删除 |
| 对象转基本类型 | `params.isUser as boolean` | `Boolean(params['isUser'])` |
| 箭头函数无返回类型 | `(x: number) => x` | `(x: number): number => x` |

### Navigation
- `.navDestination((name, param) => {})` ❌ — 必须用 `@Builder PagesMap(name: string)`
- 内联 `Column()` ❌ — 必须抽取 `@Component` struct

### bindSheet
- `bindSheet` 内部内容**不是响应式的** — 打开时渲染一次，不随状态变化更新
- 需要响应式浮层请用 `Stack` + 条件渲染
- `$$` 绑定位仅支持 `@State`，不支持 `@Prop`

### SideBarContainer
- 直接子节点不能用 `if/else`
- 程序化切换用 `.showSideBar(this.showDrawer)` + `animateTo()`，不用 `$$`
- 推荐替代：`Stack` + 条件渲染

### 其他常用规则
- `LongPressGesture` 通过 `.gesture()` 附加，不与 `onClick` 混用
- `@Reusable` + `aboutToReuse(params)` — 用 `String()`/`Boolean()` 转换参数，禁 `as` 转型
- `NavDestination` 内条件渲染改用 `.visibility()` 属性
- 可点击元素始终用 `Button()`，不用 `Text().onClick()`
- import 必须在文件最顶部，设计 token 统一从 `DesignTokens.ets` 引入
- `@StorageLink('key')` 需提前 `AppStorage.setOrCreate()` 初始化

### Border 语法
```ets
// 错误
.border({ left: { width: 3 } })

// 正确
.border({ width: { left: 3 }, color: { left: Colors.accent } })
```

### LazyForEach
- 必须实现 `IDataSource` 的 `registerDataChangeListener`/`unregisterDataChangeListener`
- 更新后需调用 `notifyDataReload()`

---

## 构建与部署

### 无线调试（当前设备）

```powershell
# 构建
cd Anywhere_harmony
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default assembleHap

# 连接（IP:端口每次可能不同）
hdc tconn 192.168.137.215:41015

# 部署
hdc -t "192.168.137.215:41015" install "entry/build/default/outputs/default/entry-default-signed.hap"

# 启动
hdc -t "192.168.137.215:41015" shell aa start -a EntryAbility -b com.anywhere.app
```

设备 UDID: `2NP0224627054426`

### Bridge Server

```powershell
cd Anywhere
npm run build        # 编译 TypeScript → server/dist/
npm start            # 启动 server/dist/server.mjs
```

---

## 文件结构

```
Anywhere_harmony/entry/src/main/ets/
├── pages/
│   └── Index.ets                    # 导航根 + PagesMap + WS 消息路由
├── feature/
│   ├── onboarding/
│   │   └── OnboardingView.ets       # 连接表单 + agent 发现 + 设备列表
│   ├── chat/
│   │   ├── ChatPage.ets             # 消息列表 + 流式 thinking + 输入绑定
│   │   ├── ChatInputBar.ets         # TextArea + 取消按钮 + 斜杠命令
│   │   └── ChatView.ets             # TitleBar + 抽屉 + 选择器 + 权限
│   └── workspace/
│       ├── WorkspaceDrawer.ets      # 工作区列表（增删选）
│       └── WorkspaceSelectView.ets  # 初始工作区选择
├── common/
│   ├── model/
│   │   ├── ChatState.ets            # ChatStore, ModelItem, ModeItem, PlanEntry
│   │   ├── WorkspaceInfo.ets        # WorkspaceStore, HostStore, DeviceEntry
│   │   ├── MessageData.ets
│   │   └── AgentConfig.ets
│   ├── ui/
│   │   ├── MessageCard.ets          # @Reusable 消息卡片
│   │   ├── ThinkingSection.ets      # thinking 内容区域
│   │   ├── ToolCallCard.ets         # 工具调用状态卡片
│   │   ├── PlanView.ets             # plan 条目
│   │   ├── MarkdownRender.ets       # Markdown 渲染
│   │   └── MessageDataSource.ets    # LazyForEach 数据源
│   └── websocket/
│       ├── WSClient.ets             # WS 客户端 + 自动重连 + 消息分发
│       └── WSProtocol.ets           # 协议类型定义
├── services/
│   └── StorageService.ets           # 持久化服务
└── constants/
    └── DesignTokens.ets             # 统一设计 token
```

---

## API 协议参考

### 客户端 → 服务端

| type | 关键字段 | 触发时机 |
|------|---------|---------|
| `list_agents` | — | WS 连接后自动发送 |
| `start` | `agent`, `cwd?`, `model?` | 新会话/首次消息 |
| `input` | `sessionId`, `text` | 发送消息 |
| `list_models` | `agent?` | 选 agent 后（仅一次，结果缓存本地） |
| `list_sessions` | `cwd` | 选工作区后 |
| `switch_model` | `sessionId`, `model` | 切换模型 |
| `set_mode` | `sessionId`, `modeId` | 切换模式 |
| `load_session` | `sessionId`, `cwd` | 加载历史会话 |
| `cancel` | `sessionId` | 取消当前轮次 |
| `permission_response` | `sessionId`, `requestId`, `outcome`, `optionId` | 权限请求响应 |

### 服务端 → 客户端

| type | 关键字段 | 用途 |
|------|---------|------|
| `server_info` | `hostname`, `ips[]` | 连接后立即发送 |
| `session_started` | `sessionId`, `agent`, `model?`, `title?` | 会话创建/加载 |
| `agent_event` | `event: AcpUpdate` | 流式数据块 |
| `turn_ended` | `stopReason` | 回合结束 |
| `agent_list` | `agents[]` | 已发现 agent 列表 |
| `model_list` | `models[]`, `modes[]` | 可用模型/模式 |
| `session_list` | `sessions[]` | 工作区会话列表 |
| `permission_request` | `requestId`, `toolCall`, `options[]` | 权限请求 |
| `session_closed` | — | 会话关闭 |

### AcpUpdate.sessionUpdate 类型

| 值 | 渲染为 | 关键字段 |
|----|-------|---------|
| `agent_message_chunk` | 消息文本（流式→Text，完成→MarkdownRender） | `content.text` |
| `agent_thought_chunk` | ThinkingSection | `content.text` |
| `tool_call` | ToolCallCard | `toolCallId`, `title` |
| `tool_call_update` | ToolCallCard 更新 | `toolCallId`, `status` |
| `plan` | PlanView | `entries[]` |
| `user_message_chunk` | 用户消息气泡 | `content.text` |
