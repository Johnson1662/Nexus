# Code Review: Anywhere 项目全面审查

## 变更概述

审查了整个项目代码库（19 个文件 +1,010/-128 行），涵盖 HarmonyOS 前端（ArkTS）和 Node.js 桥接服务器（TypeScript）。

---

## 1. 关键安全问题

### 1.1 `shell: true` 且未对 agent 名称做校验 — 远程命令执行（CRITICAL）
**文件:** `server/src/handlers/start.mts:37`
**文件:** `server/src/handlers/input.mts:51`
**文件:** `server/src/handlers/load-session.mts:37`
**文件:** `server/src/handlers/resume-session.mts:37`

所有四个处理函数都将 `spawn(agent, args, { shell: true })` 直接传入从 WebSocket 客户端接收到的 `agent` 字符串作为命令。`agent` 从未经过 `ACP_AGENTS` 注册表或任何其他方式的校验。由于 `shell: true`，攻击者可以传入 `"calc.exe"` 或 ``"rm -rf / || true"`` 等任意 shell 命令。

**修复方案：** 在调用 `spawn()` 之前，将 `agent` 与 `AGENT_ARGS_MAP` 或 `ACP_AGENTS` 列表进行比对。如果不在白名单内，拒绝并发送错误信息。

### 1.2 `isPathWithinCwd` 软链接绕过（MEDIUM）
**文件:** `server/src/acp-callbacks.mts:24-28`

`path.resolve()` 可以解析 `..` ，但不会解析软链接。如果工作目录内的软链接指向外部路径（例如 `ln -s /etc /cwd/escape`），`isPathWithinCwd` 仍然返回 `true`，从而允许读取/写入工作目录外的任意文件。

**修复方案：** 在相对路径检查之前使用 `fs.realpath()`。

---

## 2. 高优先级 Bug

### 2.1 `PulsingDots` 动画永不销毁（HIGH）
**文件:** `ChatPage.ets:15-23`

`aboutToAppear` 中的三个 `animateTo({ iterations: -1 })` 调用未在 `aboutToDisappear` 中取消。组件销毁时（例如切换会话时），动画会泄漏。

**修复方案：** 添加 `aboutToDisappear()` ，将 `iterations: 1` 设为 `animateTo` 以终止循环。

### 2.2 Logo 动画永不销毁（HIGH）
**文件:** `ChatPage.ets:84-87`
**文件:** `OnboardingView.ets:245-247`

与 2.1 相同：BrandLogo 的无限制缩放动画缺乏清理逻辑。

### 2.3 `ChatInputBar.ets:66-75` — PhotoViewPicker 的 catch 范围过大（HIGH）
```typescript
try {
  // PhotoViewPicker logic
} catch (err) {
  this.pickFile(); // fallback
}
```
真正的原因是“PhotoViewPicker 不可用”的场景与“readBinaryFile 内部的 bug”混在了一起。如果在图片选中之后发生错误，应用程序会静默地打开文档选择器作为备选方案，从而掩盖错误。

**修复方案：** 缩小 catch 范围，仅捕获 PhotoViewPicker 初始化/选择阶段的错误，或添加错误日志。

### 2.4 `handleServerInfo` 端口解析对 IPv6 有问题（HIGH）
**文件:** `WSClient.ets:292-298`

```typescript
let idx: number = this.lastUrl.lastIndexOf(':');
```
对 `ws://[::1]:12138`，`lastIndexOf(':')` 命中的是括号内的冒号，而不是端口分隔符。结果端口提取会失败，并回退到硬编码的 `'12138'`。

**修复方案：** 使用 URL 解析器，或对 IPv6 显式处理带方括号的地址。

### 2.5 `tryConnect` 中重复的 done() 调用（MEDIUM）
**文件:** `WSClient.ets:47-70`

打开套接字后，`open`、`error`、`close` 事件会连续触发。 `done()` 中有 `resolved` 守卫，但 `ws.close()` 会再次被调用，并触发另一个 `close` 事件 —— 形成一个循环。目前因为 `resolved` 守卫且 `done()` 中 `ws.close()` 被 try/catch 包裹，暂时安全，但仍是一个脆弱的问题。

**修复方案：** 在 `done()` 函数的第一行移除所有事件监听器，避免重复触发。

---

## 3. 中等优先级问题

### 3.1 `StorageService.init()` 在失败时永不 resolve（MEDIUM）
**文件:** `StorageService.ets:24`

如果 `preferences.getPreferences()` 失败，`initPromise` 会被设置但永不 resolve，导致所有后续 `init()` 调用都返回一个永远 pending 的 Promise。

