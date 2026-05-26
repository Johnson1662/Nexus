# 原生鸿蒙组件前端改进计划

> 分析时间：2026-05-15
> 数据来源：华为官方开发者文档 harmonyos-guides, harmonyos-references, best-practices
> 
> **实施状态 (2026-05-26)：**
> - ✅ Navigation + NavPathStack 已替换手动 if/else 视图切换（Index.ets）
> - ✅ LazyForEach + @Reusable 已用于消息列表（ChatPage.ets + MessageCard.ets）
> - ✅ TextArea 已替代单行 TextInput（ChatInputBar.ets）
> - ✅ Markdown 渲染使用 @luvi/lv-markdown-in（MarkdownRender.ets）
> - ❌ SideBarContainer 尚未替换手动抽屉（仍使用 Stack.position + zIndex）
> - ❌ RelativeContainer 尚未用于布局优化
> - ❌ bindSheet 半模态弹窗尚未替换 PickerSheet

---

## 1. 现状分析

### 1.1 架构问题

| 现状 | 问题 |
|------|------|
| Index.ets 单文件通过 `Stack` + `if/else` 切换 5 个视图（连接中/发现代理/未连接/选代理/聊天） | 视图层级扁平但全部挤在一个文件，难以维护 |
| 工作区抽屉用 `Stack.position()` + `zIndex` 手动实现覆盖层 | 无原生动画、无手势关闭、无键盘避让 |
| 消息列表用 `List` + `Scroller.scrollEdge()` 手动滚动 | 缺少懒加载优化（大消息量时性能下降） |
| `ChatInputBar` 使用单行 `TextInput` | 无法多行输入，长文本体验差 |
| 状态管理使用 `@State` + `@Prop` + 手动数组覆盖 | 缺少 LocalStorage/AppStorage 持久化，重连后状态丢失 |
| 无系统级路由 | 依赖手动 `if/else` 切换视图 |

### 1.2 性能问题

- 消息列表使用 `ForEach`，未启用 `LazyForEach` 懒加载
- `MessageCard` 等列表项未使用 `@Reusable` 组件复用
- 首帧渲染节点数偏高（顶层一次性构建所有视图分支）
- 未使用 `RelativeContainer` 扁平化布局

---

## 2. 可用的原生 ArkUI 组件（取自 Huawei Docs）

以下组件均为 HarmonyOS 原生 API，可直接用于本项目的改进：

### 2.1 路由导航

**Navigation + NavPathStack**（API 10+）
- 来源：`arkts-navigation-navigation`
- 内置标题栏（title, menus, toolbarConfiguration）
- 支持 Stack/Split/Auto 三种模式
- NavPathStack 管理路由栈，替代手动 `if/else` 切换
- 内置返回键、安全区避让

**SideBarContainer**（API 8+）
- 来源：`ts-container-sidebarcontainer`
- 原生侧边栏容器，支持拖拽、自动隐藏
- 可分栏模式和浮动模式（Embed/Overlay/AUTO）
- 自带分割线（DividerStyle）、控制按钮、缩放动画
- 替代当前 `position({x:0,y:0})` + `zIndex` 手动抽屉

### 2.2 弹窗与面板

**bindSheet**（API 12+，推荐替代 Panel）
- 来源：通用属性 bindSheet（Panel 已废弃）
- 半模态面板，支持拖拽、多尺寸切换
- 适合: 代理选择器、设置面板

**bindContentCover / bindMenu**
- 用于: 全屏覆盖、上下文菜单

**CustomDialogController**
- 用于: 文件上传确认、错误提示、权限请求

### 2.3 文本输入

**TextArea**（API 7+）
- 来源：`ts-basic-components-textarea`
- 多行输入框，自动换行
- 支持 `maxLines`、`minLines`、`showCounter`
- 支持 `TextContentStyle.INLINE` 内联输入风格
- 替代 `ChatInputBar` 中的单行 TextInput

