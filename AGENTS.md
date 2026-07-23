# Nexus — HarmonyOS 远程 AI 编程助手客户端

## 项目概述

Nexus（原 Anywhere）是一个 HarmonyOS App，通过 WebSocket 连接到 PC 端 Bridge Server，Bridge Server 再通过 ACP (Agent Client Protocol) 协议与 AI 编程 Agent 通信。

> 手机端有**两套实现并存**：`Anywhere_harmony/`（ArkTS，参考实现）与 `anywhere_flutter/`（Flutter，A 路线 `flutter build hap`，当前活跃开发与视觉重构主战场）。PC 端 Bridge Server 共用 `server/`。软件官方名称已全面更新为 **Nexus**。

### 连接方式

**默认：直连（LAN / 热点）** — 手机和 PC 在同一局域网或手机连接 PC 热点时。无需中继。

**可选：Relay 中继** — 通过设置环境变量 `ANYWHERE_RELAY_URL` 启用。适合远程访问场景。中继服务器参考 `relay/` 目录。

```
手机 (HarmonyOS / Nexus App)                   PC (Node.js Bridge)
┌──────────────┐        直连 WS (LAN)           ┌─────────────────────┐
│ Phone App    │ ←───────────────────────────→ │ server/dist/server  │
│ (Nexus)      │       ws://192.168.x.x:12138  │ .mjs + ACP Agent    │
└──────────────┘                                └─────────────────────┘
                                                         │
                                                ┌───────┴───────┐
                                                │ OpenCode       │
                                                │ Claude Agent   │
                                                │ codex-acp      │
                                                │ ...            │
                                                └───────────────┘
```
（可选 Relay 模式）：手机 → Relay Server → Bridge，当 `ANYWHERE_RELAY_URL` 已设置时使用。
```

---

## 工作流程

1. 用户输入
2. 分析用户输入，使用codegraph MCP获取上下文，分析代码
3. 充分计划，然后将任务拆分为多个子任务，调用子代理处理，子代理编写完代码后要让他们用deveco-mcp自己检查是否有arkts语法错误
4. 收集并review子代理的结果，先使用deveco-mcp检查arkts语法，然后再使用devecocli构建项目，进行修正，整合为最终结果，然后用devecocli部署到手机端测试
5. 测试无误后进行git提交

## 关键工具
1. 用 `deveco-cli` skill 查鸿蒙官方文档、连接手机，部署项目。不确定就查文档！
2. Codegraph MCP 用于理解代码结构。当前 MCP server 带 watcher，通常会自动 sync；若怀疑索引过期，用 `node D:/Development/codegraph-arkts/dist/bin/codegraph.js status .` 确认，必要时再手动 `sync .`，不再要求每次提交后固定执行 `index .`。

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
### 动画：淡入淡出 — `TransitionEffect.OPACITY` + `springMotion(0.6, 0.85)`。无 translation/spring 过冲/staggered delay。
  - 页面切换：`TransitionEffect.OPACITY` + springMotion
  - 消息卡片：`TransitionEffect.OPACITY` + springMotion
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

## ACP Agent 注册表与管理

### 架构变更（Registry + Installed Agents）

从 PATH 扫描模式迁移到 **Registry + Installed Agents** 模式，参考 Zed 的 `agent_registry_store` + `agent_server_store` 设计。

### 核心概念

| 组件 | 文件 | 说明 |
|------|------|------|
| Registry | `server/src/registry/agents.json` | 内置 agent 列表（~70 个），含 ID、名称、启动命令和参数 |
| Registry 加载器 | `server/src/registry/registry.mts` | 加载 registry、按 ID 查 agent、解析启动命令 |
| Installed Store | `server/src/agents-store.mts` | 管理 `~/.anywhere/installed-agents.json`，记录用户显式安装的 agent |
| Agent 发现 | `server/src/discovery/agents.mts` | **已重写** — 从 installed store + registry 返回 agent 列表，不再扫 PATH |
| Agent 管理页 | `feature/agent/AgentManageView.ets` | 客户端 UI，分"商店"和"已安装"两 Tab |

### 数据流

```
┌─────────────────────────────────────────────────────┐
│  Server                                              │
│                                                      │
│  registry/agents.json  ─→ registry.mts              │
│       (内置 70 个 agent)     │                       │
│                              ▼                       │
│  agents-store.mts  ──────────────────→ installed     │
│       (~/.anywhere/installed-agents.json)   agents   │
│                              │                       │
│                              ▼                       │
│  discovery/agents.mts  ─── list_agents ──→ 客户端   │
│       (从 installed + registry 组装)                 │
│                                                      │
│  server.mts ─── list_registry_agents ──→ 客户端     │
│              ─── install_agent / uninstall_agent     │
│              ─── install_custom_agent                │
└─────────────────────────────────────────────────────┘
```

### 安装流程

1. 用户在设置页 → 主机详情 → **管理 Agent**
2. **商店 Tab**：浏览 registry 中所有可用 agent，点击 [安装]
3. **已安装 Tab**：查看已安装 agent，可卸载或添加自定义 agent
4. 安装后，server 的 `list_agents` 返回该 agent，用户可在聊天中选择使用

### Registry JSON 格式

```json
{
  "version
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
| 客户端 → 服务端 | `list_agents`、`list_registry_agents`、`install_agent`、`uninstall_agent`、`install_custom_agent`、`start`、`input`、`list_models`、`list_sessions`、`switch_model`、`set_mode`、`load_session`、`cancel`、`permission_response` |
| 服务端 → 客户端 | `server_info`、`session_started`、`agent_event`、`turn_ended`、`agent_list`、`registry_agents_list`、`install_agent_done`、`uninstall_agent_done`、`model_list`、`session_list`、`permission_request`、`session_closed` |

**Agent 管理消息**：
- `list_registry_agents` → server 返回 `registry_agents_list`（含所有 registry agent 元数据）
- `install_agent { agentId }` → server 写入 installed 配置，返回 `install_agent_done { agentId, ok }`
- `uninstall_agent { agentId }` → server 从 installed 移除，返回 `uninstall_agent_done { agentId, ok }`
- `install_custom_agent { command, args, name }` → 安装自定义 agent（不在 registry 中的命令）

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

### 设备发现（热点模式）

当手机连接 PC 热点（`192.168.137.1`）时：
- `arp -a -N 192.168.137.1` 查看动态条目，唯一动态 IP 即为手机
- 常用无线调试端口：`46715`（多次连接未变）
- 完整连接命令：`hdc tconn 192.168.137.159:46715`

屏幕分辨率：1260×2844。设备 UDID：`2NP0224627054426`

### Bridge Server

```powershell
cd Anywhere
npm run build   # 编译 TypeScript → server/dist/
npm start       # 启动 server/dist/server.mjs
```

Bridge Server 监听 `:12138`，不指定 host（自动 IPv4+IPv6 双栈）。**不要**设 `host: "::"` 或 `"0.0.0.0"`，否则单栈。

---

## Flutter OHOS 客户端（anywhere_flutter/）

除 ArkTS 版 `Anywhere_harmony/` 外，另有 **Flutter 重写的鸿蒙客户端** `anywhere_flutter/`（A 路线：`flutter build hap`）。当前活跃开发集中在此目录。ArkTS 版仅作参考实现（如 resume 渲染、ConfigPanel 行为可对照 `Anywhere_harmony/`）。

### 工具链

| 项 | 值 |
|----|----|
| Flutter SDK | `D:\Development\flutter_flutter`（带 ohos 支持的 fork，Dart 3.6.2+） |
| 工程根 | `anywhere_flutter/`；OHOS 工程子目录 `anywhere_flutter/ohos/` |
| DevEco | `D:\DevEco Studio`（提供 hdc / ohpm / hvigor 引擎） |
| 调试设备 | HUAWEI Pura 70 Pro，UDID `2NP0224627054426`，屏幕 1260×2844 |

### 编译与部署

> ⚠️ `flutter build hap` 的 hvigor-engine 有 ohpm BATCH RECURSION bug，**不可用**。当前必须用 `devecocli` 构建。

#### 前置：清理 `@ohos/hypium`

`ohos/oh-package.json5` 中 `@ohos/hypium` devDependency 会触发 ohpm 递归依赖崩溃。已从 `devDependencies` 移除。若将来 DevEco 重新添加，需再次移除。

#### 构建

```powershell
# NODE_OPTIONS="" 是必须的！WorkBuddy 的 --use-system-ca 与 DevEco 自带旧 Node 冲突
Set-Location "D:\Development\Anywhere\anywhere_flutter\ohos"
$env:NODE_OPTIONS=""
devecocli build --build-mode debug
# 产物：ohos/entry/build/default/outputs/default/entry-default-signed.hap
# 构建耗时：约 2 分 38 秒
```

Bash 等效：
```bash
cd "D:/Development/Anywhere/anywhere_flutter/ohos"
NODE_OPTIONS="" devecocli build --build-mode debug
```

##### ⚠️ 构建失败自恢复（必读）

`devecocli build` 在 hvigor sync 阶段**偶发** ohpm 失败，报错形如：
```
> hvigor ERROR: 00306053 Specification Limit Violation
Error Message: ohpm install failed.
```
或 `Recursion Count=234, Stack Usage=90%`（BATCH RECURSION）。这不是代码问题，是 ohpm 缓存状态损坏导致的**偶发**故障。按以下顺序复位即可，**不要改代码**：

```bash
cd "D:/Development/Anywhere/anywhere_flutter/ohos"
# 1. 先手动跑一次 ohpm install，把依赖装好（这一步通常能成功）
"D:/DevEco Studio/tools/ohpm/bin/ohpm" install --all
# 2. 清理 hvigor/依赖缓存，重置异常状态
NODE_OPTIONS="" devecocli build clean
# 3. 重新构建（clean 后基本都能过）
NODE_OPTIONS="" devecocli build --build-mode debug
```

> 经验：直接 `devecocli build` 撞到 00306053 时，单纯重试往往还会失败；**必须 `build clean` 复位后再 build**。若仍失败，删除 `ohos/oh_modules` 与 `ohos/.hvigor` 目录后从步骤 1 重来。

#### 部署

```powershell
# devecocli 必须在 ohos/ 下执行（查找 build-profile.json5）
Set-Location "D:\Development\Anywhere\anywhere_flutter\ohos"
$env:NODE_OPTIONS=""
devecocli run --device "2NP0224627054426" --skip-build
# 首次安装 / 签名变更时加 --uninstall
```

#### 日志

```powershell
# 崩溃 / 错误日志
hdc -t "2NP0224627054426" shell hilog -x | Select-String "FATAL|com.anywhere.app"
# 启动后只会有无害的 vsync voting 警告
```

### 架构要点

- **状态/数据**：`lib/providers/chat_provider.dart`（ACP 事件中枢 `_handleAgentEvent`）、`lib/models/ws_protocol.dart`（`AcpUpdate` 解析 + `_extractText`）、`lib/models/message_data.dart`（`MessageData`，`toolKind` 字段，`id` 为 `final` 经构造函数传入）。
- **UI**：`lib/widgets/tool_call_card.dart`（可折叠工具卡片，运行中自动展开）、`lib/widgets/message_bubble.dart`、`lib/pages/chat_page.dart`（ListView 加 `key: ValueKey(msg.id)`）、`lib/pages/home_page.dart`、`lib/pages/workspace_detail_page.dart`。
- **聊天顶栏（`chat_page.dart` `_buildTopBar`）**：三个独立圆角胶囊、固定高度 42 —— ① 返回键 `<`（单独胶囊）；② 对话标题 + 状态点 + 主机名 + 工作区名（Expanded 胶囊，左对齐）；③ 历史记录（时钟）+ 文件（`···`）两个图标（一个胶囊）。历史记录点击弹底部 sheet 占位；文件点击从右侧滑出文件管理器面板（功能待实现）。右侧图标功能均未实现，仅 UI 壳。
- **文件管理器面板**：**不用 `Scaffold.endDrawer`**（见下方踩坑），改为 `body: Stack` 内的 `_buildFileOverlay`（遮罩 `AnimatedOpacity` + 面板 `AnimatedPositioned` 右滑）由 `setState(_fileDrawerOpen)` 控制开关。
- **连接/持久化**：`lib/services/ws_client.dart`（WS + ACP 调试 dump 到沙箱 `anywhere_acp_debug.jsonl`）、`lib/services/storage_service.dart`（**OHOS 沙箱绝对路径** `/data/storage/el2/base/haps/entry/files/.anywhere_store.json`，不用 `path_provider`——OHOS 未实现且当前目录无写权限）、`lib/main.dart`（`_probeAllHosts()` 启动时探测已配对主机并自动连接首个在线主机）。
- **ACP 渲染类型**：`user_message_chunk` / `agent_message_chunk` / `tool_call` / `tool_call_update` / `session_started` / `turn_ended`。

### 已知坑（Flutter 版）

- **`Scaffold.endDrawer` 会让 `AppBar` 自动注入 ≡ 汉堡按钮**：只要 `Scaffold` 设了 `endDrawer`，`AppBar` 会**无条件**在右上角追加一个 `Icons.menu`（≡）按钮来开抽屉。给 `AppBar` 设 `actions: const []` 没用（Flutter 是把该按钮 append 到 `actions` 列表末尾，空列表也拦不住）；`automaticallyImplyLeading: false` 只抑制左侧 leading 抽屉键，不影响 endDrawer 的 ≡。聊天页因此**不用 `endDrawer`**，改用 `body: Stack` + 遮罩 + `AnimatedPositioned` 自定义右侧滑出面板（`_buildFileOverlay` / `_buildFilePanel`），由图标 `setState` 控制开关。
- **`tool_call_update` 的 `content` 是 `[{type:"content", content:{text:...}}]` 数组**（不是 `type:"text"`）。`_extractText` 必须解析 `type:"content"`/`diff`/`terminal`，否则 `toolContent` 为空 → 工具卡片不可展开（只剩一个 √）。
- **resume 走 `session_started`**（非 `resumed_session`），且 `resumed_session` 时 `turnActive=false` 走 `input`。
- **`list_sessions` 必须带 `agent` + `cwd` 参数**，否则返回空。
- **服务器不发 `tool_call_end`**：turn 结束时 `_finishRunningTools()` 兜底把 `running`/`in_progress` 标记 `completed`，避免卡片卡转圈。
- **更名与中英文资源**：软件全面更名为 **Nexus**。桌面应用图标 Label 在 HarmonyOS 中由 `AppScope/resources/base/element/string.json` 中的 `app_name` 与 `entry/.../zh_CN/element/string.json` 及 `en_US/.../string.json` 中的 `EntryAbility_label` 共同控制。覆盖安装时系统桌面存在强缓存，需先 `hdc uninstall com.anywhere.app` 才能刷出最新的桌面名称 **Nexus**。
- **品牌 Icon**：采用纯白 Squircle 底座 + 3D 立体斜切面 ASCII 字符终端艺术 **Block N** 图腾，兼具黑白极简与硬核 Console 代码范。矢量资源保存在 `entry/src/main/resources/base/media/nexus_3d_ascii_n.svg`。
- **主机名优先**：全量界面（Chat/Home/FilterBar/Settings/Workspaces）隐去技术性 `host_...` UUID 字符串，优先渲染 Friendly 主机名 `device.name`。
- **非阻塞启动与防崩溃**：`main.dart` 启动时 `runApp()` 立即执行，避免 `await _probeAllHosts` 阻塞首帧渲染导致白屏；`SettingsPage` 中 `Dismissible` Key 增加 `index` 锚定防 DuplicateKey 崩溃。
- **持久化用 OHOS 沙箱绝对路径**（见上），不要改用 `path_provider`。

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
├── anywhere_flutter/                 # Flutter OHOS 客户端（手机端，A 路线 flutter build hap）
│   ├── lib/
│   │   ├── main.dart                 # 入口 + _probeAllHosts 启动探测已配对主机
│   │   ├── providers/chat_provider.dart   # ACP 事件中枢 _handleAgentEvent
│   │   ├── models/ws_protocol.dart        # AcpUpdate 解析 + _extractText
│   │   ├── models/message_data.dart       # MessageData（toolKind 字段，id 为 final）
│   │   ├── widgets/tool_call_card.dart    # 可折叠工具卡片（运行中自动展开）
│   │   ├── widgets/message_bubble.dart
│   │   ├── pages/chat_page.dart / home_page.dart / workspace_detail_page.dart
│   │   └── services/ws_client.dart / storage_service.dart
│   ├── ohos/                         # OHOS 工程（hvigorw 由 ohpm install 生成）
│   └── ohos/entry/build/default/outputs/default/entry-default-signed.hap  # devecocli 构建产物
└── Anywhere_harmony/                 # HarmonyOS App（手机端，ArkTS 参考实现）
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
- Tailscale：手机热点 WiFi → IPv4/IPv6 均通；移动数据 → 仅 IPv4。始终用 IPv4 地址
- 排查链路：本机 WS 测试 → `hdc shell ping` → 防火墙 → 关 Clash
- 添加主机时 IPv6 URL 必须保留 `[ ]` 自动包能力

### Flutter OHOS 构建：devecocli 替代 flutter build hap

`flutter build hap`（A 路线）的 hvigor-engine 在处理 ohpm 依赖时有 **BATCH RECURSION** bug（`Recursion Count=234, Stack Usage=90%`），稳定不可用。**改用 `devecocli build` 在 `ohos/` 目录下构建**，其 hvigor 可正常完成 ohpm install → sync → build 全流程。

### Flutter OHOS 构建必须清除 NODE_OPTIONS

WorkBuddy 设置了 `NODE_OPTIONS=--require="..." --use-system-ca`，DevEco Studio 自带的旧版 Node.js 不支持 `--use-system-ca`，导致 ohpm 静默失败（`exit code 9`）。**所有 `devecocli build` / `devecocli run` 命令前必须先 `$env:NODE_OPTIONS=""`**（PowerShell）或 `NODE_OPTIONS=""`（Bash）。

### Flutter OHOS 构建必须设置 OHPM_HOME

`flutter build hap`（A 路线）内部执行 `ohpm install` 来拉取 hvigor 引擎并生成 `anywhere_flutter/ohos/hvigorw`。若 `OHPM_HOME` 未指向 DevEco 的 ohpm（`D:\DevEco Studio\tools\ohpm`），`ohpm install` 静默失败 → 找不到 hvigorw/引擎 → 构建卡在 `Running Hvigor task assembleHap...` 后无输出或直接失败。**任何 Flutter OHOS 构建命令前务必先设好 `OHPM_HOME`**（PowerShell：`$env:OHPM_HOME="D:\DevEco Studio\tools\ohpm"`；Bash：`export OHPM_HOME="D:\DevEco Studio\tools\ohpm"`）。**注意**：当前已改用 `devecocli build`（不需 OHPM_HOME），但若将来恢复 `flutter build hap`，此条依然适用。

### @ohos/hypium 导致 ohpm 递归崩溃

`ohos/oh-package.json5` 的 `devDependencies` 中 `@ohos/hypium` 会触发 ohpm install 的 BATCH RECURSION 错误。已移除该依赖。若 DevEco Studio 自动重新添加，需再次删除。

### devecocli 必须在 ohos/ 目录执行

`devecocli run` 会查找 `build-profile.json5`，必须在 `anywhere_flutter/ohos/`（或 B 路线的 `harmonyos/<module>/.ohos`）目录下运行，否则报 `Not in a valid project directory`。

### devecocli build 偶发 ohpm 00306053 失败

`devecocli build` 在 hvigor sync 阶段会**偶发**失败，报错 `00306053 Specification Limit Violation / ohpm install failed`（与 `BATCH RECURSION` 同源，都是 ohpm 缓存状态损坏）。这是**偶发**故障，非代码问题，纯粹重试往往无效。

**必做复位流程**（见上方「编译与部署 → 构建 → 构建失败自恢复」）：
1. 手动 `ohpm install --all` 装好依赖；
2. `devecocli build clean` 清理缓存、重置异常状态；
3. 再 `devecocli build --build-mode debug`。

仍失败则删除 `ohos/oh_modules` 与 `ohos/.hvigor` 后从步骤 1 重来。

### ArkTS 与 Flutter 双客户端并存

项目有两套手机端实现：`Anywhere_harmony/`（ArkTS，参考实现）与 `anywhere_flutter/`（Flutter，当前活跃开发）。改 Flutter 端时如需对照 resume 渲染、ConfigPanel、状态管理等行为，参考 `Anywhere_harmony/`；但两者代码互不直接共享，改动需分别落地。
