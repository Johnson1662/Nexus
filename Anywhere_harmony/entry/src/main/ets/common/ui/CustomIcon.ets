/**
 * CustomIcon — 语义精确的自定义矢量图标。
 * 仅在系统符号库无合适语义匹配时使用。
 * SVG path 数据基于 24x24 viewBox，适配 ArkUI Path 组件的 commands 属性。
 */
import { Colors } from '../../constants/DesignTokens';

@Component
export struct CustomIcon {
  @Prop name: string = '';
  @Prop iconSize: number = 24;
  @Prop color: ResourceColor = Colors.foreground;

  build() {
    Path()
      .width(this.iconSize)
      .height(this.iconSize)
      .commands(this.getCommands())
      .fill(this.color)
      .stroke(Color.Transparent)
  }

  private getCommands(): string {
    const n = this.name.toLowerCase();

    // ── 操作类 ──────────────────────────────────────────
    if (n === 'stop' || n === 'cancel') {
      // 停止/取消：实心方块 (Material Design "stop")
      return 'M8 8h8v8H8z';
    }
    if (n === 'new_chat' || n === 'compose') {
      // 新建会话：带加号的消息气泡
      return 'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 11h-4v4h-2v-4H9v-2h4V7h2v4h4v2z';
    }

    // ── 思考/认知类 ──────────────────────────────────────
    if (n === 'thinking') {
      // 思考中：大脑/思维云 (简化的思维气泡轮廓)
      return 'M12 3C9.5 3 7.3 4.9 6.9 7.3C5.2 7.8 4 9.4 4 11.3c0 2.2 1.8 4 4 4h8c2.2 0 4-1.8 4-4 0-1.9-1.2-3.5-2.9-4.1C16.7 4.9 14.5 3 12 3zm0 2c1.7 0 3 1.3 3.1 3H15v1h1c.1.3.1.7.1 1 0 1.1-.9 2-2 2h-4.2c-1.1 0-2-.9-2-2 0-.3 0-.7.1-1H9V8h-.1C9 6.3 10.3 5 12 5z';
    }
    if (n === 'thinking_done') {
      // 思考完成：思维气泡+对勾
      return 'M12 3C9.5 3 7.3 4.9 6.9 7.3C5.2 7.8 4 9.4 4 11.3c0 2.2 1.8 4 4 4h1.2l.6 1.2 1.9-3.8 1.4 2.8.8-1.6H16c2.2 0 4-1.8 4-4 0-1.9-1.2-3.5-2.9-4.1C16.7 4.9 14.5 3 12 3zm-2.5 8.5L7 9l-1.4 1.4 3.9 3.9 1.4-1.4-1.4-1.4zm8.3 3.5l-1.8 1.8-1-1-1.4 1.4 2.4 2.4 3.2-3.2-1.4-1.4z';
    }

    // ── 工具调用类 ──────────────────────────────────────
    if (n === 'edit' || n === 'pencil') {
      // 编辑：铅笔
      return 'M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z';
    }
    if (n === 'tool' || n === 'wrench') {
      // 通用工具：扳手
      return 'M22.7 19l-9.1-9.1c.9-2.3.4-5-1.5-6.9-2-2-5-2.4-7.4-1.3L9 6 6 9 1.6 4.7C.4 7.1.9 10.1 2.9 12.1c1.9 1.9 4.6 2.4 6.9 1.5l9.1 9.1c.4.4 1 .4 1.4 0l2.3-2.3c.5-.4.5-1.1.1-1.4z';
    }
    if (n === 'progress' || n === 'spinner') {
      // 执行中：旋转进度环 (静态环，通过 animate rotation 动起来)
      return 'M12 4V2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10h-2c0 4.4-3.6 8-8 8s-8-3.6-8-8 3.6-8 8-8z';
    }

    // ── 状态/警告类 ──────────────────────────────────────
    if (n === 'warning' || n === 'alert') {
      // 警告：感叹号三角
      return 'M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z';
    }

    // ── 回退：默认圆形 (不可达时的标记) ──────────────────
    return 'M12 2C6.48 2 2 6.48 2 12s4.48 10 12 10 12-4.48 12-10S17.52 2 12 2z';
  }
}