**RichEditor**（API 10+）
- 富文本编辑器，支持 Markdown 预览编辑
- 可作为进阶方案（替代当前输入+Markdown 分段渲染）

### 2.4 列表与滚动

**LazyForEach**（替代 ForEach）
- 来源：`arkts-rendering-control-lazyforeach`
- 懒加载创建列表项，10000 条消息不卡顿
- 配合 `@Reusable` 组件复用进一步优化

**@Reusable**（API 10+）
- 来源：`arkts-reusable`
- `MessageCard`、`ThinkingSection`、`ToolCallCard` 实现组件复用
- 显著降低 List 滑动时的 BuildLazyItem 耗时

**SwipeRefresher**（API 10+）
- 来源：`ohos-arkui-advanced-swiperefresher`
- 下拉刷新容器

### 2.5 布局优化

**RelativeContainer**（API 9+）
- 来源：`ts-container-relativecontainer`
- 相对定位布局，用二维坐标替代多层 Row/Column 嵌套
- 可减少 30%+ 布局节点数

**给定固定宽高**
- 来源：`bpta-improve-layout-performance`
- 固定宽高的组件在父容器变化时不触发 Measure，减少重绘耗时

### 2.6 状态与数据持久化

**LocalStorage**（页面级）
- UI 状态跨组件共享，不依赖手动传递 @Prop
- 适合: 连接状态、当前 sessionId、turnActive

**AppStorage**（应用级）
- 全局状态持久化，重连后自动恢复
- 适合: serverUrl、lastAgent、workspace 列表

**Preferences**（持久化存储）
- 来源：`data-persistence-by-preferences`
- 轻量级 key-value 持久化
- 适合: 服务器地址、上次选择的 agent

### 2.7 动画与过渡

**transition + animateTo**（API 7+）
- 视图切换过渡动画，替代生硬切换
- Navigation 自带 push/pop 页面转场

**geometryTransition**（API 10+）
- 共享元素过渡

---

## 3. 分阶段改进计划

### Phase 1: 架构重构（优先，影响面大）

**目标**: 替换手动视图管理为 Navigation 路由体系

```
当前: Index.ets (Stack + 5个 if/else 分支)
替换为:
  EntryAbility
    └── Navigation (NavPathStack)
          ├── NavDestination ("onboarding")  ← 连接/代理选择页面
          └── NavDestination ("chat")        ← 聊天主页面
```

改动文件:
| 文件 | 改动 |
|------|------|
| `pages/Index.ets` | 精简为 Navigation 根容器，移除所有 if/else 视图分支 |
| `feature/chat/ChatPage.ets` | 改为 NavDestination，独立生命周期 |
| `components/ConnectingView.ets` | 独立页面组件 |
| `components/DisconnectedView.ets` | 独立页面组件，含 IP 输入 + Connect 按钮 |
| `components/AgentSelectView.ets` | 独立页面组件，代理列表选择 |
| `components/WorkspaceSelectView.ets` | 独立页面组件，工作区选择 |

**迁移步骤**:

```ets
// 新 Index.ets — Navigation 根容器
@Entry
@Component
struct Index {
  private navStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navStack) {
      // 默认显示连接页面（作为首页）
    }
    .navDestination((name: string, param: unknown) => {
      if (name === 'onboarding') {
        DisconnectedView({ onConnected: () => { this.navStack.pushPath({ name: 'agent_select' }) } })
      } else if (name === 'agent_select') {
        AgentSelectView({ onSelected: (agent) => { this.navStack.pushPath({ name: 'workspace' }) } })
      } else if (name === 'workspace') {
        WorkspaceSelectView({ onReady: () => { this.navStack.pushPath({ name: 'chat' }) } })
      } else if (name === 'chat') {
        ChatPage({ navStack: this.navStack })
      }
    })
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }
}
```

### Phase 2: 侧边栏抽屉（高优先级）

**目标**: 替换手动覆盖层为 SideBarContainer

当前: `Index.ets:438-465` — 手动 position + zIndex
替换后: `SideBarContainer(SideBarContainerType.Overlay)`

