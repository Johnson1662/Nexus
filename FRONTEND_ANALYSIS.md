# Anywhere 前端架构分析与优化方案

## 一、项目概览

Anywhere 是一个 HarmonyOS 原生应用，通过 WebSocket 连接远程 AI Coding Agent，提供移动端的代码辅助交互界面。

### 技术栈
- **框架**: ArkTS (HarmonyOS)
- **架构模式**: 单页面多视图切换
- **状态管理**: 自定义 SessionStore 类
- **通信**: WebSocket + JSON-RPC 2.0 (ACP 协议)

---

## 二、当前架构分析

### 2.1 页面架构

#### 核心结构
```
Index.ets (唯一页面)
├─ ConnectingView        # 连接中状态
├─ DisconnectedView      # 未连接状态
├─ WorkspaceSelectView   # 工作区选择
└─ WorkspaceDetailView   # 聊天主界面
   ├─ CombinedTopBar     # 顶部栏
   ├─ SessionCard        # 会话列表浮层
   ├─ EmptyChatView      # 空状态
   ├─ MessageList        # 消息列表
   └─ ChatInputBar       # 输入区
```

#### 优点
✅ **单页面架构简洁** - 避免页面跳转，状态管理集中  
✅ **视图切换清晰** - 通过状态控制不同视图显示  
✅ **组件化良好** - 子组件职责明确

#### 问题
❌ **Index.ets 过于庞大** - 1000+ 行代码，包含 8 个 @Builder 方法  
❌ **状态管理混乱** - 25+ 个 @State 变量，部分状态重复  
❌ **业务逻辑耦合** - 消息处理、会话管理、UI 渲染混在一起  
❌ **缺少常量管理** - 魔法数字和字符串散落各处

---

### 2.2 状态管理

#### SessionStore 设计
```typescript
SessionStore {
  // 工作区状态
  workspaces: WorkspaceInfo[]
  currentWorkspaceIndex: number
  
  // 会话状态
  currentSessionId: string
  messages: MessageData[]
  planEntries: PlanEntry[]
  turnActive: boolean
  
  // 模型状态
  model: string
  modelLabel: string
  cachedModels: ModelInfo[]
  cachedModes: ModeInfo[]
  
  // 缓存
  workspaceSessions: Map<string, ServerSession[]>
}
```

#### 优点
✅ **不可变更新** - 消息追加返回新数组，触发 UI 更新  
✅ **版本控制** - MessageData.version 配合 ForEach key 强制重渲染  
✅ **缓存机制** - 会话列表和模型列表缓存，减少网络请求

#### 问题
❌ **状态分散** - Index.ets 中有 25+ 个 @State，SessionStore 中又有状态  
❌ **双重管理** - workspaces、messages 等在两处都有副本  
❌ **缺少派生状态** - 如 `hasActiveSession`、`canSendMessage` 等需重复计算  
❌ **无状态持久化** - 刷新后工作区列表丢失

---

### 2.3 组件设计

#### 组件清单
| 组件 | 职责 | 行数 | 复杂度 |
|------|------|------|--------|
| MessageBubble | 消息气泡渲染 | 120 | 中 |
| ThinkingSection | 推理内容折叠 | 50 | 低 |
| ToolCallCard | 工具调用卡片 | 130 | 中 |
| PlanView | 计划列表 | 180 | 中 |
| WorkspaceDrawer | 工作区抽屉 | 200 | 高 |

#### 优点
✅ **职责单一** - 每个组件功能明确  
✅ **可复用性好** - 通过 @Prop 传递数据  
✅ **视觉一致** - 统一使用 Colors 常量

#### 问题
❌ **缺少原子组件** - 按钮、输入框等基础组件未封装  
❌ **样式重复** - 圆角、阴影、间距等样式代码重复  
❌ **缺少组合组件** - 如 StatusBadge、Avatar 等可复用元素  
❌ **无动画封装** - 动画逻辑散落在各组件中

---

### 2.4 设计系统

#### 当前 Colors.ets
```typescript
// 色彩 (13 个)
surface0, surface1, surface2, surfaceElevated
foreground, foregroundMuted, foregroundLight
accent, accentLight
success, warning, error + Light 变体
borderLight, borderFocus
shadowColor, shadowAccent

// 缺失
❌ 圆角常量
❌ 间距常量
❌ 字体大小
❌ 阴影层级
❌ 动画时长
```

#### 优点
✅ **语义化命名** - surface/foreground/accent 清晰  
✅ **状态色完整** - success/warning/error 三态齐全

