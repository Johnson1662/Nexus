# Anywhere Markdown + 数学公式渲染集成计划

> **目标：** 在 Anywhere HarmomyOS App 中，将 Agent 响应的纯文本渲染升级为完整的 Markdown 渲染，支持表格、代码块、LaTeX 数学公式等，保持流式更新的兼容性和终端风格的视觉一致性。

---

## 一、现状分析

### 当前渲染链路

```
Agent (ACP) → WebSocket → AppState.appendToLastAssistantText()
  → ForEach + MessageCard → Text(this.msgContent)
```

- Agent 回复直接作为纯文本塞进 `Text()` 组件
- 流式更新靠 ForEach key `msg.id + msg.content.length` 触发重渲染
- 无 Markdown/LaTeX 处理，代码块和表格在手机上是纯文本

### 选型确认：@luvi/lv-markdown-in ✅

基于之前的调研结论，使用该库的理由：

| 需求 | 支持 |
|---|---|
| Markdown 基础语法 | ✅ |
| 表格（带隔行变色等样式 API） | ✅ |
| LaTeX 数学公式（`$...$`, `$$...$$`） | ✅ |
| 代码块（亮/暗主题） | ✅ |
| 流式增量渲染 | ✅（`streamMode` 参数） |
| Worker 子线程（不阻塞 UI） | ✅ |
| 50+ 自定义样式 API | ✅ |
| 原生 ArkUI 渲染（无 WebView） | ✅ |
| 超链接/图片/公式点击事件 | ✅ |

---

## 二、实现步骤

### Step 1：安装依赖

在 `Anywhere_harmony` 项目根目录执行：

```bash
cd entry
ohpm install @luvi/lv-markdown-in
```

如果 ohpm 装在系统别处，用完整路径：

```bash
node "D:\DevEco Studio\tools\ohpm\bin\ohpm" install @luvi/lv-markdown-in
```

这会自动更新 `oh-package.json5` 和 `oh_modules/`。

### Step 2：创建 MarkdownRender 组件

**路径：** `common/ui/MarkdownRender.ets`

职责：
1. 封装 `@luvi/lv-markdown-in` 的 `Markdown` 组件
2. 注入当前项目的设计 Token（字体颜色、间距、代码主题）
3. 提供 `streamMode` 开关
4. 处理长内容的 Scroll 联动

```typescript
// common/ui/MarkdownRender.ets
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { Colors } from '../../constants/Colors';

@Component
export struct MarkdownRender {
  @Prop text: string = '';
  @Prop streamMode: boolean = false;
  @Prop mathEnabled: boolean = true;

  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    // 注入项目设计 Token
    this.controller.setCodeBlockTheme('light');
    this.controller.setTextColor(Colors.foreground);
    this.controller.setTextSize(14);
    this.controller.setTableBackgroundColor(Colors.surfaceElevated);
    this.controller.setTableInterleaveBackgroundColor(Colors.surface1);
    this.controller.setBlockSpacing(8);
    // 公式点击可放大交互
    this.controller.setLatexClickListener((text, pixelMap) => {
      // 可选：弹出公式大图
      return true;
    });
  }

  build() {
    Markdown({
      text: this.text,
      controller: this.controller,
      streamMode: this.streamMode
    })
    .width('100%')
  }
}
```

### Step 3：修改 MessageCard 集成渲染器

**目标文件：** `common/ui/MessageCard.ets`

当前：
```typescript
if (this.msgContent.length > 0) {
  Text(this.msgContent)  // ❌ 纯文本
    .fontSize(FontSize.base)...
}
```

修改为：
```typescript
if (this.msgContent.length > 0) {
  MarkdownRender({
    text: this.msgContent,
    streamMode: true,   // 流式下开 streamMode
    mathEnabled: true
  })
}
```

**区分用户消息/Agent 消息：**
- 用户消息（纯文本短消息）→ 维持 `Text()` 不变（性能优化）
- Agent 消息 → 使用 `MarkdownRender`
- ThinkingContent → 维持 `ThinkingSection` 不变（展开/折叠纯文本）
- ToolCall → 维持 `ToolCallCard` 不变

### Step 4：处理流式更新兼容性

当前流式更新机制：
```typescript
// Index.ets / AppState.ets
appendToLastAssistantText(text: string): MessageData[] {
  const last = this.messages[this.messages.length - 1];
  if (last.role === 'assistant' && last.type === 'text') {
    last.content += text;   // 追加文本
    return [...this.messages]; // 触发 @State 更新
  }
}
```

`@luvi/lv-markdown-in` 的 `streamMode` 设计为可以直接接收增量文本，但需要确认它是否支持渐进式追加，还是需要完整文本。

**两种方案，根据实际测试选择：**

**方案 A：streamMode 原生支持（推荐）**
```typescript
// 直接设置 text 属性，组件内部处理增量渲染
// MessageCard 中
MarkdownRender({ text: this.msgContent, streamMode: true })
```
每次 content 更新时，markdown 组件会增量解析增量渲染，不会从头重新渲染整段内容。

**方案 B：降级为完整文本重渲染**
如果 streamMode 在分批追加时闪烁或性能不佳：
```typescript
// 收集完整文本后再渲染（等 turn_ended 后才渲染 Markdown）
// streaming 期间仍然显示纯 Text
@State showMarkdown: boolean = false;

// 在 turn ended 后切换
this.showMarkdown = true;
```
但这样会失去流式滚动的体验，**不推荐优先采用**。