```ets
SideBarContainer(SideBarContainerType.Overlay) {
  // 侧边栏内容
  WorkspaceDrawerContent({ ... })
  // 主内容区
  ChatPage({ ... })
}
.sideBarWidth(300)
.minSideBarWidth(200)
.maxSideBarWidth(360)
.showControlButton(false)
.autoHide(true)
.onChange((visible) => { if (!visible) { /* 关闭回调 */ } })
```

### Phase 3: 消息列表性能优化（高优先级）

**目标**: 大消息量下保持 60fps

| 改动 | 效果 |
|------|------|
| `ForEach` → `LazyForEach` + `IDataSource` | 避免全量渲染，10000 条消息保持流畅 |
| `MessageCard` 加 `@Reusable` | 滑动复用，Build 耗时降低 90% |
| 固定消息卡片宽高 | 减少 Measure 重算 |

```ets
@Component
@Reusable
export struct ReusableMessageCard {
  @State isUser: boolean = false;
  @State msgContent: string = '';
  // ...

  aboutToReuse(params: Record<string, object>): void {
    this.isUser = params.isUser as boolean;
    this.msgContent = params.msgContent as string;
  }
}
```

### Phase 4: 输入框升级（中优先级）

**目标**: 多行输入、更好的编辑体验

```ets
TextArea({
  placeholder: 'Enter command or message...',
  text: this.text,
  controller: this.textAreaController
})
  .style(TextContentStyle.INLINE)
  .maxLines(6)
  .minLines(1)
  .onChange((val) => { this.text = val })
  .onSubmit(() => { this.doSend() })
```

### Phase 5: 半模态弹窗（低优先级，UX 增强）

替换场景:

| 当前实现 | 替换为 |
|----------|--------|
| Agent 选择器（全屏列表面板） | `bindSheet` 半模态 |
| 文件上传占位 Toast | `bindSheet` 包含文件浏览器 |
| 设置/信息提示 Toast | `CustomDialogController` |

```ets
// bindSheet 示例
Button('Select Model')
  .bindSheet($$this.isModelSheetOpen, () => {
    Column() {
      ForEach(this.models, (model) => {
        Text(model.name).onClick(() => { this.selectModel(model) })
      })
    }
    .padding(24)
  }, { height: 400 })
```

### Phase 6: 状态管理升级（持续优化）

| 状态 | 当前 | 目标 |
|------|------|------|
| WebSocket URL | @State in Index | AppStorage('serverUrl') |
| 连接状态 | @State + ChatStore | LocalStorage + @Watch |
| 工作区列表 | WorkspaceStore 静态类 | AppStorage + Preferences |
| 上次选择 Agent | 无持久化 | Preferences |
| sessionId | ChatStore | LocalStorage（页面级） |

```ets
// AppStorage 示例
let serverUrl: string = AppStorage.setAndLink<string>('serverUrl', 'ws://100.111.77.50:6767');

@Entry
@Component
struct Index {
  @State @StorageLink('serverUrl') serverUrl: string = 'ws://100.111.77.50:6767';
  // 自动持久化、自动恢复
}
```

### Phase 7: 布局性能优化（低优先级）

- 使用 `RelativeContainer` 替代多层 Row/Column 嵌套
- 对不变化的组件设置固定 `width`/`height`
- 使用 `Visibility.Hidden` 替代 `if` 频繁切换的场景

---

## 4. 详细 API 参考（来自华为官方文档）

### 4.1 Navigation

```ets
// ts-basic-components-navigation（API 8+, 推荐 API 10+）
Navigation(pathInfos: NavPathStack)
// 属性:
.title('title') | .title({ main: '主标题', sub: '副标题' }, { barBackground: ... })
.menus([{ value: '菜单', icon: $r('app.media.icon') }])
.titleMode(NavigationTitleMode.Free | Mini | Full)
.toolbarConfiguration([{ value: '工具', icon: $r('app.media.tool'), action: () => {} }])
.hideTitleBar(true)
.hideToolBar(false)
.navDestination((name: string, param: unknown) => { /* builder */ })
```