#### 问题
❌ **不完整** - 只有颜色，缺少其他设计 Token  
❌ **硬编码尺寸** - 圆角、间距、字体大小散落在组件中  
❌ **无响应式** - 固定像素值，不支持不同屏幕尺寸  
❌ **缺少暗色主题** - 只有浅色主题

---

## 三、优化方案

### 3.1 页面架构优化

#### 方案：拆分 Index.ets 为多个视图组件

**目标结构**
```
pages/
├─ Index.ets (200 行)          # 主入口，状态管理
└─ views/
   ├─ ConnectingView.ets       # 连接中
   ├─ DisconnectedView.ets     # 未连接
   ├─ WorkspaceSelectView.ets  # 工作区选择
   └─ ChatView.ets             # 聊天主界面
      ├─ ChatHeader.ets        # 顶部栏
      ├─ SessionDrawer.ets     # 会话抽屉
      ├─ MessageList.ets       # 消息列表
      └─ ChatInput.ets         # 输入区
```

**优点**
- 单文件代码量降至 200 行以内
- 职责清晰，易于维护
- 可独立测试和优化

---

### 3.2 状态管理优化

#### 方案：统一状态管理，引入 @Observed/@ObjectLink

**优化后的 SessionStore**
```typescript
@Observed
export class AppState {
  // 连接状态
  connection: ConnectionState = {
    status: 'disconnected',
    hostName: '',
    hostUrl: ''
  }
  
  // 工作区状态
  workspace: WorkspaceState = {
    list: [],
    currentIndex: -1,
    sessions: new Map()
  }
  
  // 会话状态
  session: SessionState = {
    id: '',
    messages: [],
    planEntries: [],
    isActive: false
  }
  
  // 模型状态
  model: ModelState = {
    current: '',
    list: [],
    modes: []
  }
  
  // 派生状态 (getter)
  get hasActiveSession(): boolean {
    return this.session.id.length > 0;
  }
  
  get canSendMessage(): boolean {
    return this.connection.status === 'connected' && !this.session.isActive;
  }
  
  get currentWorkspace(): WorkspaceInfo | null {
    // ...
  }
}
```

**优点**
- 状态集中管理，避免分散
- 派生状态自动计算
- 类型安全，易于重构

---

### 3.3 组件设计优化

#### 方案 1：封装原子组件

**新增基础组件**
```
components/
├─ base/
│  ├─ Button.ets           # 统一按钮样式
│  ├─ Input.ets            # 统一输入框
│  ├─ Badge.ets            # 徽章
│  ├─ Avatar.ets           # 头像
│  ├─ Card.ets             # 卡片容器
│  └─ Divider.ets          # 分割线
├─ composed/
│  ├─ StatusBadge.ets      # 状态徽章
│  ├─ ConnectionStatus.ets # 连接状态指示器
│  └─ EmptyState.ets       # 空状态占位
└─ domain/
   ├─ MessageBubble.ets    # 消息气泡
   ├─ ThinkingSection.ets  # 推理内容
   ├─ ToolCallCard.ets     # 工具调用
   ├─ PlanView.ets         # 计划列表
   └─ WorkspaceDrawer.ets  # 工作区抽屉
```

#### 方案 2：优化现有组件

**MessageBubble 优化**
```typescript
// 当前问题：角色判断逻辑复杂
if (this.message.role === 'user') { ... }
else if (this.message.type === 'thinking') { ... }
else if (this.message.type === 'tool_call') { ... }
else { ... }

// 优化方案：策略模式
@Component
export struct MessageBubble {
  @Prop message: MessageData;
  
  build() {
    this.getBubbleComponent()
  }
  
  @Builder
  getBubbleComponent() {
    if (this.message.role === 'user') {
      UserBubble({ message: this.message })
    } else if (this.message.type === 'thinking') {
      ThinkingBubble({ message: this.message })
    } else if (this.message.type === 'tool_call') {
      ToolCallBubble({ message: this.message })
    } else {
      AssistantBubble({ message: this.message })
    }
  }
}
```

**ThinkingSection 优化**
```typescript
// 当前问题：展开/收起动画缺失
Text(this.expanded ? '▾' : '▸')

// 优化方案：添加旋转动画
Text('▸')
  .rotate({ angle: this.expanded ? 90 : 0 })
  .animation({
    duration: 200,
    curve: Curve.EaseInOut
  })
```

---

### 3.4 设计系统优化

#### 方案：完善 Design Tokens

