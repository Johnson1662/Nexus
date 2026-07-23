# Paseo App 前端界面架构文档

## 1. 项目概述

Paseo 的前端应用位于 `packages/app` 目录，是一个基于 **Expo (React Native)** 的跨平台应用，同时支持移动端和桌面端 (Electron)。

- **技术栈**: React Native + Expo Router + React Navigation
- **状态管理**: Zustand + React Query
- **样式**: react-native-unistyles
- **平台适配**: 移动端 / 桌面端 (Electron) / Web

---

## 2. 目录结构

```
packages/app/src/
├── app/                    # Expo Router 页面路由 (基于文件系统的路由)
│   ├── _layout.tsx         # 根布局 - 全局 providers 和路由配置
│   ├── index.tsx           # 首页 - 启动引导和重定向
│   ├── welcome.tsx         # 欢迎页
│   ├── pair-scan.tsx      # 配对扫描页
│   ├── settings/           # 设置相关页面
│   │   ├── index.tsx       # 设置首页
│   │   ├── [section].tsx  # 设置详情页
│   │   ├── hosts/         # 主机配置
│   │   └── projects/      # 项目配置
│   └── h/[serverId]/      # 主机路由 (动态路由)
│       ├── index.tsx      # 主机首页 -> 重定向到 open-project
│       ├── sessions.tsx  # 会话列表
│       ├── open-project.tsx  # 打开项目页
│       ├── settings.tsx  # 主机设置页
│       ├── workspace/[workspaceId]/  # 工作区路由
│       │   └── index.tsx  # 工作区主页
│       └── agent/[agentId].tsx  # Agent 详情页
│
├── components/             # UI 组件
│   ├── left-sidebar.tsx   # 左侧边栏 (Agent 列表)
│   ├── explorer-sidebar.tsx   # 文件浏览器侧边栏
│   ├── headers/           # 头部组件
│   │   ├── screen-header.tsx
│   │   ├── back-header.tsx
│   │   ├── menu-header.tsx
│   │   └── header-toggle-button.tsx
│   ├── sidebar/           # 侧边栏子组件
│   ├── icons/             # 图标组件
│   ├── ui/                # 基础 UI 组件 (Combobox, Dropdown, Tooltip 等)
│   └── ...                # 其他业务组件
│
├── screens/                # 业务页面组件 (与 app/ 路由对应)
│   ├── workspace/          # 工作区页面
│   │   ├── workspace-screen.tsx    # 工作区主屏幕 (3607 行，核心组件)
│   │   ├── workspace-pane-content.tsx   # 工作区面板内容
│   │   ├── workspace-desktop-tabs-row.tsx  # 桌面端标签栏
│   │   ├── workspace-draft-agent-tab.tsx   # Draft Agent 标签
│   │   └── workspace-git-actions.tsx   # Git 操作
│   ├── settings/          # 设置页面
│   ├── sessions-screen.tsx
│   ├── open-project-screen.tsx
│   └── startup-splash-screen.tsx
│
├── contexts/               # React Context
│   ├── session-context.tsx        # 会话上下文
│   ├── voice-context.tsx         # 语音上下文
│   ├── toast-context.tsx         # Toast 提示
│   ├── sidebar-callout-context.tsx
│   └── sidebar-animation-context.tsx
│
├── hooks/                  # 自定义 Hooks
│   ├── use-settings.ts           # 设置管理
│   ├── use-sidebar-workspaces-list.ts  # 侧边栏工作区列表
│   ├── use-projects.ts           # 项目管理
│   └── ...                       # 40+ 个 hooks
│
├── stores/                 # Zustand 状态管理
│   ├── panel-store.ts             # 面板状态 (侧边栏、标签页等)
│   ├── session-store.ts          # 会话状态 (Agent、Workspace 管理)
│   ├── workspace-layout-store.ts # 工作区布局状态
│   ├── workspace-tabs-store.ts   # 标签页状态
│   ├── browser-store.ts          # 浏览器状态 (WebView)
│   └── ...                       # 其他 store
│
├── styles/                 # 样式配置
│   ├── unistyles.ts        # Unistyles 初始化
│   ├── theme.ts           # 主题配置 (6 种主题)
│   └── settings.ts        # 样式设置
│
├── runtime/                # 运行时
│   └── host-runtime.ts    # 主机运行时客户端
│
├── desktop/                # Electron 桌面端特定代码
├── terminal/               # 终端相关
└── workspace/              # 工作区相关
```

---

## 3. 路由架构

### 3.1 根布局 `_layout.tsx` (核心入口)

**文件**: `packages/app/src/app/_layout.tsx`

根布局负责:
- 全局 Providers 注入 (GestureHandler, SafeArea, Keyboard, Query, Portal)
- 运行时 Providers (HostRuntimeBootstrap, Session, Voice, Toast, Sidebar)
- 主题切换和样式初始化
- 启动引导和 Daemon 连接管理
- 移动端手势边栏
- 全局弹窗 (CommandCenter, ProjectPicker, WorkspaceSetupDialog 等)

### 3.2 路由层级

```
index (启动页)
    │
    ├── welcome (欢迎页)
    │
    ├── pair-scan (配对扫描)
    │
    ├── settings/
    │       ├── index (设置首页)
    │       ├── [section] (设置详情)
    │       ├── hosts/[serverId] (主机设置)
    │       └── projects/
    │
    └── h/[serverId]/                    (主机路由组)
            ├── index (重定向 -> open-project)
            ├── sessions (会话列表)
            ├── open-project (打开项目)
            ├── settings (主机设置)
            │
            ├── workspace/[workspaceId]/ (工作区)
            │       └── index (工作区主页面)
            │
            └── agent/[agentId] (Agent 详情 - 跳转路由)
```

