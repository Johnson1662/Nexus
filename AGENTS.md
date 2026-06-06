# Anywhere — HarmonyOS 远程 AI 编程助手客户端

## 永远用中文回答；需要解释时，用中文给出简要思路与结论，不输出隐藏思考链

## 使用 hmdev-cli skill 查鸿蒙官方文档、构建部署项目

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
手机 App 与 PC Bridge 通过 **Relay Server**（Node.js `relay.mjs`，运行在 GCloud VM）进行 hostId 配对双向转发。不再经过 Cloudflare。

---

## ⚠️ 网络连接问题排查

**Server 监听:** `server/dist/server.mjs` 使用 `new WebSocketServer({ port: 12138 })`，不指定 host 自动 IPv4+IPv6 双栈。**不要**设 `host: "::"` 或 `"0.0.0.0"`，否则单栈。

**IPv6 URL:** 添加主机入口已并入首页右上三点菜单，手动链接时必须继续保留 IPv6 自动包 `[ ]` 的 URL 归一化能力。**防火墙:** nvmw4 管理 Node (`D:\nvm4w\nodejs\node.exe`)，不是 DevEco Studio 的 Node。**Clash:** 全局模式 → 关掉或在 clash 中 bypass `192.168.0.0/16`、`10.0.0.0/8`。

**Tailscale:** 手机热点 WiFi → IPv4/IPv6 均通；移动数据 → 仅 IPv4。始终用 Tailscale IPv4 地址。

**排查:** `netstat -an | findstr "12138"` → 确认监听 `0.0.0.0:[::]` → 本机 WS 测试 → `hdc shell ping` → 防火墙 → 关 clash。

**心跳/重连:** 手机端 `WSClient` 的 watchdog 不能只依赖业务期间 heartbeat。Bridge 收到 `{ type: "heartbeat" }` 必须回包；手机端收到任意服务端消息也应刷新连接活跃时间，避免空闲 45s 被误判断线。用 `hdc -t <device> shell hilog -x | Select-String -Pattern "WSClient|Heartbeat|reconnect|bg task"` 查实机证据。

**后台限制:** `backgroundTaskManager.requestSuspendDelay()` 是短时任务，不是长期后台保活；实机出现 `bg task failed: {"code":"9900002"}` 表示短时任务校验失败。若要后台持续连接，只能尝试用户可感知的长时任务（通知栏），类型需符合官方校验（如 `DATA_TRANSFER`/`MULTI_DEVICE_CONNECTION`），不能按音乐软件的 `AUDIO_PLAYBACK` 思路无感保活。

## ⚠️ Golden Rule: 优先使用原生 ArkUI 组件

优先使用 ArkUI 内置组件（SideBarContainer、bindSheet、Navigation 等），而非手写浮层/弹窗。原生组件自带系统级行为：动画、无障碍、多渲染器生命周期和系统升级兼容。在 `animateTo()` 中包裹状态变更以确保平滑过渡。

## 关键设计决策

### 视觉设计
- **风格：** ChatGPT / Linear 混合 — 黑白灰单色调，大留白，卡片阴影无边框
- **消息气泡：** 用户消息黑底白字 (`Colors.foreground` 背景)，Agent 消息全宽无背景
- **字体：** 正文 HarmonyOS Sans，品牌标题衬线体 (`fontFamily('serif')`)
- **空状态：** 图标 + 粗标题 + 引导副标题 + 黑底白字按钮 CTA
- **按压反馈：** 所有可点击卡片 `scale(0.97)` + `animation(duration:100)` on TouchDown
- **交错入场：** Agent/Session 列表项 `index * 50~60ms` delay + `TransitionEffect.OPACITY + translateY`

### 图标 — SymbolGlyph

使用 `SymbolGlyph($r('sys.symbol.xxx'))`。`fontColor` 必须是数组格式：`fontColor([...])`。

常用：`house`/`house_fill`、`person_2`/`person_2_fill`、`clock`、`gearshape`、`chevron_left`、`ellipsis_message`、`person_badge_plus`、`vpn_key`、`wifi`、`externaldrive`、`square_grid_2x2`。完整列表见 `docs/harmonyos-symbol-reference.md`。`fontColor` 必须是数组：`fontColor([Colors.accent])`，不是 `fontColor(Colors.accent)`。

参考：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

