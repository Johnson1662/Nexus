# Nexus Flutter OHOS 客户端 (`nexus_flutter/`)

Nexus 手机端是基于 Flutter 开发并编译为 HarmonyOS 原生 HAP 的移动开发协作客户端。通过 WebSocket 连接 PC 端 Bridge Server（默认端口 `12138`），利用 ACP (Agent Client Protocol) 协议驱动并监控桌面 AI 编程 Agent。

---

## 核心特性

- **专业极简界面**：黑白单色调工程美学，无冗余卡片阴影与边框，专注 Agent 代码与思考过程呈现。
- **实时流式与思考链**：支持 Agent Message Chunk、Thinking 折叠流、实时工具调用折叠卡片（状态联动展开/收起）。
- **工作区与代码审查**：内置侧滑文件管理器与 Diff 视图，可直接查看 PC 变更文件列表、Git 差异与提交历史。
- **远程安全授权**：将 Agent 触发的敏感终端命令或文件修改拦截为权限卡片，支持移动端一键授权或拒绝。
- **非阻塞启动与多地址探测**：启动立即渲染界面，后台并行竞速探测局域网、热点及中继候选 IP，自动连入可用主机。
- **鸿蒙系统能力对接**：集成 LiveViewKit 实况窗状态同步与交互式通知审批桥接。

---

## 目录结构

```text
nexus_flutter/
├── lib/
│   ├── main.dart                 # 应用入口、路由表与启动探测
│   ├── pages/                    # 页面组件（Home、Chat、Workspace、Settings、Agent 等）
│   ├── providers/                # 状态层（ChatProvider、WorkspaceProvider）
│   ├── models/                   # 数据模型（MessageData、WsProtocol、ChatState 等）
│   ├── widgets/                  # 核心组件（ToolCallCard、MessageBubble、DiffView 等）
│   ├── services/                 # 核心服务（WSClient、StorageService、HostStore 等）
│   ├── utils/                    # 辅助工具（Agent 格式化与图标工具）
│   └── constants/                # 主题、设计 Token（AppColors、AppSpacing 等）
├── ohos/                         # HarmonyOS 工程目录（DevEco / Hvigor）
│   ├── AppScope/                 # 应用全局配置（app.json5, bundleName: com.nexus.remoteai）
│   ├── entry/                    # 主模块（ArkTS 壳层与原生资源）
│   ├── build-profile.json5       # 构建与签名配置
│   └── local.properties          # 本地 SDK 路径配置（flutter.sdk）
└── pubspec.yaml                  # Flutter 依赖配置
```

---

## 快速构建与部署

### 1. 环境准备

- **Flutter SDK**：带 OHOS 支持的 Flutter 分支（如 `flutter_flutter`，Dart 3.6.2+）
- **构建工具**：DevEco Studio 或 DevEco Command Line Tools (`devecocli`)
- **连接工具**：`hdc`

### 2. 依赖获取

```bash
cd nexus_flutter
flutter pub get
```

### 3. 构建 HAP

由于 `flutter build hap` 的引擎在 ohpm 递归解析时存在已知问题，项目统一使用 `devecocli build` 构建：

```bash
cd nexus_flutter/ohos
# 必须清除 NODE_OPTIONS（避免与 DevEco 自带旧 Node 冲突）
NODE_OPTIONS="" devecocli build --build-mode debug
```

构建产物位于：
`nexus_flutter/ohos/entry/build/default/outputs/default/entry-default-signed.hap`

### 4. 部署至真机

```bash
# 连接设备
hdc tconn <手机IP>:<端口>

# 安装 HAP
hdc -t "<手机IP>:<端口>" install nexus_flutter/ohos/entry/build/default/outputs/default/entry-default-signed.hap

# 启动应用
hdc -t "<手机IP>:<端口>" shell aa start -a EntryAbility -b com.nexus.remoteai
```

---

## 故障排查与构建自恢复

- **ohpm 00306053 Specification Limit Violation / BATCH RECURSION**：
  若在 `hvigor sync` 阶段偶发该报错，是 ohpm 缓存损坏所致。在 `nexus_flutter/ohos` 执行复位：
  ```bash
  ohpm install --all
  NODE_OPTIONS="" devecocli build clean
  NODE_OPTIONS="" devecocli build --build-mode debug
  ```
- **签名材料缺失**：
  检查 `nexus_flutter/ohos/build-profile.json5` 中的 `signingConfigs` 路径。若从 Windows 迁移到 Linux，需将 `.p12`、`.cer`、`.p7b` 复制到 Linux 本地目录并更新配置。