### 4.2 SideBarContainer

```ets
// ts-container-sidebarcontainer（API 8+）
SideBarContainer(SideBarContainerType.Embed | Overlay | AUTO)
.showSideBar(true)              // 支持 $$ 双向绑定
.controlButton({ left: 16, top: 48, width: 24, height: 24, icons: { hidden: ..., shown: ... } })
.showControlButton(false)
.sideBarWidth(240)
.minSideBarWidth(200)
.maxSideBarWidth(300)
.autoHide(true)
.sideBarPosition(SideBarPosition.Start | End)
.divider({ strokeWidth: 2, color: '#E5E7EB', startMargin: 8, endMargin: 8 })
.minContentWidth(360)
.onChange((visible: boolean) => {})
```

### 4.3 bindSheet

```ets
// 通用属性（API 12+ 推荐替代 Panel）
.bindSheet($$isShow, () => { /* content */ }, {
  height: 400,         // 或 SheetHeight.LARGE | MEDIUM | SMALL
  backgroundColor: Color.White,
  cornerRadius: 16,
  dragBar: true,
  showClose: true,
  onDisappear: () => {}
})
```

### 4.4 TextArea

```ets
// ts-basic-components-textarea（API 7+）
TextArea({ placeholder: '...', text: $$text, controller: new TextAreaController() })
  .style(TextContentStyle.INLINE | DEFAULT)
  .maxLines(6)
  .minLines(1)
  .showCounter(true, { thresholdPercentage: 90 })
  .placeholderColor('#9CA3AB')
  .placeholderFont({ size: 15, weight: FontWeight.Normal })
  .fontSize(15)
  .caretColor('#1A7F4B')
  .copyOption(CopyOptions.LocalDevice)
```

### 4.5 LazyForEach

```ets
// arkts-rendering-control-lazyforeach
LazyForEach(this.messageDataSource, (msg: MessageData) => {
  ListItem() {
    MessageCard({ ... })
  }
}, (msg: MessageData) => msg.id)
```

### 4.6 @Reusable

```ets
// arkts-reusable（API 10+）
@Component
@Reusable
export struct MessageCard {
  @State isUser: boolean = false;
  @State msgContent: string = '';

  aboutToReuse(params: Record<string, object>): void {
    this.isUser = params.isUser as boolean;
    this.msgContent = params.msgContent as string;
  }

  build() { /* 组件 UI */ }
}
```

### 4.7 SwipeRefresher

```ets
// ohos-arkui-advanced-swiperefresher（API 10+）
SwipeRefresher() {
  List() { ... }
}
.onRefresh(() => { /* 重新连接/刷新会话列表 */ })
```

### 4.8 RelativeContainer

```ets
// ts-container-relativecontainer（API 9+）
RelativeContainer() {
  Row() { /* ... */ }.alignRules({
    top: { anchor: '__container__', align: VerticalAlign.Top },
    left: { anchor: '__container__', align: HorizontalAlign.Start },
    right: { anchor: '__container__', align: HorizontalAlign.End }
  })
  Button() { /* ... */ }.alignRules({
    bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
    right: { anchor: '__container__', align: HorizontalAlign.End }
  })
}
```

---

## 5. 收益预估

| 改进项 | 预估收益 |
|--------|----------|
| Navigation 路由 | 代码可维护性 +50%，单文件缩减 60% |
| SideBarContainer | 动画流畅度提升，手势支持，无额外实现成本 |
| LazyForEach + @Reusable | 消息量 >500 时丢帧率从 >10% 降至 <1% |
| TextArea 替代 TextInput | 多行输入支持，编辑体验提升 |
| bindSheet 替代全屏选择器 | UI 交互更原生，操作路径更短 |
| AppStorage/LocalStorage | 重连后状态自动恢复，消除状态丢失 |
| RelativeContainer | 布局节点减少 20-30%，重绘性能提升 |
| 固定宽高优化 | 频繁重绘场景性能提升 10-20 倍（参考官方数据） |

