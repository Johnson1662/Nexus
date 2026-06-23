# Anywhere — HarmonyOS 远程 AI 编程助手客户端

## 项目概述

Anywhere 是一个 HarmonyOS App，通过 Relay 中继连接到 PC 端 Bridge Server，Bridge Server 再通过 ACP (Agent Client Protocol) 协议与 AI 编程 Agent 通信。

```
手机 (HarmonyOS)                  Relay Server (GCloud)         PC (Node.js Bridge)
┌──────────────┐    WS (client)   ┌──────────────┐  WS (host)  ┌─────────────────────┐
│ Phone App    │ ───────────────→ │ relay.mjs    │ ──────────→ │ server/dist/server  │
│ (HarmonyOS)  │ ←─────────────── │ :12138       │ ←────────── │ .mjs + ACP Agent    │
└──────────────┘                  └──────────────┘             └─────────────────────┘
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

手机 App 与 PC Bridge 通过 **Relay Server**（Node.js `relay.mjs`，运行在 GCloud VM）进行 hostId 配对双向转发，不再经过 Cloudflare。

---

## 工作流程

1. 用户输入
2. 分析用户输入，使用codegraph MCP获取上下文，分析代码
3. 充分计划，然后将任务拆分为多个子任务，调用子代理处理
4. 收集并review子代理的结果，构建项目，进行修正，整合为最终结果，然后部署到手机端测试
5. 测试无误后进行git提交

| 规则 | 说明 |
|------|------|
| **Git 提交** | 每次成功改动后执行 `git commit`，只 stage 本次改动的文件 |
| **语言** | 永远用中文回答；需要解释时给出简要思路与结论，不输出隐藏思考链 |
| **设计参考** | 原型图在 `prototype_picture/`，实机截图在 `app_test_picture/`。无视觉能力的模型用 `vision_analyze` 分析截图 |
| **查文档 无限调试 连接手机部署** | 用 `deveco-cli` skill 查鸿蒙官方文档、连接手机，部署项目。不确定就查文档！ |

Codegraph MCP 用于理解代码结构。当前 MCP server 带 watcher，通常会自动 sync；若怀疑索引过期，用 `node D:/Development/codegraph-arkts/dist/bin/codegraph.js status .` 确认，必要时再手动 `sync .`，不再要求每次提交后固定执行 `index .`。

---

## 架构与设计决策

### 导航与路由

- `Navigation(NavPathStack)` + `.navDestination(this.PagesMap)` — `PagesMap` 是 `@Builder` 引用
- 启用 `NavigationMode.Stack`（`Navigation` 根节点设置 `.mode(NavigationMode.Stack)`）
- 每个目的地必须是根节点为 `NavDestination()` 或 `HdsNavDestination()` 的 `@Component`
- 首页使用 `HdsNavDestination`（来自 `@kit.UIDesignKit`），通过 `titleBar()` 配置标题、菜单项和安全区
- 聊天页使用 `NavDestination` 原生标题栏（`.title(string)`），返回键由 Stack 自动处理
- 聊天页顶部结构：左返回（原生）、中间 session 标题、右三点。Agent / Model / Mode 选择器已整合到输入栏的 Model 名称 chip 中，点击弹出 `ConfigPanel` bindSheet（摘要卡片 → 选择列表）。先选 Agent，才能选 Model；Model 默认上一次使用项
- **子页面路由**：`agentDetail` / `sessionDetail` / `workspaceDetail` / `workspaceList` / `settings`
- **跨页面参数传递**：通过 `AppStorage`（如 `selectedDeviceIndex`），不用 param 对象（ArkTS `@Builder` 限制）
- 移动端无底部 Tab，首页为主入口，底部只保留 Search / New chat 操作条
- `New chat` 直接进入聊天页，不展示中间页
- 首页右上 `plus` 直接扫码添加主机；`gearshape` 进入设置页
- 设置页 `连接与主机` 行右侧提供 `line_viewfinder` 扫码按钮和 `plus` 手动 URL 入口；主机列表用 ArkUI `List`，支持左滑删除，详情在行内展开，不做单独详情页
- `OnboardingView.ets`、`HomeManageView.ets` / `HostManageView.ets` 已删除，不要恢复。主机管理统一在 `SettingsView.ets`

### 状态管理

| 层级 | 方案 |
|------|------|
| Model 类 | `@ObservedV2` / `@Trace`（V2） |
| UI 组件 | `@Component` / `@State` / `@Prop`（V1） |
| 全局单例 | `ChatStore`、`WorkspaceStore`、`HostStore`、`HostRuntimeStore` |
| 持久化 | `StorageService`（基于 `@kit.ArkData` preferences） |
| 跨组件 | `AppStorage`（如 `serverUrl`、`lastAgent`、`pref_app_language`、`pref_color_mode`） |

### ChatStore 关键字段

```
messages: MessageData[]              — 完整消息列表
streamingThinking / streamingText    — 流式 thinking（独立字段，不在 LazyForEach 中）
turnActive / bridgeSessionId / acpSessionId
connected / currentDeviceId          — 连接状态（server_info 设置，断开清空）
sessions / models / modes / planEntries
selectedAgentName / agentType        — 当前选中的 ACP Agent
lastUsage: UsageInfo | null          — turn_ended Token 用量
reconnectPhase / reconnectAttempt    — 断线重连状态
pendingPermission                   — 当前权限请求
availableCommands                   — 斜杠命令补全
configOptions                       — Agent 配置项
```

**LazyForEach key** 必须包含消息内容或工具调用相关的长度变化字段，不能只用 `msg.id`。流式传输时 content/toolContent 在变化，只用 id 不会触发 UI 更新。

当前 ChatPage 实际 key 模式：
```ets
(msg: MessageData) => msg.id + ':' + msg.content.length + ':' + msg.toolContent.length + ':' +
  msg.toolContentType + ':' + msg.toolOldText.length + ':' + msg.toolNewText.length + ':' + msg.toolStatus
