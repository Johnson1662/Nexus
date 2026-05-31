# Product

## Register

product

## Users
开发者和工程师。他们需要通过 HarmonyOS 手机随时随地访问 PC 端的 AI 编程代理（如 OpenCode, Claude Code）。使用场景多为移动办公、碎片化时间或远程协作，需要快速、稳定、清晰地与代码 Agent 进行交互。

## Product Purpose
Anywhere 是一个 HarmonyOS App，作为手机上的移动开发工作区。通过混合中继架构连接 PC 端 Bridge Server，利用 ACP 协议与 AI 编程代理通信。成功的产品应该在移动端提供无缝、高响应、可靠且类似终端的专业聊天体验。

## Brand Personality
专注、极简、平静、专业。高信噪比。采用类似 ChatGPT 的黑白灰单色调风格（#202123, #F4F4F4, #6B7280），体现工具的纯粹感和技术感。

## Anti-references
- 避免花哨的渐变色和无意义的毛玻璃（Glassmorphism）装饰。
- 避免拥挤、繁杂的“工具箱”式界面。
- 避免过度消费级（Consumer-heavy）的 UI，如不必要的插画或多余的表情符号。
- 避免在移动端难以阅读的过密布局。

## Design Principles
- **内容优先 (Content over Chrome)**：Agent 输出的代码和思考链是界面的绝对核心，UI 框架应当尽可能隐形。
- **极致清晰 (Exceptional Clarity)**：通过排版、字号对比和留白瞬间传达信息的层级结构。
- **原生流畅 (Native Fluidity)**：严格优先使用 HarmonyOS 原生组件（如 NavPathStack, bindSheet），保障系统级的丝滑动画与无障碍支持。
- **可靠感知 (Unyielding Reliability)**：网络状态、端到端加密、心跳重连等后台机制需以克制且清晰的方式呈现，不打扰用户但随时可知。

## Accessibility & Inclusion
- 高对比度文本（遵循单色调背景）。
- 在移动端适合阅读密集代码和 Markdown 的合理字号及行高。
- 系统状态（如 Thinking、Tool Call、Connected）必须有清晰的视觉提示，不纯依赖颜色区分。