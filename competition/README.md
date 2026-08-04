# Nexus 初赛提交材料清单

## 已准备

| 文件 | 说明 | 状态 |
|------|------|------|
| `01-作品说明文档.docx` | 基于官方模板填写，含封面信息、创意描述、技术方案 | ✅ 待补充学校和团队信息 |
| `02-演示视频.mp4` | 15 秒 Remotion 动态演示视频（1080p/30fps） | ✅ 可替换为更完整的版本 |
| `03-Nexus-演示包.zip` | 内含 Nexus-demo.hap + 核心源码（Flutter Dart + Node.js Server） | ✅ |

## 需要你手工完成的

1. **打开 `01-作品说明文档.docx`**，填写：
   - 学校名称
   - 团队名称
   - 队长姓名 + 联系电话
   - 团队成员信息表
   - 创意描述（300字内，已预填草稿）
   - 设计稿/技术方案（已预填草稿，可扩展）

2. **文件最终命名**（按比赛要求）：
   - `01-作品说明文档+参赛队伍名称.pdf`（Word 导出为 PDF）
   - `02-演示视频+参赛队伍名称.mp4`
   - `03-作品名称+参赛队伍名称.zip`

3. **可选增强**：
   - 设计稿/宣传海报（图片）
   - 演示 PPT
   - 更完整的演示视频（5 分钟内，建议加入真机录屏）

## 设计稿与宣传材料

| 文件 | 说明 | 用法 |
|------|------|------|
| `design-showcase.html` | 宣传海报 + 交互流程图 + 界面预览 | 浏览器打开 → 打印 → 另存为 PDF |

```powershell
# 构建
cd nexus_flutter/ohos
$env:NODE_OPTIONS=""
devecocli build --build-mode debug

# 连接设备 + 安装
hdc tconn <IP>:<PORT>
hdc -t "<IP>:<PORT>" install entry/build/default/outputs/default/entry-default-signed.hap

# 启动
hdc -t "<IP>:<PORT>" shell aa start -a EntryAbility -b com.nexus.remoteai
```