### 自定义图标 — SVG 文件 + Image.fillColor

当系统符号库没有语义匹配的图标时，用 SVG 文件代替。**严禁使用 `Path().commands()` 绘制自定义图标** — ArkUI `Path` 的坐标是绝对 px，无 `viewBox` 缩放机制，任何尺寸的坐标都会在高分屏上变成极小像素点。

**正确做法**：
1. 创建 `<svg viewBox="0 0 24 24">` 文件，放到 `entry/src/main/resources/base/media/` 目录（例如 `ic_stop.svg`）
2. 用 `Image($r('app.media.ic_xxx')).fillColor(color)` 加载 — ArkUI `Image` 组件原生支持 SVG viewBox 缩放
3. 通过 `CustomIcon` 组件统一调用：`CustomIcon({ name: 'stop', iconSize: 28, color: Colors.error })`

现有的自定义 SVG 图标：`ic_stop`、`ic_warning`、`ic_edit`、`ic_wrench`、`ic_progress`、`ic_new_chat`、`ic_thinking`、`ic_check`。


### 导航与路由
- `Navigation(NavPathStack)` + `.navDestination(this.PagesMap)` — `PagesMap` 是 `@Builder` 引用。
- 当前移动端壳层不再使用底部 5 Tab。首页为主入口，底部只保留 Search / New chat 操作条。
- `New chat` 必须直接进入聊天页，不再展示 “What should we work on” 中间页。
- 添加主机入口已并入首页右上三点菜单：`Add host` → `Scan QR` / `Link manually`，配对成功后立即拉取并缓存 agent 列表。
- `OnboardingView.ets` 已删除，不要恢复该页面；主机管理和设置通过首页菜单/聊天页菜单进入。
- 聊天页顶部结构：左返回、中间 workspace 胶囊、右三点；下方 `Agent` / `Model` / `Mode` 三选择器。先选 Agent，才能选 Model；Model 默认上一次使用项。
- **子页面路由**（`navStack.pushPath`）: `agentDetail` / `sessionDetail` / `workspaceDetail` / `settings` / `host-manage`。
- **跨页面参数传递**：通过 `AppStorage`（如 `selectedDeviceIndex`）— 不用 param 对象（ArkTS `@Builder` 限制）。
- 每个目的地必须是根节点为 `NavDestination()` 的 `@Component`。
- 启用 `NavigationMode.Stack`。

### 状态管理
- Model 类用 `@ObservedV2`/`@Trace`（V2）
- UI 组件用 `@Component`/`@State`/`@Prop`（V1）
- 全局单例：`ChatStore`、`WorkspaceStore`、`HostStore`
- 持久化：`StorageService`（基于 `@kit.ArkData` preferences）
- 跨组件状态：`AppStorage`（如 `serverUrl`、`lastAgent`）

### ChatStore 关键字段
- `messages: MessageData[]` — 完整消息列表
- `streamingThinking: string` / `streamingText: string` — 流式 thinking 独立字段（不在 LazyForEach 中，避免重渲染闪烁）
- `turnActive: boolean` / `bridgeSessionId: string` / `acpSessionId: string`
- `connected: boolean` / `currentDeviceId: string` — 当前连接设备标识（server_info 设置，断开清空）
- `sessions: ServerSession[]` / `models: ModelItem[]` / `modes: ModeItem[]` / `planEntries: PlanEntry[]`
- `selectedAgentName: string` / `agentType: string` — 当前选中的 ACP Agent
- `lastUsage: UsageInfo | null` — turn_ended 时的 Token 用量统计
- `reconnectPhase: string` / `reconnectAttempt: number` — 断线重连状态
- `pendingPermission: PendingPermission | null` — 当前权限请求
- `availableCommands: AvailableCommand[]` — 斜杠命令补全
- `configOptions: ConfigOption[]` — Agent 配置项

**LazyForEach key 必须用 `msg.id + msg.content.length`**，不能只用 `msg.id`。流式传输时 content 在变化，只用 id 不会触发 UI 更新。

### Markdown 渲染
使用 `@luvi/lv-markdown-in` (v3.4.1)。`turnActive` 期间用纯 `Text()`，`turn_ended` 后切换 `MarkdownRender`。

### 工作区管理
`SideBarContainer` 侧边栏 + `WorkspaceStore` 全局单例。工作区按设备名持久化（同 PC 的所有 IP 共享），`getWorkspaceScopes()` 提供回退链。