---

## 6. 图标全面替换：SymbolGlyph + SymbolSpan（原生系统图标）

### 6.1 背景

当前项目使用 24 个自定义 SVG 图标，存放在 `resources/base/media/ic_*.svg`，通过 `Image($r('app.media.ic_xxx')).fillColor(...)` 加载。

**HarmonyOS 系统内置 2000+ 原生图标**，通过 `SymbolGlyph($r('sys.symbol.xxx'))` 直接使用，无需任何 SVG 资源文件。

> 完整图标浏览: https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/
> 参考: `ts-basic-components-symbolglyph`（API 11+）

### 6.2 图标映射表

| SVG 文件 | 当前用法 | 原生替代（sys.symbol） | 备注 |
|----------|----------|----------------------|------|
| `ic_terminal.svg` | 终端 logo (Index.ets) | `$r('sys.symbol.terminal')` | 终端图标 |
| `ic_menu.svg` | 汉堡菜单 (Index.ets) | `$r('sys.symbol.line_horizontal_3')` | 三横线菜单 |
| `ic_clear.svg` | 清空会话 (Index.ets) | `$r('sys.symbol.trash')` 或 `$r('sys.symbol.xmark_bin')` | 垃圾桶/清除 |
| `ic_chevron_down.svg` | 下拉箭头 (Index.ets) | `$r('sys.symbol.chevron_down')` | 向下箭头 |
| `ic_panel.svg` | 面板图标 (Index.ets) | `$r('sys.symbol.sidebar_left')` | 面板/侧栏 |
| `ic_close.svg` | 关闭按钮 (WorkspaceDrawer) | `$r('sys.symbol.xmark')` | 关闭/叉号 |
| `ic_copy.svg` | 复制 (MessageCard) | `$r('sys.symbol.doc_on_doc')` | 复制文档 |
| `ic_check.svg` | 完成状态 (ToolCallCard) | `$r('sys.symbol.checkmark')` | 勾选 |
| `ic_error.svg` | 失败状态 (ToolCallCard) | `$r('sys.symbol.exclamationmark_triangle')` | 警告三角 |
| `ic_thinking.svg` | 思考中 (ThinkingSection) | `$r('sys.symbol.brain')` 或 `$r('sys.symbol.sparkles')` | 大脑/火花 |
| `ic_dots.svg` | 进行中状态 (PlanView) | `$r('sys.symbol.ellipsis')` | 三点 |
| `ic_circle.svg` | 待办状态 (PlanView) | `$r('sys.symbol.circle')` | 空心圆 |
| `ic_send_active.svg` | 发送 (ChatInputBar) | `$r('sys.symbol.arrow_up_circle_fill')` | 发送箭头 |
| `ic_send_disabled.svg` | 发送禁用 | `$r('sys.symbol.arrow_up_circle')` | 发送箭头（空） |
| `ic_attachment.svg` | 附件 (ChatInputBar) | `$r('sys.symbol.paperclip')` | 回形针 |
| `ic_mic.svg` | 语音 (ChatInputBar) | `$r('sys.symbol.mic')` | 麦克风 |
| `ic_waveform.svg` | 波形 (ChatInputBar) | `$r('sys.symbol.waveform')` | 声波 |
| `ic_model.svg` | 模型 (ChatInputBar) | `$r('sys.symbol.gear')` | 齿轮 |
| `ic_scan.svg` | 扫描 (未使用) | `$r('sys.symbol.qrcode_viewfinder')` | 二维码 |
| `ic_paste.svg` | 粘贴 (未使用) | `$r('sys.symbol.doc_on_clipboard')` | 剪贴板 |
| `ic_link.svg` | 链接 (未使用) | `$r('sys.symbol.link')` | 链接 |
| `ic_knot.svg` | 打结 (未使用) | `$r('sys.symbol.knot')` | 结 |
| `ic_tool.svg` | 工具 (未使用) | `$r('sys.symbol.wrench')` | 扳手 |