```

### 视觉设计

- **风格**：ChatGPT / Linear 混合 — 黑白灰单色调，大留白，**极致无边框**（移除卡片边框/背景，靠留白区分区块）
- **消息气泡**：用户消息灰底黑字（`Colors.surface1` + `Colors.foreground`），Agent 消息全宽无背景
- **字体**：正文 HarmonyOS Sans，品牌标题衬线体（`fontFamily('serif')`）
- **空状态**：左对齐纯文本（`FontSize.sm` + `Colors.foregroundMuted`），无图标/无按钮
- **动画**：极简淡入淡出 — `TransitionEffect.OPACITY`，150ms，`Curve.EaseOut`。无 translation/spring/staggered delay
  - 页面切换：`TransitionEffect.OPACITY`
  - 消息卡片：`TransitionEffect.OPACITY`
- **按压反馈**：背景色浮现 — `stateStyles({ pressed: { .backgroundColor(Colors.surface1) }, normal: { .backgroundColor(Color.Transparent) } })`，不再用 `scale(0.97)`
- **输入框**：悬浮胶囊（Floating Pills）— 圆角 + 阴影，不贴底部边缘
- **代码块**：柔和表面（浅灰 `surface1`/`surface2` 背景 + 深色文字，无边框）

### 图标

**系统符号库（优先）**：`SymbolGlyph($r('sys.symbol.xxx'))`，`fontColor` 必须是数组格式：`fontColor([Colors.accent])`，**不是 `fontColor(Colors.accent)`**。

常用：`house`/`house_fill`、`person_2`/`person_2_fill`、`clock`、`gearshape`、`chevron_left`、`ellipsis_message`、`person_badge_plus`、`vpn_key`、`wifi`、`externaldrive`、`square_grid_2x2`。完整列表见 `docs/harmonyos-symbol-reference.md`。

参考：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

**自定义 SVG 图标**：当系统符号库无匹配时，用 SVG 文件代替。**严禁用 `Path().commands()` 绘制**（坐标是绝对 px，无 viewBox 缩放）。

正确做法：
1. 创建 `<svg viewBox="0 0 24 24">` 放到 `entry/src/main/resources/base/media/`
2. 用 `Image($r('app.media.ic_xxx')).fillColor(color)` 加载
3. 通过 `CustomIcon` 组件统一调用：`CustomIcon({ name: 'stop', iconSize: 28, color: Colors.error })`

注册在 `CustomIcon` 组件中的 SVG 名称：`thinking`、`thinking_done`/`check`、`knot`/`logo`、`stop`/`cancel`、`warning`/`alert`、`edit`/`pencil`、`tool`/`wrench`、`progress`/`spinner`、`new_chat`/`compose`、`waveform`、`panel`/`grid`、`menu`、`dots`/`more`、`copy`、`paste`、`link`、`close`/`xmark`、`scan`、`model`、`clear`/`trash`、`error`。各名称对应的 SVG 文件在 `entry/src/main/resources/base/media/` 下以 `ic_<name>.svg` 命名。

### 配置面板 (ConfigPanel)

ChatInputBar 的 Model 名称 chip 点击后弹出单 bindSheet（`ConfigPanel`），分两种视图：
- **summary 视图**：显示当前 Agent / Model / Mode 摘要卡片，每行可点击
- **selection 视图**：根据选中项展示对应列表（Agent 列表 / Provider 列表 / Model 列表 / Mode 列表），支持右上角刷新

视图切换通过 `switchView()` 关闭 sheet → 更新 `sheetView` → 重开 sheet 实现。Provider→Model 钻取同样使用此模式。

### 会话时间戳

opencode ACP 返回 session 时使用 `updatedAt`（ISO 8601 字符串）而非 `createdAt`。`WSClient` 在 `session_list` 处理时从原始 JSON 提取 `updatedAt` 并转为 epoch ms。所有 `formatRelativeTime` 函数添加 `!epoch` 防御检查。

### 工作区管理

`SideBarContainer` 侧边栏 + `WorkspaceStore` 全局单例。工作区按设备名持久化（同 PC 的所有 IP 共享），`getWorkspaceScopes()` 提供回退链。

### 设置页与偏好

- 设置页是 HarmonyOS / iOS 系统设置风：分组标题 + 大圆角列表组；不做营销页/说明页
- `SettingsView.ets` 包含 `连接与主机`、`显示`、`偏好设置` 三组；语言和外观选择器均为 inline 展开，不跳转单独详情页
- 语言 / 外观偏好由 `AppPreferenceService.ets` 统一 normalize / apply，并通过 `StorageService` 持久化到 `PrefsKeys.APP_LANGUAGE`、`PrefsKeys.COLOR_MODE`
- `pref_app_language` / `pref_color_mode` 必须用 `AppStorage.setOrCreate()` 初始化，设置页用 `@StorageLink` 读取，避免选择器状态和启动层不同步
- `LANGUAGE_SYSTEM` 表示跟随系统。HarmonyOS 的 `setAppPreferredLanguage('default')` 需要冷启动才完全生效，当前实现会在运行时读取系统语言并立即应用，回前台时重新同步
- 语言切换当前通过 `localeRevision` + keyed `ForEach` 保证文案和勾选刷新；视觉节奏后续 polish 已记录在 `docs/todo.md`

### 设备与连接

**HostStore（设备分组）**：`server_info` 消息按 hostname / hostId 合并 IP 为 `DeviceEntry[]`，只保存配对主机、URL、relayPin、relayUrl 等持久化信息。兼容旧 `HostInfo[]` 格式自动迁移。

**HostRuntimeStore（运行态）**：独立在 `common/model/HostState.ets`，不要塞回 `WorkspaceInfo.ets`。所有 host 在线/离线/重连/等待 host 状态统一读写 `HostRuntimeStore`。

`HostPhase` 当前值：`unknown`、`connecting`、`waiting_host`、`online`、`offline`、`reconnecting`、`syncing`、`error`。`unknown` 表示本次启动尚未探测或还没有运行态信息，不等于 offline。

只连上 Relay 但目标 PC host 没有连上 Relay 时，不能算 online；应进入 `waiting_host` 或后续 `offline/error`。绿色点只对应 `online` / `syncing`，橙色对应 `connecting` / `waiting_host` / `reconnecting`。

**HostFilterBar**：独立 `@Component`，读取 `HostRuntimeStore.getDevicePhase(device)` 和 `ChatStore.connected/currentDeviceId` 判断 chip 状态。`ForEach` key 包含 `statusRevision`，由 Index 的 WS 状态回调 bump，确保首页 host 绿点实时刷新。

**WSClient 连接探测**：`connectBest(urls[])` 并行尝试候选地址，选择最快的可用连接；relay client URL 必须带 `role=client&targetHostId=<hostId>`。探测不应创建业务 session，也不应污染 host 运行态。

**自动重连**：指数退避（1s → 2s → 4s → ... → 30s 上限）。后台恢复依赖快速重连 + `sync_request`/消息游标补齐，不宣称普通 UIAbility 能长期后台保活。

### 缓存结构与刷新策略

```
层级: host → workspace → agent → provider → model/mode/session
```

- **Agent 列表**：每天启动时对已配对主机请求一次，之后读 `DeviceAgentStore` / preferences 缓存；支持手动刷新
- **Model / Mode 列表**：与 workspace + agent 绑定，首次进入工作区并选定 agent 时请求；切换 agent 后才能切换 model
- **Session 列表**：与 workspace 绑定，首次打开工作区请求并缓存；除非新建/加载会话、手动刷新或后端推送变化，不重复加载
- 启动时自动向已配对主机发起连接，失败只进入重连/手动刷新状态，不阻塞首页渲染

---

## ArkTS 开发指南

### Golden Rule: 优先使用原生组件

优先使用 ArkUI 内置组件（`SideBarContainer`、`bindSheet`、`Navigation` 等），而非手写浮层/弹窗。原生组件自带系统级行为：动画、无障碍、多渲染器生命周期和系统升级兼容。在 `animateTo()` 中包裹状态变更以确保平滑过渡。

### 类型系统

| 规则 | 错误 | 正确 |
|------|------|------|
| 禁 `any`/`unknown` | `x as unknown as string` | `String(x)` |
| 禁 `this` 类型标注 | `this: Type` | 删除 |
| 对象转基本类型 | `params.isUser as boolean` | `Boolean(params['isUser'])` |
| 箭头函数无返回类型 | `(x: number) => x` | `(x: number): number => x` |

### 组件陷阱

#### Navigation
- `.navDestination((name, param) => {})` ❌ — 必须用 `@Builder PagesMap(name: string)`
- 内联 `Column()` ❌ — 必须抽取 `@Component` struct

#### bindSheet
- 内部内容**不是响应式的** — 打开时渲染一次，不随状态变化更新
- 需要响应式浮层用 `Stack` + 条件渲染
- `$$` 绑定位仅支持 `@State`，不支持 `@Prop`

#### SideBarContainer
- 直接子节点不能用 `if/else`
- 程序化切换用 `.showSideBar(this.showDrawer)` + `animateTo()`，不用 `$$`
- 推荐替代：`Stack` + 条件渲染

#### NavDestination
- `.hideTitleBar(true)` 会隐藏原生标题栏；不设置则显示原生标题栏+返回键
- 条件渲染改用 `.visibility()` 属性而非 `if/else`
- `.title(string)` 的标题会随组件重渲染更新

#### HdsNavDestination
- 内容区需要手动 `.padding({ top: 42 })` 避免与标题栏重叠（高度约 42-56vp，无自动避让）
- 菜单项是配置对象，不能附加 `.bindMenu()`
- 多菜单选项方案：用 `NavDestination` + `.title(CustomBuilder)` 放真实 Button + `.bindMenu()`，但丢失 HDS 沉浸光感

### 其他规则

- `LongPressGesture` 通过 `.gesture()` 附加，不与 `onClick` 混用
- `@Reusable` + `aboutToReuse(params)` — 用 `String()`/`Boolean()` 转换参数，禁 `as` 转型
- 可点击元素始终用 `Button()`，不用 `Text().onClick()`
- import 必须在文件最顶部，设计 token 统一从 `DesignTokens.ets` 引入
- `@StorageLink('key')` 需提前 `AppStorage.setOrCreate()` 初始化
- `wrapBuilder()` 参数必须是文件级 `@Builder function`，不能是 struct 内的 `@Builder` 方法。这在用 `openMenu` + `ComponentContent` 时是个硬限制
- `.bindSheet()` 的 `height` 不支持 `SheetSize.AUTO`，只能用 `MEDIUM` / `LARGE` 等枚举值

### Border 语法

```ets
// 错误
.border({ left: { width: 3 } })