**新增 DesignTokens.ets**
```typescript
export class DesignTokens {
  // 颜色 (保留 Colors.ets)
  
  // 间距
  static readonly spacing = {
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
    xxl: 24,
    xxxl: 32
  }
  
  // 圆角
  static readonly radius = {
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
    full: 999
  }
  
  // 字体大小
  static readonly fontSize = {
    xs: 10,
    sm: 12,
    md: 14,
    lg: 16,
    xl: 18,
    xxl: 20,
    xxxl: 24
  }
  
  // 字重
  static readonly fontWeight = {
    regular: FontWeight.Normal,
    medium: FontWeight.Medium,
    bold: FontWeight.Bold
  }
  
  // 阴影
  static readonly shadow = {
    sm: { radius: 4, color: '#00000008', offsetY: 2 },
    md: { radius: 8, color: '#00000010', offsetY: 4 },
    lg: { radius: 16, color: '#00000015', offsetY: 8 }
  }
  
  // 动画时长
  static readonly duration = {
    fast: 150,
    normal: 250,
    slow: 400
  }
  
  // 断点 (响应式)
  static readonly breakpoint = {
    sm: 360,
    md: 600,
    lg: 840
  }
}
```

---

## 四、优化优先级

### P0 - 必须优化（影响可维护性）
1. **拆分 Index.ets** - 降低单文件复杂度
2. **统一状态管理** - 避免状态分散和重复
3. **完善设计 Token** - 消除魔法数字

### P1 - 应该优化（提升代码质量）
4. **封装原子组件** - 提高复用性
5. **优化 MessageBubble** - 简化条件判断
6. **添加动画效果** - 提升用户体验

### P2 - 可以优化（锦上添花）
7. **状态持久化** - 本地存储工作区列表
8. **暗色主题** - 支持系统主题切换
9. **响应式布局** - 适配不同屏幕尺寸

---

## 五、具体实施步骤

### 阶段 1：设计系统优化（1-2 小时）
1. 创建 `DesignTokens.ets`，定义完整的设计 Token
2. 更新 `Colors.ets`，调整色彩命名
3. 在现有组件中替换硬编码值

### 阶段 2：状态管理重构（2-3 小时）
1. 创建 `AppState.ets`，定义统一状态结构
2. 迁移 SessionStore 逻辑到 AppState
3. 更新 Index.ets 使用新的状态管理

### 阶段 3：页面架构拆分（3-4 小时）
1. 创建 `views/` 目录
2. 提取 @Builder 方法为独立组件
3. 简化 Index.ets 为路由控制器

### 阶段 4：组件优化（2-3 小时）
1. 创建 `components/base/` 原子组件
2. 优化 MessageBubble 使用策略模式
3. 为 ThinkingSection 添加动画

### 阶段 5：测试与验证（1-2 小时）
1. 功能回归测试
2. 性能测试（渲染帧率）
3. 代码审查

**总计：9-14 小时**

---

## 六、预期收益

### 代码质量
- Index.ets 从 1000+ 行降至 200 行 ⬇️ 80%
- 组件平均行数从 150 行降至 80 行 ⬇️ 47%
- 状态变量从 25+ 个降至 5 个 ⬇️ 80%

### 可维护性
- 单一职责原则，易于定位问题
- 组件复用率提升 3 倍
- 新增功能开发时间减少 50%

### 用户体验
- 动画流畅度提升
- 视觉一致性增强
- 响应速度优化

---

## 七、风险与注意事项

### 技术风险
⚠️ **ArkTS 限制** - 不支持高阶组件、装饰器组合等高级特性  
⚠️ **状态更新机制** - @Observed/@ObjectLink 需要正确使用  
⚠️ **ForEach key 稳定性** - 必须保证唯一性，否则崩溃

### 兼容性风险
⚠️ **API 版本** - 确保 compileSdkVersion 支持新特性  
⚠️ **设备差异** - 不同设备的渲染性能差异

### 建议
✅ **增量重构** - 分阶段实施，每阶段验证  
✅ **保留备份** - 重构前创建 git 分支  
✅ **充分测试** - 每个阶段完成后进行回归测试

---

## 八、附录：代码示例