---

## 4. 布局结构

### 4.1 桌面端布局

```
┌─────────────────────────────────────────────────────────────┐
│  Titlebar (Electron 窗口控制)                                │
├────────────┬────────────────────────────────────────────────┤
│            │  Workspace Tabs (标签栏)                        │
│  左侧边栏  ├────────────────────────────────────────────────┤
│  (Agent   │                                                │
│   列表)   │         工作区内容                              │
│            │     (Terminal / Browser / File / Agent)       │
│            │                                                │
│            ├────────────────────────────────────────────────┤
│            │  右侧边栏 (文件浏览器 - 可选)                   │
└────────────┴────────────────────────────────────────────────┘
```

**组件**:
- `LeftSidebar` - 左侧边栏，显示 Agent 列表和工作区
- `WorkspaceScreen` - 工作区主屏幕 (3607 行)
- `ExplorerSidebar` - 右侧文件浏览器 (可选)

### 4.2 移动端布局

```
┌────────────────────────────────────────────────┐
│  状态栏                                        │
├────────────────────────────────────────────────┤
│  Workspace Tabs                                │
├────────────────────────────────────────────────┤
│                                                │
│         工作区内容                              │
│                                                │
├────────────────────────────────────────────────┤
│  ← 左侧边栏 (滑入手势) →                       │
└────────────────────────────────────────────────┘
```

**特性**:
- 左侧边栏通过滑动手势打开
- `MobileGestureWrapper` 处理滑动手势
- 响应式布局 (`useIsCompactFormFactor()`)

---

## 5. 核心组件

### 5.1 工作区屏幕 (WorkspaceScreen)

**文件**: `packages/app/src/screens/workspace/workspace-screen.tsx` (3607 行)

这是应用的核心组件，负责:
- 工作区标签页管理 (Tabs)
- 左侧文件浏览器 (`ExplorerSidebar`)
- 面板容器 (`SplitContainer`)
- Git 操作 (`BranchSwitcher`, `WorkspaceGitActions`)
- 浏览器 WebView (`browser-pane.tsx`)
- 终端 (`terminal-pane.tsx`)
- Agent 聊天界面 (`message.tsx`, `message-input.tsx`)

### 5.2 左侧边栏 (LeftSidebar)

**文件**: `packages/app/src/components/left-sidebar.tsx` (994 行)

功能:
- 主机选择器 (Host Combobox)
- 工作区列表 (`SidebarWorkspaceList`)
- Agent 列表 (`AgentList`)
- 快捷键提示 (`SidebarShortcutModel`)
- 刷新和设置入口

### 5.3 面板状态管理 (PanelStore)

**文件**: `packages/app/src/stores/panel-store.ts`

管理:
- 左侧边栏开关状态
- 右侧文件浏览器开关状态
- 移动端视图状态
- 焦点模式 (Focus Mode)

---

## 6. 主题系统

**文件**: `packages/app/src/styles/theme.ts`

支持 6 种主题:
- `dark`, `zinc`, `midnight`, `cla` (Claude), `ghostty`, `light`

主题通过 `react-native-unistyles` 管理，支持自适应主题。

---

## 7. 平台适配

通过以下方式进行平台适配:

| 方式 | 用途 |
|------|------|
| `isWeb` / `isNative` / `isElectron` | 条件渲染 |
| `.web.ts` / `.native.ts` / `.electron.ts` | 平台特定文件 |
| `useIsCompactFormFactor()` | 响应式布局 |
| `getIsElectronRuntime()` | Electron 检测 |

---

## 8. 关键文件索引

### 路由相关
| 文件 | 说明 |
|------|------|
| `app/_layout.tsx` | 根布局，全局 providers 和路由配置 |
| `app/index.tsx` | 首页，启动引导 |
| `app/h/[serverId]/workspace/[workspaceId]/index.tsx` | 工作区路由入口 |

### 核心组件
| 文件 | 说明 |
|------|------|
| `components/left-sidebar.tsx` | 左侧边栏 (994行) |
| `components/explorer-sidebar.tsx` | 文件浏览器侧边栏 |
| `screens/workspace/workspace-screen.tsx` | 工作区主屏幕 (3607行) |
| `components/message.tsx` | 消息组件 |
| `components/terminal-pane.tsx` | 终端面板 |
| `components/browser-pane.tsx` | 浏览器面板 |

### 状态管理
| 文件 | 说明 |
|------|------|
| `stores/panel-store.ts` | 面板状态 |
| `stores/session-store.ts` | 会话状态 |
| `stores/workspace-layout-store.ts` | 工作区布局 |
| `stores/workspace-tabs-store.ts` | 标签页状态 |

### Contexts
| 文件 | 说明 |
|------|------|
| `contexts/session-context.tsx` | 会话上下文 |
| `contexts/voice-context.tsx` | 语音上下文 |
| `contexts/toast-context.tsx` | Toast 提示 |

---

## 9. 总结

Paseo App 是一个基于 **Expo Router** 的跨平台应用，采用:
- **文件系统的路由** (app/ 目录)
- **Zustand** 进行状态管理
- **React Query** 进行数据获取
- **Unistyles** 进行样式管理
- 响应式设计支持移动端和桌面端

核心工作区界面通过 `WorkspaceScreen` 组件承载，支持多标签页、终端、浏览器、文件浏览器等多种面板组合。