// 正确
.border({ width: { left: 3 }, color: { left: Colors.accent } })
```

### LazyForEach

必须实现 `IDataSource` 的 `registerDataChangeListener` / `unregisterDataChangeListener`。

---

## API 协议参考

### 消息类型

| 方向 | 消息 |
|------|------|
| 客户端 → 服务端 | `list_agents`、`start`、`input`、`list_models`、`list_sessions`、`switch_model`、`set_mode`、`load_session`、`cancel`、`permission_response` |
| 服务端 → 客户端 | `server_info`、`session_started`、`agent_event`、`turn_ended`、`agent_list`、`model_list`、`session_list`、`permission_request`、`session_closed` |

`AcpUpdate.sessionUpdate` 渲染类型：`agent_message_chunk`、`agent_thought_chunk`、`tool_call`、`tool_call_update`、`plan`、`user_message_chunk`。

### 服务端 temp-client 注意

创建临时 ACP 进程时，如果 `cwd` 目录不存在，`spawn` 加 `shell: true` 会抛出误导性的 `cmd.exe ENOENT`（实际是 cwd 不存在）。先 `existsSync(cwd)` 检查，不存在则回退 `process.cwd()`。

### list_models 数据来源

opencode ACP 的 `createSession` 返回模型列表在 `configOptions` 而非 `models.availableModels`。从 `configOptions` 中提取 `category === "model"` 的 option 作为可用模型列表。

### 心跳

Bridge 收到 `{ type: "heartbeat" }` 必须回包；手机端收到任意服务端消息也应刷新连接活跃时间，避免空闲 45s 被误判断线。

---

## 构建与部署

### 无线调试

```powershell
# 构建 HAP
cd Anywhere_harmony
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default assembleHap