### 示例 1：原子组件 Button.ets
```typescript
import { Colors, DesignTokens } from '../constants';

export enum ButtonVariant {
  Primary = 'primary',
  Secondary = 'secondary',
  Danger = 'danger'
}

export enum ButtonSize {
  Small = 'small',
  Medium = 'medium',
  Large = 'large'
}

@Component
export struct AppButton {
  @Prop label: string = '';
  @Prop variant: ButtonVariant = ButtonVariant.Primary;
  @Prop size: ButtonSize = ButtonSize.Medium;
  @Prop disabled: boolean = false;
  onClick?: () => void;
  
  private getBackgroundColor(): string {
    if (this.disabled) return Colors.surface2;
    switch (this.variant) {
      case ButtonVariant.Primary: return Colors.accent;
      case ButtonVariant.Secondary: return Colors.surface1;
      case ButtonVariant.Danger: return Colors.error;
      default: return Colors.accent;
    }
  }
  
  private getTextColor(): string {
    if (this.disabled) return Colors.foregroundMuted;
    return this.variant === ButtonVariant.Primary || this.variant === ButtonVariant.Danger
      ? '#FFFFFF'
      : Colors.foreground;
  }
  
  private getHeight(): number {
    switch (this.size) {
      case ButtonSize.Small: return 36;
      case ButtonSize.Medium: return 44;
      case ButtonSize.Large: return 52;
      default: return 44;
    }
  }
  
  build() {
    Button(this.label)
      .height(this.getHeight())
      .backgroundColor(this.getBackgroundColor())
      .fontColor(this.getTextColor())
      .fontSize(DesignTokens.fontSize.md)
      .fontWeight(DesignTokens.fontWeight.medium)
      .borderRadius(DesignTokens.radius.md)
      .enabled(!this.disabled)
      .onClick(() => {
        if (this.onClick && !this.disabled) {
          this.onClick();
        }
      })
  }
}
```

### 示例 2：统一状态管理
```typescript
import { WorkspaceInfo, MessageData, PlanEntry, ServerSession, ModelInfo, ModeInfo } from './types';

export interface ConnectionState {
  status: 'disconnected' | 'connecting' | 'connected';
  hostName: string;
  hostUrl: string;
}

export interface WorkspaceState {
  list: WorkspaceInfo[];
  currentIndex: number;
  sessions: Map<string, ServerSession[]>;
}

export interface SessionState {
  id: string;
  title: string;
  messages: MessageData[];
  planEntries: PlanEntry[];
  isActive: boolean;
}

export interface ModelState {
  current: string;
  currentLabel: string;
  list: ModelInfo[];
  modes: ModeInfo[];
  currentModeIndex: number;
}

@Observed
export class AppState {
  connection: ConnectionState = {
    status: 'disconnected',
    hostName: '',
    hostUrl: ''
  };
  
  workspace: WorkspaceState = {
    list: [],
    currentIndex: -1,
    sessions: new Map()
  };
  
  session: SessionState = {
    id: '',
    title: '',
    messages: [],
    planEntries: [],
    isActive: false
  };
  
  model: ModelState = {
    current: '',
    currentLabel: 'Default',
    list: [],
    modes: [],
    currentModeIndex: 0
  };
  
  // 派生状态
  get isConnected(): boolean {
    return this.connection.status === 'connected';
  }
  
  get hasActiveSession(): boolean {
    return this.session.id.length > 0;
  }
  
  get canSendMessage(): boolean {
    return this.isConnected && !this.session.isActive;
  }
  
  get currentWorkspace(): WorkspaceInfo | null {
    if (this.workspace.currentIndex < 0 || this.workspace.currentIndex >= this.workspace.list.length) {
      return null;
    }
    return this.workspace.list[this.workspace.currentIndex];
  }
  
  get hasWorkspace(): boolean {
    return this.workspace.list.length > 0;
  }
  
  get workspaceSessions(): ServerSession[] {
    const ws = this.currentWorkspace;
    if (!ws) return [];
    return this.workspace.sessions.get(ws.path) || [];
  }
  
  // 操作方法
  addMessage(msg: MessageData): void {
    this.session.messages.push(msg);
  }
  
  appendToLastAssistantText(text: string): void {
    const msgs = this.session.messages;
    if (msgs.length > 0) {
      const last = msgs[msgs.length - 1];
      if (last.role === 'assistant' && last.type === 'text') {
        last.content += text;
        last.version += 1;
        return;
      }
    }
    
    this.addMessage({
      id: 'msg_' + Date.now(),
      role: 'assistant',
      content: text,
      type: 'text',
      version: 0,
      timestamp: Date.now()
    });
  }
  
  resetSession(): void {
    this.session = {
      id: '',
      title: '',
      messages: [],
      planEntries: [],
      isActive: false
    };
  }
}
```

---

## 九、总结

Anywhere 项目的前端架构整体设计合理，但存在以下核心问题：

1. **单文件过大** - Index.ets 承载过多职责
2. **状态分散** - 状态管理不统一
3. **设计系统不完整** - 缺少完整的 Design Tokens
4. **组件复用性低** - 缺少原子组件封装

通过本优化方案，可以显著提升代码质量、可维护性和用户体验，为后续功能扩展（文件上传、权限请求、多主机管理等）打下坚实基础。

建议采用**增量重构**策略，优先实施 P0 级优化，确保每个阶段都能独立验证和交付。
