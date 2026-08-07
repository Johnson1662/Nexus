# Nexus — HarmonyOS 远程 AI 编程助手

Nexus 是一个 HarmonyOS 优先的 AI Agent 远程控制与代码协作工具：在手机上通过 WebSocket 连接 PC 端的 Bridge Server，Bridge Server 再通过 [Agent Client Protocol（ACP）](https://agentclientprotocol.com/) 与 OpenCode、Claude Code、Codex 等本地 AI 编程 Agent 通信，实现随时随地在移动端查看、审批和驱动 PC 上的 AI 编程任务。

## 架构

```text
手机 (Nexus App)                     PC (Bridge Server)                  AI Agent
┌──────────────┐     直连 WS (LAN)    ┌─────────────────────┐            ┌──────────┐
│  nexus_flutter │ ←────────────────→ │  server/dist/cli.mjs │ ── ACP ──→ │ OpenCode  │
│  (Flutter HAP) │   ws://<ip>:12138  │  (Node.js 守护进程)  │           │ Claude    │
└──────────────┘                      └─────────────────────┘           │ codex-acp │
        │                                    │                          └──────────┘
        └──── 可选：中继模式（NEXUS_RELAY_URL 环境变量启用），适用于远程访问 ────┘
```

- **手机端**：`nexus_flutter/`（Flutter，构建为 HarmonyOS HAP），当前活跃开发的主战场
- **服务端**：`server/`（Node.js + TypeScript），WebSocket 桥接 + ACP 会话生命周期管理 + Agent 注册/安装 + 权限转发 + E2EE 加密通道
- **协议**：手机 ↔ Bridge 为自定义 JSON over WebSocket；Bridge ↔ Agent 为 ACP（JSON-RPC）

## 目录结构

```text
Nexus/
├── server/           # PC 端 Bridge Server（TypeScript → dist/*.mjs）
│   ├── src/          # 源码：server.mts、session-manager.mts、handlers/、registry/…
│   └── README.md     # 服务端完整文档（协议、CLI、故障排查）
├── nexus_flutter/    # 手机端 Flutter 客户端（OHOS 工程在 ohos/ 子目录）
│   └── lib/          # pages/、widgets/、providers/、services/、models/
├── docs/             # 设计文档、todo、比赛材料
├── plans/            # 规格与重构计划
├── adr/              # 架构决策记录
├── app_test_picture/ # 实机测试截图
└── prototype_picture/ # 产品设计原型
```

## 快速开始

### 1. 构建并启动 Bridge Server（PC 端）

```bash
npm install
npm run build        # 编译 TypeScript → server/dist/
npm start            # 启动后台守护进程，监听 :12138
npm run status       # 查询状态
npm run stop         # 停止服务
```

### 2. 手机端构建与部署（nexus_flutter）

```bash
cd nexus_flutter/ohos
NODE_OPTIONS="" devecocli build --build-mode debug   # 产物：entry/build/default/outputs/default/entry-default-signed.hap
devecocli run --device "<UDID>" --skip-build
```

> ⚠️ 构建前必须清空 `NODE_OPTIONS`（WorkBuddy 的 `--use-system-ca` 与 DevEco 自带旧 Node 冲突）；`devecocli` 必须在 `ohos/` 目录下执行。构建失败（ohpm 00306053）时先 `devecocli build clean` 复位。

### 3. 连接

手机与 PC 处于同一局域网（或手机连 PC 热点）时，在 App 中扫码 / 手动添加主机地址 `ws://<PC-IP>:12138` 即可直连。

## 测试

```bash
npm test             # 构建 + 服务端全部测试（会话生命周期、权限委托、取消、终端 delta、session watcher 等）
cd nexus_flutter && flutter test   # 手机端 Dart 单元测试
```

## 文档

- `server/README.md` — WebSocket 协议、CLI 用法、Agent 注册/安装、故障排查、安全边界
- `AGENTS.md` — 开发指南（架构决策、ArkTS 规范、构建部署、踩坑记录）
- `CONTEXT.md` — 领域模型与术语
- `PRODUCT.md` / `SPEC.md` — 产品定位与规格
- `adr/` — 架构决策记录