# 连接设备（IP:端口每次不同）
hdc tconn <IP>:<PORT>

# 部署
hdc -t "<IP>:<PORT>" install "entry/build/default/outputs/default/entry-default-signed.hap"

# 启动
hdc -t "<IP>:<PORT>" shell aa start -a EntryAbility -b com.anywhere.app
```

**诊断命令**：

```powershell
# WS 重连/后台任务日志
hdc -t "<IP>:<PORT>" shell hilog -x | Select-String -Pattern "WSClient|Heartbeat|reconnect|bg task"

# 截图
hdc -t "<IP>:<PORT>" shell snapshot_display -f /data/local/tmp/shot.jpeg
hdc -t "<IP>:<PORT>" file recv /data/local/tmp/shot.jpeg "D:\Development\Anywhere\app_test_picture\<name>.jpeg"

# UI 布局树（含 bounds）
hdc -t "<IP>:<PORT>" shell uitest dumpLayout -p /data/local/tmp/layout.json
hdc -t "<IP>:<PORT>" file recv /data/local/tmp/layout.json "D:\Development\Anywhere\app_test_picture"

# UI 交互（替代不存在的 hdc shell input）
hdc -t "<IP>:<PORT>" shell uitest uiInput click <x> <y>            # 点击
hdc -t "<IP>:<PORT>" shell uitest uiInput swipe <x1> <y1> <x2> <y2> [vel]  # 滑动
hdc -t "<IP>:<PORT>" shell uitest uiInput text <字符串>             # 在聚焦处输入
hdc -t "<IP>:<PORT>" shell uitest uiInput inputText <x> <y> <字符串> # 点击并输入
hdc -t "<IP>:<PORT>" shell uitest uiInput keyEvent Back             # 返回键
hdc -t "<IP>:<PORT>" shell uitest screenCap -p /data/local/tmp/shot.jpeg  # 截图
```

屏幕分辨率：1260×2844。设备 UDID：`2NP0224627054426`

### Bridge Server

```powershell
cd Anywhere
npm run build   # 编译 TypeScript → server/dist/
npm start       # 启动 server/dist/server.mjs
```

Bridge Server 监听 `:12138`，不指定 host（自动 IPv4+IPv6 双栈）。**不要**设 `host: "::"` 或 `"0.0.0.0"`，否则单栈。

---

## 文件结构

```
Anywhere/                             # 项目根（PC 端 + 手机端合一）
├── AGENTS.md                         # 开发指南
├── README.md
├── package.json                      # PC 端 Node.js 项目（Bridge Server）
├── tsconfig.json
├── server/                           # Bridge Server (Node.js + ACP)
│   ├── src/
│   │   ├── server.mts                # WS 服务主入口，监听 :12138
│   │   ├── relay.mts                 # Relay 客户端（连接 GCloud Relay Server）
│   │   ├── encrypted-channel.mts     # E2EE 加密通道
│   │   ├── host-identity.mts         # 主机身份 / 密钥
│   │   ├── prefs.mts                 # 持久化偏好
│   │   ├── session.mts               # 桥接会话管理
│   │   ├── temp-client.mts           # 临时 ACP 子进程
│   │   ├── acp-callbacks.mts         # ACP 事件回调 → WS 转发
│   │   ├── acp/
│   │   │   ├── client.mts            # ACP JSON-RPC 客户端
│   │   │   └── types.mts             # ACP 协议类型
│   │   ├── discovery/
│   │   │   ├── agents.mts            # Agent 发现
│   │   │   └── mcp-config.mts        # MCP 配置发现
│   │   └── handlers/                 # ACP 消息处理器
│   │       ├── auth.mts
│   │       ├── start.mts
│   │       ├── input.mts
│   │       ├── cancel.mts
│   │       ├── list-models.mts
│   │       ├── list-sessions.mts
│   │       ├── load-session.mts
│   │       ├── resume-session.mts
│   │       ├── close-session.mts
│   │       ├── set-mode.mts
│   │       ├── switch-model.mts
│   │       ├── set-config.mts
│   │       ├── permission.mts
│   │       └── close-session.mts
│   └── dist/                         # 编译产物（*.mjs）
│
├── relay/                            # GCloud Relay Server
│   ├── relay.mjs                     # Node.js 中继（当前使用）
│   ├── relay.py                      # Python 中继（备用）
│   ├── server.ts                     # TypeScript 源
│   ├── go.mod
│   ├── anywhere-relay                # Go 编译中继（Linux）
│   └── anywhere-relay.exe            # Go 编译中继（Windows）
├── wstest/                           # WebSocket 测试工具
│   ├── test-relay.cjs
│   └── package.json
├── prototype_picture/                # 产品设计原型
│   ├── Home.png
│   ├── Chat.png
│   ├── Project Detail.png
│   └── ...
├── app_test_picture/                 # 实机测试截图
│   ├── shot_home.jpeg
│   ├── chat_title_bar_native.jpeg
│   └── ...
├── docs/                             # 文档
│   ├── harmonyos-symbol-reference.md
│   └── ...
└── Anywhere_harmony/                 # HarmonyOS App（手机端）
    ├── entry/
    │   ├── src/main/ets/
    │   │   ├── pages/
    │   │   │   └── Index.ets         # 导航根、PagesMap、WS 生命周期、自动连接
    │   │   ├── feature/
    │   │   │   ├── home/
    │   │   │   │   ├── HomeView.ets      # 首页：host chips、Projects、Recent chats
    │   │   │   │   └── HostFilterBar.ets # 独立 host 在线状态组件
    │   │   │   ├── chat/
    │   │   │   │   ├── ChatView.ets      # 聊天壳层（NavDestination）
    │   │   │   │   ├── ChatPage.ets      # 消息流列表（LazyForEach）
    │   │   │   │   ├── ChatInputBar.ets  # 输入区 + Model chip → ConfigPanel
    │   │   │   │   └── NewSessionView.ets# 新建会话页
    │   │   │   ├── agent/
    │   │   │   │   └── AgentDetailView.ets
    │   │   │   ├── session/
    │   │   │   │   └── SessionDetailView.ets
    │   │   │   ├── workspace/
    │   │   │   │   ├── WorkspaceDetailView.ets
    │   │   │   │   ├── WorkspaceListView.ets
    │   │   │   │   └── WorkspaceDrawer.ets
    │   │   │   └── settings/
    │   │   │       └── SettingsView.ets
    │   │   │
    │   │   ├── common/
    │   │   │   ├── model/
    │   │   │   │   ├── ChatState.ets         # ChatStore 全局状态
    │   │   │   │   ├── WorkspaceInfo.ets     # WorkspaceStore / HostStore /...
    │   │   │   │   ├── HostState.ets         # HostRuntimeStore / HostPhase
    │   │   │   │   ├── DeviceAgentStore.ets  # Agent 缓存
    │   │   │   │   ├── MessageHandler.ets    # 消息路由
    │   │   │   │   ├── MessageData.ets       # 消息数据模型
    │   │   │   │   ├── NavParams.ets         # 导航参数
    │   │   │   │   └── AgentConfig.ets       # Agent 配置模型
    │   │   │   ├── websocket/
    │   │   │   │   ├── WSClient.ets          # WS 客户端 + 自动重连
    │   │   │   │   └── WSProtocol.ets        # 协议类型定义
    │   │   │   └── ui/
    │   │   │       ├── CustomIcon.ets        # SVG 图标组件
    │   │   │       ├── MessageCard.ets       # 消息气泡
    │   │   │       ├── ToolCallCard.ets      # 工具调用卡片
    │   │   │       ├── MarkdownRender.ets    # Markdown 渲染
    │   │   │       ├── ThinkingSection.ets   # Thinking 折叠区
    │   │   │       └── PlanView.ets          # Plan 进度视图
    │   │   │
    │   │   ├── services/
    │   │   │   ├── StorageService.ets        # Preferences 持久化
    │   │   │   └── AppPreferenceService.ets  # 语言 / 深浅色模式偏好
    │   │   │
    │   │   ├── constants/
    │   │   │   └── DesignTokens.ets          # 设计 token
    │   │   │
    │   │   └── vendor/                       # 第三方组件
    │   │       └── lv-md/                    # Markdown 解析引擎
    │   │
    │   └── src/main/resources/
    │       ├── base/media/                   # SVG 图标文件（33 个 ic_*.svg）
    │       ├── base/profile/                 # 配置文件
    │       └── base/element/                 # 主题元素
    │
    ├── build/                                # 构建产物
    └── oh_modules/                           # 鸿蒙依赖
