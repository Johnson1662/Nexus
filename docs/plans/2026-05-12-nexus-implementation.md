# Nexus 重构实现计划

> **Goal:** 基于华为官方文档（StateStore + @ComponentV2 + Navigation）重新设计 Nexus HarmonyOS App，支持任意 ACP 协议 Agent。

**架构:** 三层分层架构 (common/feature/product) + StateStore 全局状态管理 + Navigation 路由 + 全宽卡片式视觉

**Tech Stack:** ArkTS (API 12+), StateStore (createStore/Reducer/Action), @ComponentV2/@ObservedV2/@Trace, Navigation + NavPathStack, @kit.NetworkKit WebSocket

---

### Phase 1: 公共能力层 — model + store + websocket + Colors

**Task 1.1: Colors.ets — 精简设计 Token**

- Modify: `constants/Colors.ets`
- 合并 Colors.ets 和 AGENTS.md 的 Token，统一为新版视觉规范

**Task 1.2: 数据模型 — @ObservedV2 装饰**

- Create: `common/model/MessageData.ts`
- Create: `common/model/ChatState.ts`
- Create: `common/model/WorkspaceInfo.ts`
- Create: `common/model/AgentConfig.ts`

**Task 1.3: StateStore 仓库**

- Create: `common/store/ChatStore.ts`
- Create: `common/store/WorkspaceStore.ts`

**Task 1.4: WebSocket 客户端**

- Create: `common/websocket/WSProtocol.ts`
- Create: `common/websocket/WSClient.ts`

### Phase 2: 基础特性层 — 组件

**Task 2.1: 公共 UI 组件**

- Create: `common/ui/CardHeader.ets`
- Create: `common/ui/MessageCard.ets`
- Modify: `components/ThinkingSection.ets` → 内嵌折叠样式
- Modify: `components/ToolCallCard.ets` → 胶囊式

**Task 2.2: 工作区组件**

- Modify: `components/WorkspaceDrawer.ets`

**Task 2.3: 聊天组件**

- Create: `feature/chat/ChatPage.ets`
- Create: `feature/chat/ChatInputBar.ets`

### Phase 3: 产品定制层 — 页面入口

**Task 3.1: Index.ets Navigation 根容器**

- Rewrite: `pages/Index.ets`

### Phase 4: server.js ACP 通用化

- Modify: `server.js` — 移除 opencode 硬编码限制

### Phase 5: 构建部署验证

- 构建 HAP
- 部署设备
- 启动验证