### 6.3 替换示例

```ets
// 当前: SVG 图标
Image($r('app.media.ic_terminal'))
  .fillColor(Colors.foreground).width(64).height(64)

// 替换: SymbolGlyph 原生系统图标
SymbolGlyph($r('sys.symbol.terminal'))
  .fontSize(64)
  .fontColor([Colors.foreground])

// 当前: 复制图标
Image($r('app.media.ic_copy'))
  .fillColor(Colors.foregroundLight).width(16).height(16)

// 替换
SymbolGlyph($r('sys.symbol.doc_on_doc'))
  .fontSize(16)
  .fontColor([Colors.foregroundLight])

// 当前: 多种状态的 ToolCallCard
Image($r('app.media.ic_check')).fillColor(Colors.success).width(16).height(16)
Image($r('app.media.ic_error')).fillColor(Colors.error).width(16).height(16)

// 替换: 带动效的原生图标
SymbolGlyph($r('sys.symbol.checkmark'))
  .fontSize(16)
  .fontColor([Colors.success])
  .effectStrategy(SymbolEffectStrategy.SCALE)  // 有动效！
```

### 6.4 收益

- 删除 24 个 SVG 文件，减少 APK 体积
- 图标自动适配系统主题（深色/浅色模式）
- 自带动效支持（scale/hierarchical/bounce/pulse）
- 多色渲染支持（单色/分层/多色）
- 无需手动 `fillColor` 配色调色
- 矢量无损缩放（基于 font-size，不再是 bitmap 缩放）

---

## 7. 完整原生组件清单

### 7.1 已使用的原生组件（保留）

| 组件 | 用途 | API |
|------|------|-----|
| `Text` | 所有文本显示 | `ts-basic-components-text` |
| `Button` | 按钮 | `ts-basic-components-button` |
| `TextInput` | 单行输入（可升级为 TextArea） | `ts-basic-components-textinput` |
| `Image` | 图标（可替换为 SymbolGlyph） | `ts-basic-components-image` |
| `List` + `ListItem` | 消息列表、代理列表 | `ts-container-list` |
| `Column` / `Row` | 基础布局 | `ts-basic-components-column` / `row` |
| `Stack` | 层叠布局 | `ts-container-stack` |
| `LoadingProgress` | 加载中动画 | `ts-basic-components-loadingprogress` |
| `Select` | 下拉选择模型/模式 | `ts-basic-components-select` |
| `Circle` | 小圆点装饰 | `ts-basic-components-circle` |
| `Divider` | 分割线 | `ts-basic-components-divider` |
| `Scroll` / `Scroller` | 滚动容器 | `ts-container-scroll` |
| `ForEach` | 列表渲染 | `arkts-rendering-control-foreach` |
| `Flex` | 弹性布局 | `ts-container-flex` |
| `Blank` | 空白填充 | `ts-basic-components-blank` |

### 7.2 可替换为原生组件

| 当前实现 | 原生替换 | 文档来源 |
|----------|----------|----------|
| `Image($r('app.media.ic_xxx'))` 24 个 SVG | **SymbolGlyph**(`$r('sys.symbol.xxx')`) | `ts-basic-components-symbolglyph` |
| `Stack` + `if/else` 切换 5 个视图 | **Navigation + NavPathStack** | `ts-basic-components-navigation` |
| `Stack.position()` + `zIndex` 手写抽屉 | **SideBarContainer** | `ts-container-sidebarcontainer` |
| 全屏代理/模型选择器 | **bindSheet** 半模态面板 | 通用属性 |
| `TextInput` 单行输入 | **TextArea** 多行 | `ts-basic-components-textarea` |
| `ForEach` 全量渲染 | **LazyForEach** 懒加载 | `arkts-rendering-control-lazyforeach` |
| 无复用 | **@Reusable** 组件复用 | `arkts-reusable` |
| 状态丢失 | **AppStorage / LocalStorage / Preferences** | 状态管理 |
| 深层 Row/Column 嵌套 | **RelativeContainer** 扁平化 | `ts-container-relativecontainer` |
| 手动滚动到底部 | **Scroll.scrollEdge()** + **Scroll.edgeEffect** | `ts-container-scroll` |
| `bindSheet` 需要 API 12+ | **bindContentCover** (API 10+) 替代方案 | 通用属性 |
| 手动主题管理 | **系统颜色资源** `$r('sys.color.xxx')` | 资源分类 |

