# Anywhere HarmonyOS UI 美化计划

## 目标
全面提升 Anywhere HarmonyOS App 的视觉设计，从基础功能型 UI 升级为现代、精致、有层次感的专业界面。

## 当前问题

### 视觉问题
1. 颜色系统简单，缺少层次和现代感
2. 连接/断开页面视觉单调
3. 工作区选择页空状态简陋
4. 消息气泡样式基础
5. 使用文字符号代替图标（☰、▶、×）
6. 缺少阴影、动画等现代设计元素
7. 输入框和按钮样式朴素
8. 组件间缺少视觉区分度

### 布局问题
1. **WorkspaceDetailView 区域混杂**：Header、Toolbar、SessionBar、MessageList、ChatInput 直接堆叠，缺少区域分隔线，视觉上连成一片
2. **背景色层次混乱**：ToolbarRow 和 SessionBar 同为 surface0，无法区分功能区域；消息列表和输入框背景相同，边界不清
3. **连接页面布局单薄**：卡片内边距不足，元素间距紧凑，缺少视觉焦点和引导层次
4. **工作区选择页空状态简陋**：只有文字和按钮，没有插图或视觉引导，顶部菜单按钮位置突兀
5. **SessionBar 折叠设计粗糙**：触发条与下拉列表之间缺少视觉联系，当前会话高亮不突出
6. **ChatInputBar 边界不清**：输入框与消息列表之间无分隔，底部安全区域未考虑，输入框和按钮融合度差
7. **间距系统不统一**：各区域 padding 不一致（12/16/24混用），缺少统一的间距规范
8. **WorkspaceDrawer 比例失调**：宽度 78% 过大，工作区列表项缺少图标，底部 Host 信息与上方缺少分隔

## 修改文件清单

### 1. Colors.ets — 设计 Token 扩展
新增/修改内容：
- 添加 `surface3` (#D8DCE4) 用于更深的卡片背景
- 添加 `surfaceElevated` (#FFFFFF) 用于浮层卡片
- 添加 `border` (#D1D5DB) 用于边框
- 添加 `borderLight` (#E8EAED) 用于浅色边框
- 添加 `accentDark` (#156B3D) 用于强调色悬停/按下状态
- 添加 `accentTransparent` (#1A7F4B15) 用于强调色透明背景
- 修改 `surface0` 为 `#F0F2F5`（更温暖的灰）
- 修改 `surface1` 为 `#E8EBF0`（更温暖的灰）
- 修改 `assistantBubble` 为 `#F0F2F5` 与页面背景区分
- 添加 `shadowColor` 常量 `#00000015`
- 添加 `shadowColorStrong` 常量 `#00000025`
- 添加圆角常量：`radiusSm=8`, `radiusMd=12`, `radiusLg=16`, `radiusXl=20`, `radiusFull=999`

### 2. Index.ets — 主页面视图美化
改进内容：
- ConnectingView: 脉冲动画、精致阴影、品牌色装饰线、圆角 20
- DisconnectedView: 标题层次、输入框聚焦效果、按钮按下状态、卡片舒展
- WorkspaceSelectView: 空状态插图、大按钮+图标、工作区卡片列表
- WorkspaceHeader: 精致图标、底部边框、状态脉冲动画
- ToolbarRow: 底部边框、Select 背景圆角、圆形+按钮
- SessionBar: 折叠面板样式、箭头旋转、会话徽章
- ChatInputBar: 纯白输入框、聚焦边框、圆形发送按钮、顶部边框分隔

### 3. MessageBubble.ets — 消息气泡美化
- 用户气泡添加微妙阴影，圆角优化
- 助手气泡添加微妙阴影，圆角优化
- 添加消息时间戳
- 增加气泡间距
- 助手消息添加头像占位

### 4. ThinkingSection.ets — 思考区域美化
- 左侧 accent 色竖条装饰
- 标题行添加图标
- 展开/收起箭头旋转动画
- 圆角统一为 12

### 5. ToolCallCard.ets — 工具卡片美化
- 现代卡片设计，彩色圆形状态图标
- 左侧彩色竖条表示状态
- 微妙阴影，圆角 14
- in_progress 脉冲动画

### 6. PlanView.ets — 计划视图美化
- 标题添加图标
- 卡片式条目设计，序号/步骤编号
- 进度条显示完成比例
- 背景使用 surfaceElevated + 阴影

### 7. WorkspaceDrawer.ets — 抽屉面板美化
- 标题栏底部边框
- 工作区卡片式设计，左侧竖条指示器
- 工作区图标
- 底部 Host 信息卡片背景
- 连接状态脉冲动画

## 实现顺序
1. Colors.ets — 先扩展设计 Token
2. MessageBubble.ets — 核心聊天体验
3. ThinkingSection.ets + ToolCallCard.ets + PlanView.ets
4. WorkspaceDrawer.ets
5. Index.ets — 主页面视图

## 注意事项
- 符合 ArkTS 规则（无 any/unknown、@Builder 内不声明变量等）
- 颜色引用使用 Colors.xxx 常量
- ForEach key 保持稳定唯一
- 状态更新返回新引用
- Select 不支持 fontSize
- 使用 Unicode 符号替代图标资源
