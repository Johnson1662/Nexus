# Nexus Roadmap & TODO

## 已经完成 (Completed)

### 架构与服务端深模块
- [x] **统一 Session ID 架构**：移除 `bridgeSessionId` (`acp-timestamp-...`)，全链路（Flutter App → WebSocket 协议 → Node.js Bridge → ACP Agent）统一使用 Agent 原生 `sessionId`（UUID / `ses_...`）。
- [x] **多 Session 后台并发与进程池**：实现 `SessionManager` 进程池，支持后台保留 active ACP 子进程（最多 5 个 LRU 淘汰，15 分钟闲置清理），切换会话或切出 App 时长任务不被中断。
- [x] **事件缓冲与回放 (Message Buffer)**：`SessionManager` 维护滚动消息缓冲区，客户端重连/载入会话时通过 `lastMessageId` 游标平滑补齐遗漏事件。
- [x] **实时状态检测引擎 (`SessionStatusWatcher`)**：重构 watcher 为深模块类，支持 `computeSessionDiff` 纯函数计算与 `mergeSessionStatus` 内存 `turnActive` 覆盖，向手机端广播 `{ type: "session_status_update" }`。
- [x] **Agent 注册表服务 (`AgentRegistryService`)**：收敛 Agent 发现、安装/卸载、多 Agent 聚合查询、12 秒超时保护与 Windows 路径规范化。
- [x] **自动归并同 Host 节点**：`HostStore` 自动按 `hostId` 与 `hostname` 去重合并多 IP 候选地址（`urls` 数组），解决多网卡/热点 IP 导致的重复主机记录问题。

### 客户端 (Flutter OHOS) 与 UI
- [x] **会话恢复工作区 (`cwd`) 自动归位**：`loadSession` 自动提取目标会话原本绑定的 `cwd` 路径并更新当前工作区，彻底修复跨工作区 resume 时 OMP 抛出 `Internal error (ACP session not found)` 的问题。
- [x] **消除 `session_status_update` 死循环**：修正 Flutter 端状态更新比对逻辑，不再将其他工作区的 Status 更新误判为 `hasNewSession`，消除无限发送 `list_sessions` 的死循环。
- [x] **思考过程与工具卡片视觉对齐**：`ThinkingSection` 的展开箭头统一移至右侧，方向调整为“闭合朝右、展开朝下”，并加上与 `ToolCallCard` 相同的浅色外框。
- [x] **输入栏与 ConfigPanel 升级**：Model 胶囊 Chip 内嵌在输入框左下角，ConfigPanel 支持 AnimatedSwitcher 视图切换与 Agent 商店一键安装。

---

## 🏆 鸿蒙应用创新赛道 Kit 融合方案 (HarmonyOS 6+ 集成)

### 架构设计：Flutter UI + ArkTS 原生 Kit 混合架构

`nexus_flutter` 界面保持跨平台的高效 UI 迭代，鸿蒙系统级特有能力通过 `MethodChannel` 与 `nexus_flutter/ohos/entry/src/main/ets` 原生 ArkTS 代码通信，直接调用 HarmonyOS 原生 Kit SDK。

```text
Flutter (Dart 代码) ── MethodChannel ──> ArkTS (nexus_flutter/ohos/entry) ──> 鸿蒙系统 Kit
```

### 推荐融合 Kit 方案

#### 1. 实况窗 (Live View Kit) —— 锁屏/状态栏实时看 Agent 进度
- **定位**：AI 智能化体验 / 实时状态感知
- **目标**：用户把手机平放桌上，瞥一眼锁屏或状态栏左上角胶囊，就能看到 remote AI 的实时进度，无需解锁进 App。
- **功能设计**：
  - **状态栏胶囊**：显示小胶囊 `[🟢 AI 编写中 65%]`。
  - **展开卡片**：显示 Agent 名称、当前执行步骤（如 `正在修改 server.mts 第 120 行...`），并提供 **[暂停] [取消]** 按钮。
  - **锁屏展示**：常显全景进度条，任务完成时音效与通知提醒。
- **技术实现**：
  - Dart 侧：`MethodChannel('com.nexus.app/live_view').invokeMethod('updateLiveView', ...)`
  - ArkTS 侧：引入 `@kit.LiveViewKit`，调用 `liveViewManager.startLiveView()` / `updateLiveView()`。

#### 2. 交互式通知审批 (Notification Kit) —— 下拉通知栏直接授权/拒绝
- **定位**：安全隐私保护
- **目标**：当 Remote Agent 在 PC 上请求高危命令（如 `rm -rf` / 执行 Shell / 改配置）触发 `permission_request` 时，通知栏直接呈现决策按钮，用户无需解锁打开 App。
- **功能设计**：
  - 收到权限请求时，弹出系统通知，展示目标路径与命令摘要。
  - 通知下方嵌入 ActionButton：**[允许]** 与 **[拒绝 (红色)]**。
  - 点击按钮后，通过后台 Channel 直接回传 `permission_response` 到 Bridge。
- **技术实现**：
  - 引入 `@kit.NotificationKit`，使用带操作按钮的 Action Notification。

#### 3. 近场发现与无缝流转 (DeviceManager / 软总线 / Continuation)
- **定位**：全场景一体协同
- **目标**：利用鸿蒙近场感知与分布式软总线，实现免配置连 PC、大屏流转。
- **功能设计**：
  - **近场自动感知**：手机靠近运行 Bridge 的 PC 时，自动弹窗提示“发现附近 PC (LAPTOP-3FLH)，点击一键连接”。
  - **大屏流转**：点击鸿蒙系统右上角流转按钮，将当前代码 Diff 审查与聊天界面拉起至鸿蒙平板（MatePad Pro），大屏双页对比代码。
  - **分布式剪贴板**：PC 终端报错一键复制，手机侧自动识别并浮现“让 Nexus 修复此报错？”。

#### 4. 后台唤醒与推送 (Push Kit)
- **定位**：全场景一体协同
- **目标**：解决手机切后台/长睡眠后 WebSocket 断连问题。
- **功能设计**：
  - App 退后台或挂起时，通过 Push Kit 推送通道接收 Agent 状态提醒（如长任务完成、权限等待）。
  - 点击通知自动唤起 App 并重连，带上 `lastMessageId` 游标恢复上下文。

---

## 💡 功能增强与 UI Polish (待办)

### 全局搜索中心 (Search Hub)
- **目标**：首页底部 `Search chats` 入口升级为真正搜索中心。
- **功能**：跨 Host、Workspace、Session 检索历史对话正文、Agent 工具调用摘要（如命令、文件路径）和 Plan 步骤。

### 权限请求审阅面板 (Permission Sheet)
- **目标**：增强 `permission_sheet.dart`，在授权前展示完整的风险等级、命令摘要、涉及文件列表及 Diff 预览，避免盲目 Allow。

### 工具调用审阅面板 (Tool Call Review Panel)
- **目标**：增强 `tool_call_card.dart`，提供 stdout / stderr 分色渲染、Bash 命令一键复制、Git Diff 双栏预览。

### 会话管理增强
- **目标**：支持手机端直接重命名 Session、置顶重要会话、归档历史会话与手动销毁后台 ACP 进程。

### 语言 / 主题切换动画平滑统一
- **目标**：收敛 Settings 页面语言/深浅色模式切换时的 UI 重绘路径，避免跳变感。