### 7.3 其他可用原生组件（未来扩展）

| 组件 | 用途 | API |
|------|------|-----|
| **Badge** | 角标/未读标记 | `ts-container-badge` |
| **Toggle** | 开关/Switch 设置项 | `ts-basic-components-toggle` |
| **Swiper** | 图片/卡片轮播 | `ts-container-swiper` |
| **Counter** | 数字增减器 | `ts-basic-components-counter` |
| **Slider** | 滑块/进度调节 | `ts-basic-components-slider` |
| **Progress** | 进度条 | `ts-basic-components-progress` |
| **DataPanel** | 数据面板 | `ts-basic-components-datapanel` |
| **Gauge** | 仪表盘 | `ts-basic-components-gauge` |
| **QRCode** | 二维码生成 | `ts-basic-components-qrcode` |
| **PatternLock** | 图案锁 | `ts-basic-components-patternlock` |
| **TextClock** | 实时时钟 | `ts-basic-components-textclock` |
| **TextTimer** | 计时器 | `ts-basic-components-texttimer` |
| **AlphabetIndexer** | 字母索引（联系人列表） | `ts-container-alphabet-indexer` |
| **Search** | 搜索框 | `ts-basic-components-search` |
| **Menu** + **MenuItem** | 上下文菜单 | `ts-basic-components-menu` |
| **Hyperlink** | 超链接 | `ts-basic-components-hyperlink` |
| **RichEditor** | 富文本编辑器 | `ts-basic-components-richeditor` |
| **Web** | WebView 浏览器 | `ts-basic-components-web` |
| **XComponent** | 原生渲染节点 | `ts-basic-components-xcomponent` |
| **Canvas** / **Path** | 2D 绘图 | `ts-components-canvas-canvas` |
| **Shape** / **Rect** / **Circle** | 矢量图形 | `ts-basic-components-shape` |
| **Video** | 视频播放 | `ts-basic-components-video` |
| **Audio** | 音频控制（API 12+） | `ts-basic-components-audio` |
| **Animator** / **animateTo** | 动画控制 | `arkts-animation` |
| **geometryTransition** | 共享元素过渡 | `arkts-geometry-transition` |

---

## 8. 实施注意事项

1. **优先做 Phase 1 + Phase 2**：架构层面的改动应尽早进行，避免后续组件绑定旧架构
2. **SymbolGlyph 仅支持系统预置图标**：自定义图标仍需 SVG，但本项目 24 个图标全部有原生替代
3. **LazyForEach 注意点**：需要实现 `IDataSource` 接口，对消息增删改的触发方式与 `ForEach` 不同
4. **@Reusable 限制**：仅对系统组件和 `@State` 装饰的变量生效，复杂的内部状态需要手动在 `aboutToReuse` 中重置
5. **SideBarContainer 子组件限制**：不支持渲染控制类型（if/else, ForEach, LazyForEach）直接作为子组件
6. **Navigation navDestination builder**：builder 下只能有一个根节点
7. **AppStorage 仅支持 JSON 可序列化类型**，复杂类需要手动序列化
8. **bindSheet 需要 API 12+**，当前项目需确认 minCompatibleVersion
9. **SymbolGlyph 需要 API 11+**，当前项目需确认
10. **系统图标完整列表**：[HarmonyOS Symbol 图标库](https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/)（2000+ 个）