### Step 5：数学公式专用配置

LaTeX 公式渲染需要额外配置：

```typescript
// 开启公式支持（默认可能关闭，需显式开启）
this.controller.setLatexEnable(true);

// 公式点击事件（放大查看）
this.controller.setLatexClickListener((text, pixelMap) => {
  // text: 公式 LaTeX 源代码 ($E=mc^2$)
  // pixelMap: 渲染后的位图，可用于弹窗大图展示
  promptAction.showDialog({ message: text });
  return true;
});

// 公式样式
this.controller.setLatexTextColor('#333333');
this.controller.setLatexFontSize(16);
```

### Step 6：处理超链接交互

Agent 回复中的链接需要可点：

```typescript
this.controller.setHyperlinkClickListener((title, src, anchorInfo) => {
  if (!anchorInfo) {
    // 外部链接 → 用系统浏览器打开
    openLink(src);
    return true;  // 阻止默认行为
  }
  // 锚点链接 → 滚动
  if (this.scroller && anchorInfo) {
    this.scroller.scrollTo({
      yOffset: px2vp(anchorInfo.screenOffset.y)
    });
    return true;
  }
  return false;
});
```

### Step 7：代码块复制

`@luvi/lv-markdown-in` v3.1.0+ 禁用了自动剪贴板，需要手动处理：

```typescript
this.controller.setCodeCopyListener((text: string) => {
  let pasteData = pasteboard.createData(
    pasteboard.MIMETYPE_TEXT_PLAIN, text
  );
  let systemPasteboard = pasteboard.getSystemPasteboard();
  systemPasteboard.setData(pasteData).then(() => {
    promptAction.showToast({
      message: 'Code copied to clipboard',
      bottom: 80
    });
  });
});
```

> 复用 `MessageCard.ets` 中已有的 `@ohos.pasteboard` 复制逻辑。

---

## 三、文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `entry/oh-package.json5` | 修改 | 添加 `@luvi/lv-markdown-in` 依赖 |
| `common/ui/MarkdownRender.ets` | **新建** | Markdown 渲染封装组件 |
| `common/ui/MessageCard.ets` | 修改 | Agent 文本消息改用 MarkdownRender |
| `feature/chat/ChatPage.ets` | 无需修改 | 只传数据，不涉及渲染逻辑 |
| 其他 | — | 架构不变，纯组件替换 |

---

## 四、测试验证

### 4.1 测试内容列表

| 测试项 | 预期结果 | 优先级 |
|--------|----------|--------|
| 普通 Markdown 文本渲染 | 加粗、列表、标题正常显示 | P0 |
| 表格渲染 | 表格正常且有隔行变色 | P0 |
| LaTeX 行内公式 `$...$` | 公式被正确渲染，不出现原始代码 | P0 |
| LaTeX 块级公式 `$$...$$` | 居中渲染 | P0 |
| 代码块渲染 | 亮色主题，行号可选，可复制 | P1 |
| 流式增量渲染 | 文字渐出，不闪烁 | P0 |
| 超链接点击 | 系统浏览器打开 | P1 |
| 公式点击 | 弹窗显示公式源码 | P2 |
| 用户消息样式 | 仍为纯 Text，不受影响 | P1 |
| 长内容性能 | 无卡顿，Worker 工作正常 | P1 |

### 4.2 测试数据

```markdown
# 标题测试

## 表格

| 模型 | 速度 | 价格 |
|------|------|------|
| DeepSeek V4 | 快 | $0.20 |
| GPT-4o | 中 | $2.50 |

## 公式

质能方程：$E = mc^2$

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

## 代码

```typescript
const greet = (name: string): string => {
  return `Hello, ${name}!`;
};
```

## 列表
1. 第一项
2. 第二项

- 无序项
- 无序项
```

通过 Agent 回复发送上述样本文本，目视验证渲染效果。

### 4.3 回归测试

- 在 `@State messages` 流式追加场景下反复测试 5+ 轮，确认无内存泄漏或 UI 卡顿
- 在 `turn_ended` 后加载已有 session 的历史消息（批量而非流式），确认 MarkdownRender 能处理完整文本而非增量

---

## 五、回退方案

如果 `@luvi/lv-markdown-in` 在某些场景下不稳定：

1. **ArkWeb + markdown-it + KaTeX：** 使用 HarmonyOS 的 `Web` 组件加载本地 HTML，用标准前端库渲染。缺点是引入 WebView 开销和加载延迟。
2. **服务端预渲染：** PC bridge（server.js）在返回前将 Markdown 转为 HTML 片段，App 端用 Web 组件展示。缺点：增加 server 依赖和延迟。

---

## 六、交付标准

- [ ] `ohpm install @luvi/lv-markdown-in` 成功，编译通过
- [ ] MarkdownRender 组件独立可用
- [ ] Agent 回复中的表格正确渲染
- [ ] Agent 回复中的数学公式正确渲染
- [ ] 流式场景下无闪烁/卡顿
- [ ] 代码块可复制
- [ ] 超链接可点击
- [ ] 用户消息仍为纯文本
- [ ] 所有现有功能回归通过