**修复方案：** 使用 try/catch → reject，或将 `initPromise` 重置为 null。

### 3.2 文件读取 catch 块静默吞掉所有错误（MEDIUM）
**文件:** `ChatInputBar.ets:104-123, 128-150`

`readTextFile` 和 `readBinaryFile` 中的 `catch (err)` 块完全吞掉了错误。用户在文件附加失败时看不到任何反馈。

**修复方案：** 添加 `hilog.error()` 或 toast 提示。

### 3.3 `MessageDataSource.updateData` 在全量重载时效率低下（MEDIUM）
**文件:** `MessageDataSource.ets:17`

每次流式更新都会对整个列表调用 `notifyDataReload()`。在流式传输快的情况下，这会导致帧率下降。

**修复方案：** 使用 `notifyDataChange(index)` 实现更细粒度的更新。

### 3.4 `ChatPage.ets:23` — `getUIContext()` 在 `aboutToAppear` 中可能为 undefined（MEDIUM）

在组件挂载之前，`getUIContext()` 可能返回 `undefined`，导致所有点动画都悄悄不启动。

**修复方案：** 延迟到 `onAppear` 启动动画，或添加显式的 null 检查逻辑。

---

## 4. 代码质量与规范

### 4.1 ✅ 总体遵循 ArkTS 规范
- 所有 SymbolGlyph 名称均在与 `docs/harmonyos-symbol-reference.md` 交叉验证中存在
- `@ObservedV2`/`@Trace` 用法正确
- `String()`/`Boolean()` 类型转换符合规范
- `LongPressGesture` 用法正确（`.gesture()` + `duration: 600`）
- `SideBarContainer` 动画使用 `animateTo()` + `.showSideBar()` 模式（不带 `$$`），与 AGENTS.md 一致

### 4.2 服务端代码组织良好
- 清晰的处理函数模式，每个 WS 消息类型一个文件
- `enqueueWsOp()` 会话操作序列化设计良好
- Session 和 terminal 清理在断开连接时可靠执行

### 4.3 无新增测试
所有 19 个被修改的文件中均未包含测试。像 `parseFilePrefix()`、`getWorkspaceScopes()`、`isOldHostList()`、`tryConnect()` 等都是纯函数，非常适合做单元测试。

---

## 5. 按优先级排序的修复清单

| # | 优先级 | 文件 | 问题 | 修复 |
|---|--------|------|------|------|
| 1 | CRITICAL | `handlers/start.mts` 等 | `shell: true` + agent 未校验 | 在 spawn 前加白名单校验 |
| 2 | HIGH | `ChatPage.ets:15` | PulsingDots 动画泄漏 | 添加 `aboutToDisappear` 清理逻辑 |
| 3 | HIGH | `ChatPage.ets:84` | Logo 动画泄漏 | 同上 |
| 4 | HIGH | `ChatInputBar.ets:66` | catch 范围过大 | 缩小 catch 范围 / 加日志 |
| 5 | HIGH | `WSClient.ets:292` | IPv6 端口解析 | 添加 IPv6 方括号检测 |
| 6 | MEDIUM | `acp-callbacks.mts:24` | 软链接绕过 | 使用 `fs.realpath()` |
| 7 | MEDIUM | `StorageService.ets:24` | init 永不 resolve | try/catch → reject |
| 8 | MEDIUM | `ChatInputBar.ets:104` | 静默错误吞掉 | 添加 hilog/反馈 |
| 9 | MEDIUM | `WSClient.ets:47` | done() 重复调用 | 解除事件监听绑定 |
| 10 | LOW | `MessageDataSource.ets` | 全量重载 | 改为 `notifyDataChange(index)` |

---

## 6. 合并准备度评分

| 维度 | 评分 | 备注 |
|------|------|------|
| 功能完整性 | 4/5 | 设备分组、文件上传、会话重命名均完整 |
| 代码质量 | 4/5 | 遵循规范，存在几个中等风险问题 |
| 安全性 | 2/5 | CRITICAL：`shell: true` 且 agent 未校验 |
| 性能 | 4/5 | 并行连接探测；LazyForEach 全量重载效率较低 |
| 测试 | 2/5 | 无新增测试 |
| **总分** | **3.2/5** | **阻塞项：在合并前修复 agent 命令注入问题** |

---

## 7. 校验说明

执行 `hmdev-cli build`：✅ BUILD SUCCESSFUL (1.084s)

运行 `npm run build`（server TypeScript）：✅ 通过，无错误