```

---

## 踩坑记录

### HDS titleBar 菜单项不支持 bindMenu

`HdsNavDestination` 的 menu 项是配置对象，不是真实 ArkUI 组件。无法附加 `.bindMenu()`。

**方案**：
- 简单场景：直接用 `action` 回调
- 多选项：用 `NavDestination` + `.title(CustomBuilder)` 放真实 Button + `.bindMenu()`，但丢失 HDS 沉浸光感

### NavDestination + CustomBuilder 局限

`.title(builder: CustomBuilder)` 可自定义标题栏内容，放入带 `.bindMenu()` 的 Button，但无法使用 HDS 的 `systemMaterialEffect`（沉浸光感）。两者不可兼得。

### SheetSize.AUTO 不存在

`.bindSheet()` 的 `height` 不支持 `SheetSize.AUTO`。只能用 `SheetSize.MEDIUM` / `LARGE` 等枚举值。

### SymbolGlyph 图标名必须准确

`$r('sys.symbol.xxx')` 中 `xxx` 必须是系统符号库中存在的名称，否则编译报错。安全常用名：`plus`、`gearshape`、`folder`、`message`、`clock`、`chevron_right`、`ohos_trash`、`ohos_folder_badge_plus`。

### 后台限制

`backgroundTaskManager.requestSuspendDelay()` 是短时任务，不是长期后台保活。实机会出现 `bg task failed: {"code":"9900002"}` 表示短时任务校验失败。若要后台连接，只能用用户可感知的长时任务（通知栏），类型需符合官方校验（`DATA_TRANSFER`/`MULTI_DEVICE_CONNECTION`），不能按音乐软件的 `AUDIO_PLAYBACK` 思路无感保活。

### 网络排查

- Server 监听：`netstat -an | findstr "12138"` → 确认 `0.0.0.0:[::]` 双栈
- 防火墙：nvmw4 管理 Node（`D:\nvm4w\nodejs\node.exe`），不是 DevEco Studio 的 Node
- Clash：全局模式 → 关掉，或 bypass `192.168.0.0/16`、`10.0.0.0/8`
- Tailscale：手机热点 WiFi → IPv4/IPv6 均通；移动数据 → 仅 IPv4。始终用 IPv4 地址
- 排查链路：本机 WS 测试 → `hdc shell ping` → 防火墙 → 关 Clash
- 添加主机时 IPv6 URL 必须保留 `[ ]` 自动包能力
