# Anywhere HarmonyOS App

Anywhere 的鸿蒙原生客户端，通过局域网 WebSocket 连接 `server.js`（bridge），实现 AI Agent 聊天功能。

## 项目结构

```
Anywhere_harmony/
├─ AppScope/
│  ├─ app.json5                     # 应用配置
│  └─ resources/
├─ entry/
│  ├─ src/main/
│  │  ├─ ets/
│  │  │  ├─ entryability/EntryAbility.ets   # UIAbility
│  │  │  ├─ pages/
│  │  │  │  ├─ Index.ets                  # Host 列表页
│  │  │  │  └─ Chat.ets                   # 聊天页
│  │  │  ├─ components/
│  │  │  │  ├─ MessageBubble.ets          # 消息气泡
│  │  │  │  └─ ToolCallCard.ets           # 工具调用卡片
│  │  │  ├─ services/
│  │  │  │  └─ WebSocketService.ets       # WebSocket 服务
│  │  │  ├─ store/
│  │  │  │  └─ SessionStore.ets           # 会话状态
│  │  │  └─ constants/
│  │  │     └─ Colors.ets                # 浅色主题配色
│  │  ├─ resources/
│  │  └─ module.json5
│  └─ build-profile.json5
├─ oh-package.json5
└─ build-profile.json5
```

## 配色（浅色主题）

| Token | 色值 | 用途 |
|-------|------|------|
| surface0 | `#FFFFFF` | 页面背景（白色）|
| surface1 | `#F5F5F5` | 悬停 |
| surface2 | `#EEEEEE` | 卡片、输入框 |
| foreground | `#1A1A1A` | 主文本 |
| foregroundMuted | `#7A7A7A` | 次要文本 |
| accent | `#20744A` | 品牌绿 |
| accentBright | `#2E9B6A` | 亮绿 |
| userBubble | `#007AFF` | 用户消息气泡（蓝色）|
| assistantBubble | `#F0F0F0` | 助手消息气泡（浅灰）|

## 使用步骤

### 1. 启动 Bridge（电脑端）

```bash
cd C:\Users\lneoo\Desktop\cltest\Anywhere
node server.js
```

看到 `[server] listening on ws://localhost:6767` 即成功。

### 2. 查看电脑局域网 IP

```powershell
ipconfig
```

记录 IPv4 地址，如 `192.168.1.100`。

### 3. 用 DevEco Studio 打开项目

1. 打开 DevEco Studio
2. `文件` → `打开` → 选择 `C:\Users\lneoo\Desktop\cltest\Anywhere\Anywhere_harmony`
3. 等待 Sync 完成

### 4. 修改默认 Host 地址

编辑 `entry/src/main/ets/store/SessionStore.ets`：

```typescript
hostUrl: string = 'ws://你的局域网IP:6767';  // 替换 192.168.1.100
```

或在 App 的 Host 列表页点击 "+ Add Host" 添加。

### 5. 运行到真机

1. 手机和电脑连同一 Wi-Fi
2. 手机开启**开发者模式** + **USB 调试**
3. DevEco Studio 顶部选择设备 → 点击运行按钮

### 6. 测试

- 点击 Host（如 "Local Bridge"）→ 进入聊天页
- 输入消息（如 `hello`）→ 点击发送按钮
- 看到助手回复后，`turn_ended` 触发，可发下一条

## WebSocket 协议

App 与 Bridge 之间的消息格式（与 client.js 一致）：

### App → Bridge

| type | 字段 | 用途 |
|------|------|------|
| `start` | `agent`, `prompt?` | 启动 agent（ACP 模式）|
| `input` | `sessionId`, `text` | 发送用户输入 |
| `cancel` | `sessionId` | 取消运行中的 agent |

### Bridge → App

| type | 字段 | 用途 |
|------|------|------|
| `session_started` | `sessionId`, `agent` | agent 已启动 |
| `agent_event` | `sessionId`, `event` | ACP 事件（消息/工具调用）|
| `turn_ended` | `sessionId`, `stopReason` | 一轮结束，可输入下一条 |
| `session_ended` | `sessionId`, `exitCode` | agent 进程退出 |
| `error` | `text` | 错误 |

## ACP 事件类型（agent_event 中的 event）

| `sessionUpdate` | 说明 |
|---------------|------|
| `agent_message_chunk` | 助手文本输出 |
| `agent_thought_chunk` | 思考过程（UI 中跳过）|
| `tool_call` | 工具调用开始 |
| `tool_call_update` | 工具调用状态更新 |
| `plan` | Agent 计划 |

## 注意事项

1. **防火墙**：电脑需放行 `node.exe` 的入站连接（端口 6767）
2. **局域网**：手机和电脑必须在同一网段（如都是 `192.168.1.x`）
3. **权限**：`module.json5` 已声明 `ohos.permission.INTERNET`
4. **浅色主题**：已替换原深色主题，背景为白色，文字为深灰

## 下一步

- [ ] 实现 `NavPathStack` 导航（替换 `router`）
- [ ] 完善 `ToolCallCard` 展开/收起功能
- [ ] 添加消息长按复制功能
- [ ] 实现 `PlanView.ets` 显示 Agent 计划
- [ ] 添加 `permission_request` 处理（权限请求弹窗）
- [ ] 支持多 Host 持久化（preferences）
