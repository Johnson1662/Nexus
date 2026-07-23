# Nexus 重构架构设计

日期: 2026-05-12
状态: 已批准

## 概述

Nexus HarmonyOS App 全面重构。基于华为官方文档的最佳实践，使用状态管理 V2 + StateStore + Navigation + 分层架构，同时适配任意 ACP 协议的 AI Agent。

## 核心变更

| 维度 | 旧方案 | 新方案 |
|------|--------|--------|
| 状态管理 | `@State` + 手动 `version++` hack | `StateStore.createStore()` + Reducer/Action |
| 组件装饰器 | `@Component` / `@State` / `@Prop` | `@ComponentV2` / `@Local` / `@Param` / `@Event` |
| 数据模型 | 普通 class | `@ObservedV2` + `@Trace` 深度观测 |
| 路由 | `if/else` 切视图 | `Navigation` + `NavPathStack` |
| 模块化 | 代码平铺 | 三层架构: common / feature / product |
| Agent 支持 | 硬编码 `opencode` | ACP 协议无关，可配置 agent 类型 |
| 视觉 | 窄气泡 | 全宽白卡片 + CardHeader 区分角色 |

## 分层模块结构

```
entry/src/main/ets/
├── common/                          # 公共能力层 (HAR)
│   ├── model/                       # @ObservedV2 数据模型
│   │   ├── MessageData.ts
│   │   ├── ChatState.ts
│   │   ├── WorkspaceInfo.ts
│   │   └── AgentConfig.ts
│   ├── store/                       # StateStore 全局仓库
│   │   ├── ChatStore.ts
│   │   ├── WorkspaceStore.ts
│   │   └── AgentStore.ts
│   ├── websocket/                   # WSClient + 协议定义
│   │   ├── WSClient.ts
│   │   └── WSProtocol.ts
│   └── ui/                          # 公共 UI 组件
│       ├── MessageCard.ets          # 全宽消息卡片
│       ├── CardHeader.ets           # 卡片头部(图标+名字+时间+状态)
│       ├── ThinkingSection.ets      # 折叠推理
│       ├── ToolCallCard.ets         # 工具调用胶囊
│       ├── PlanView.ets             # 计划进度
│       └── Colors.ets               # 设计 Token
│
├── feature/                         # 基础特性层 (HAR)
│   ├── workspace/
│   │   ├── WorkspaceListPage.ets
│   │   └── WorkspaceDrawer.ets
│   └── chat/
│       ├── ChatPage.ets             # 聊天主页面
│       ├── ChatInputBar.ets         # 输入栏(两行布局)
│       └── SessionBar.ets           # 会话选择器
│
└── product/                         # 产品定制层 (Entry HAP)
    └── pages/
        └── Index.ets                # @Entry Navigation 根容器
```

## 布局结构

```
┌──────────────────────────────────────────────────────────┐
│  ☰ Nexus  [Sessions ▼]                  my-project    │ ← 顶栏
├──────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  用户卡片                                              │  │
│  │  CardHeader(头像+名称+时间)                            │  │
│  │  消息内容                                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Agent卡片                                             │  │
│  │  CardHeader(头像+名称+状态)                            │  │
│  │  ┌ 推理过程 ──────────────────────────────────────┐  │  │
│  │  │  ...thinking...                                │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  │  [工具调用] ✔ 完成                                   │  │
│  │  [工具调用] ⏳ 执行中                                 │  │
│  │  回复内容                                              │  │
│  │  ● 计划 3/3 步骤完成                                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  输入消息...                                          │  │ ← 第一行
│  │  [Model ▼]  [Mode ▼]                      [发送 ▶]  │  │ ← 第二行
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## 视觉 Token

基于 HarmonyOS Design 语言，重用现有 Colors.ets:
- 卡片: `surfaceElevated(#FFFFFF)`, 圆角 `radiusLg(16)`
- 页面背景: `surface0(#F0F2F5)`
- 主文本: `foreground(#1A1A1A)`
- 次要: `foregroundMuted(#8A8E96)`
- 品牌绿: `accent(#1A7F4B)` 仅用户卡片标记

## 技术栈

| 能力 | 方案 |
|------|------|
| 状态管理 | `StateStore.createStore()` + Reducer/Action |
| 装饰器 | `@ComponentV2` / `@Local` / `@Param` / `@Event` |
| 数据模型 | `@ObservedV2` + `@Trace` |
| 路由 | `Navigation` + `NavPathStack` |
| WebSocket | `@kit.NetworkKit` `webSocket.createWebSocket()` |
| ACP 协议 | agent 无关，server.js 透传 agent 字段 |

## 实现顺序

1. **Phase 1**: common/ 公共能力层 (model + store + websocket + Colors)
2. **Phase 2**: feature/ 基础特性层 (workspace + chat 组件)
3. **Phase 3**: product/ 产品定制层 (Index.ets Navigation)
4. **Phase 4**: server.js ACP 通用化
5. **Phase 5**: 构建部署验证