### 设备分组 (HostStore)
`server_info` 消息按 hostname 合并 IP 为 `DeviceEntry[]`。`connectBest(urls[])` 并行探测选最低延迟。兼容旧 `HostInfo[]` 格式自动迁移。

### 缓存结构与刷新策略
- 缓存层级按 `host -> workspace -> agent -> provider -> model/mode/session` 思考和命名，避免把跨主机、跨工作区的数据混在一起。
- Agent 列表：每天打开 app 时对已配对主机请求一次，之后读 `DeviceAgentStore` / preferences 缓存；用户可在 Agent 列表或菜单手动刷新。
- Model / Mode 列表：与 workspace + agent 绑定，第一次进入某工作区并选定 agent 时请求，后续优先读缓存；切换 agent 后才能切换 model。
- Session 列表：与 workspace 绑定，第一次打开工作区请求并缓存；除非新建/加载会话、手动刷新或后端推送变化，不要每次进入页面都重新加载。
- 启动时自动向已配对主机发起连接请求，但失败只进入重连/可手动刷新状态，不阻塞首页渲染。

### 自动重连
指数退避 (1s → 2s → 4s → ... → 30s 上限)。不要宣称普通 UIAbility 能长期后台保活；后台恢复应依赖快速重连 + `sync_request`/消息游标补齐。

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
## 构建与部署

---



### 无线调试（当前设备）

```powershell
# 构建
cd Anywhere_harmony
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default assembleHap

# 连接（IP:端口每次可能不同；2026-06-06 实测端口如下）
hdc tconn 192.168.137.11:46715

# 部署
hdc -t "192.168.137.11:46715" install "entry/build/default/outputs/default/entry-default-signed.hap"
# 启动
hdc -t "192.168.137.11:46715" shell aa start -a EntryAbility -b com.anywhere.app

# 诊断 WS 重连/后台任务
hdc -t "192.168.137.11:46715" shell hilog -x | Select-String -Pattern "WSClient|Heartbeat|reconnect|bg task"

# 必要时抓实机图
hdc -t "192.168.137.11:46715" shell snapshot_display -f /data/local/tmp/shot.jpeg
hdc -t "192.168.137.11:46715" file recv /data/local/tmp/shot.jpeg "D:\Development\Anywhere\shot.jpeg"
```

设备 UDID: `2NP0224627054426`

### Bridge Server

```powershell
cd Anywhere
npm run build        # 编译 TypeScript → server/dist/
npm start            # 启动 server/dist/server.mjs
```

---

## 文件结构速查

- `Anywhere_harmony/entry/src/main/ets/pages/Index.ets` — 导航根、PagesMap、WS 生命周期、启动自动连接已配对主机。
- `feature/home/HomeView.ets` — 原型风格首页、host chips、Projects、Recent chats、Add host 菜单。
- `feature/chat/ChatView.ets` / `ChatPage.ets` / `ChatInputBar.ets` — 聊天标题栏、消息流、输入区、权限浮层。
- `feature/agent` / `feature/session` / `feature/workspace` / `feature/host` / `feature/settings` — 对应详情页与管理页。
- `common/model/ChatState.ets`、`WorkspaceInfo.ets`、`DeviceAgentStore.ets`、`MessageHandler.ets`、`NavParams.ets` — 全局状态、缓存、消息路由、导航参数。
- `common/websocket/WSClient.ets` / `WSProtocol.ets` — WS 客户端、自动重连、协议类型。
- `services/StorageService.ets`、`constants/DesignTokens.ets`、`common/ui/*` — preferences 持久化、设计 token、通用 UI 组件。

---

## API 协议参考

### 消息类型速查

客户端 → 服务端：`list_agents`、`start`、`input`、`list_models`、`list_sessions`、`switch_model`、`set_mode`、`load_session`、`cancel`、`permission_response`。

服务端 → 客户端：`server_info`、`session_started`、`agent_event`、`turn_ended`、`agent_list`、`model_list`、`session_list`、`permission_request`、`session_closed`。

`AcpUpdate.sessionUpdate` 渲染类型：`agent_message_chunk`、`agent_thought_chunk`、`tool_call`、`tool_call_update`、`plan`、`user_message_chunk`。
