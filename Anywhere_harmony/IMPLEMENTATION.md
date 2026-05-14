# Anywhere HarmonyOS App - 实现总结

## 项目信息
- **项目路径**：`C:\Users\lneoo\Desktop\cltest\Anywhere\Anywhere_harmony`
- **Target SDK**：`6.0.2(22)`
- **Compatible SDK**：`5.0.0(12)`
- **构建状态**：✅ BUILD SUCCESSFUL

## 项目结构
```
Anywhere_harmony/
├─ AppScope/
│  ├─ app.json5
│  └─ resources/
│     └─ base/element/string.json, media/startIcon.png
├─ entry/
│  ├─ src/main/
│  │  ├─ ets/
│  │  │  ├─ entryability/EntryAbility.ets
│  │  │  ├─ entrybackupability/EntryBackupAbility.ets
│  │  │  ├─ pages/
│  │  │  │  └─ Index.ets                  # Host 列表 + 聊天（单页）
│  │  │  ├─ components/
│  │  │  │  ├─ MessageBubble.ets
│  │  │  │  ├─ ToolCallCard.ets
│  │  │  │  └─ PlanView.ets
│  │  │  ├─ services/
│  │  │  │  └─ WebSocketService.ets
│  │  │  ├─ store/
│  │  │  │  └─ SessionStore.ets
│  │  │  └─ constants/
│  │  │     └─ Colors.ets
│  │  ├─ resources/
│  │  │  ├─ base/profile/main_pages.json
│  │  │  └─ element/string.json, color.json
│  │  └─ module.json5
│  ├─ build-profile.json5
│  ├─ oh-package.json5
│  └─ hvigorfile.ts
├─ build-profile.json5          # 项目级构建配置（含签名）
├─ oh-package.json5
├─ hvigorfile.ts
└─ hvigor/hvigor-config.json5
```

## 核心功能

### 1. Host 列表页
- 显示已配置的 Host（名称 + URL）
- 点击进入聊天
- 支持添加新 Host（名称 + ws://IP:port）
- **模型选择下拉框**：预设模型列表

### 2. 聊天页
- 连接 WebSocket（支持 Tailscale IP）
- 发送消息（用户消息右对齐蓝色气泡）
- 接收 AI 回复（助手消息左对齐浅灰气泡）
- 显示工具调用卡片（pending/running/completed/failed）
- 显示 Agent 计划（plan 事件）

### 3. WebSocket 协议
| 客户端 → 服务端 | 服务端 → 客户端 |
|---|---|
| `{ type: "start", agent: "opencode", prompt: "..." }` | `{ type: "session_started", sessionId: "..." }` |
| `{ type: "input", sessionId: "...", text: "..." }` | `{ type: "agent_event", event: {...} }` |
| `{ type: "permission_response", sessionId: "...", requestId: "...", outcome: "allow" }` | `{ type: "turn_ended" }` |
| | `{ type: "permission_request", ... }` |
| | `{ type: "error", text: "..." }` |

**ACP 事件解析**
- `agent_message_chunk` → 流式文本追加
- `tool_call` → 工具调用卡片
- `tool_call_update` → 工具状态更新
- `plan` → 计划视图

### 4. 权限请求
- 收到 `permission_request` 时显示对话框
- 支持 Allow / Deny

### 5. 浅色主题
| Token | 色值 | 用途 |
|-------|------|------|
| surface0 | `#FFFFFF` | 页面背景 |
| surface1 | `#F5F5F5` | 悬停、输入框 |
| surface2 | `#EEEEEE` | 卡片 |
| foreground | `#1A1A1A` | 主文本 |
| foregroundMuted | `#7A7A7A` | 次要文本 |
| accent | `#20744A` | 按钮、品牌 |
| userBubble | `#007AFF` | 用户消息气泡 |
| assistantBubble | `#F0F0F0` | 助手消息气泡 |
| success | `#07C160` | 成功状态 |
| warning | `#FF9500` | 进行中状态 |
| error | `#FF3B30` | 错误状态 |

## 构建与部署

### 本地构建
```powershell
cd C:\Users\lneoo\Desktop\cltest\Anywhere\Anywhere_harmony

# Debug 构建
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default assembleHap

# Sync（项目配置校验）
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --sync -p product=default
```

### 部署
- Deveco Studio 选择设备 → Run/Debug
- HAP 安装后自动启动

### 签名配置
- `build-profile.json5` 已配置调试签名（会自动生成）
- 首次部署会提示设置签名（选自动生成 debug 签名）

## 网络配置

### 电脑端启动 Bridge
```powershell
cd C:\Users\lneoo\Desktop\cltest\Anywhere
node server.js
# 监听 ws://0.0.0.0:6767
```

### Tailscale（推荐）
- 手机和电脑都打开 Tailscale
- 手机用电脑的 Tailscale IP（如 `100.111.77.50:6767`）
- 无需配置防火墙/同一 Wi-Fi

### 局域网（备选）
- 手机和电脑连同一 Wi-Fi
- 电脑查询局域网 IP：`ipconfig`
- 防火墙放行：`netsh advfirewall firewall add rule name="Anywhere Node Server 6767" dir=in action=allow protocol=TCP localport=6767`

## 已修复的问题

### 1. 构建错误 No module found
- **根因**：`build-profile.json5` 配置格式不对
- **修复**：删除空的 `signingConfigs`，添加 `compileSdkVersion` 使 `compatible <= target <= compile` 满足

### 2. 资源文件格式错误
- **根因**：`color.json`、`string.json` 用对象而非数组
- **修复**：改为 HarmonyOS 要求的数组结构

### 3.ArkTS 编译错误（77 个）
- **根因**：原代码是 TypeScript 风格，不符合严格ArkTS
- **修复**：完全重写 `.ets` 文件，使用正确 ArkTS 语法

### 4. 第二条消息不回复
- **根因**：收到第二轮 `agent_message_chunk` 时追加到"上一条消息"而非新建 assistant 消息
- **修复**：`SessionStore.appendToLastAssistantText()` 只有最后一条是 assistant text 时才追加；否则新建消息

### 5. HAP 未签名
- **根因**：`products.default` 未引用 `signingConfigs.default`
- **修复**：添加 `"signingConfig": "default"`

## 待实现功能

### 1. 实时模型列表获取（进行中）
- **方案**：App 请求 → server 执行 `opencode models` → 返回下拉框
- **进度**：已添加静态预设，正在开发实时获取

### 2. 模型参数传递
- **方案**：App 选择模型 → 首次 `start` 消息带 `model` → server 启动 `opencode --model ... acp`
- **状态**：已完成

## 已知限制
- 单页设计（Host + 聊天在同一页面，非 Navigation）
- 首次发消息时创建 session，之后用 `sessionId` 续对话
- 断开连接后需重新进入 Host 列表再进入聊天