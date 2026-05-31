/**
 * CustomIcon — 基于 ArkUI 原生 Shape 子组件的自定义矢量图标。
 * 使用 Rect/Circle/Polygon 等原生组件，天然适配任意尺寸。
 */
import { Colors } from '../../constants/DesignTokens';

@Component
export struct CustomIcon {
  @Prop name: string = '';
  @Prop iconSize: number = 24;
  @Prop color: ResourceColor = Colors.foreground;

  build() {
    Stack() {
      if (this.name === 'stop' || this.name === 'cancel') {
        // 停止：实心方块，居中约 60% 大小
        Rect()
          .width(this.iconSize * 0.55)
          .height(this.iconSize * 0.55)
          .fill(this.color)
          .radius(this.iconSize * 0.08)
      } else if (this.name === 'warning' || this.name === 'alert') {
        // 警告：三角 + 感叹号
        Column() {
          Polygon()
            .points(this.trianglePoints())
            .fill(this.color)
            .width(this.iconSize * 0.85)
            .height(this.iconSize * 0.62)
          // 感叹号竖线
          Rect()
            .width(this.iconSize * 0.08)
            .height(this.iconSize * 0.2)
            .fill(this.color)
            .margin({ top: this.iconSize * 0.02 })
          // 感叹号圆点
          Circle()
            .width(this.iconSize * 0.08)
            .height(this.iconSize * 0.08)
            .fill(this.color)
            .margin({ top: this.iconSize * 0.04 })
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else if (this.name === 'edit' || this.name === 'pencil') {
        // 铅笔：斜矩形条 + 三角形笔尖
        Row() {
          Rect()
            .width(this.iconSize * 0.1)
            .height(this.iconSize * 0.7)
            .fill(this.color)
            .borderRadius(this.iconSize * 0.02)
            .rotate({ angle: -30 })
          Polygon()
            .points(this.pencilTipPoints())
            .fill(this.color)
            .width(this.iconSize * 0.22)
            .height(this.iconSize * 0.35)
            .margin({ left: -this.iconSize * 0.02 })
            .rotate({ angle: -30 })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else if (this.name === 'thinking') {
        // 思考中：三个小圆点 (类似于省略号但垂直错位)
        Row({ space: this.iconSize * 0.1 }) {
          Circle().width(this.iconSize * 0.18).height(this.iconSize * 0.18).fill(this.color)
            .margin({ top: -this.iconSize * 0.1 })
          Circle().width(this.iconSize * 0.18).height(this.iconSize * 0.18).fill(this.color)
          Circle().width(this.iconSize * 0.18).height(this.iconSize * 0.18).fill(this.color)
            .margin({ top: -this.iconSize * 0.15 })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else if (this.name === 'thinking_done') {
        // 思考完成：对勾
        Polygon()
          .points(this.checkmarkPoints())
          .fill(this.color)
          .width(this.iconSize * 0.6)
          .height(this.iconSize * 0.45)
      } else if (this.name === 'tool' || this.name === 'wrench') {
        // 工具：大圆 + 矩形手柄
        Column() {
          Circle()
            .width(this.iconSize * 0.5)
            .height(this.iconSize * 0.5)
            .fill(this.color)
          Rect()
            .width(this.iconSize * 0.15)
            .height(this.iconSize * 0.35)
            .fill(this.color)
            .margin({ top: -this.iconSize * 0.02 })
            .borderRadius(this.iconSize * 0.03)
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else if (this.name === 'progress' || this.name === 'spinner') {
        // 旋转进度：圆弧 (用部分圆环模拟)
        Circle()
          .width(this.iconSize * 0.65)
          .height(this.iconSize * 0.65)
          .fill(Color.Transparent)
          .stroke(this.color)
          .strokeWidth(this.iconSize * 0.08)
          .strokeDashArray([this.iconSize * 1.0, this.iconSize * 2.0])
      } else if (this.name === 'new_chat' || this.name === 'compose') {
        // 新建会话：圆角矩形气泡 + 加号
        Stack() {
          Rect()
            .width(this.iconSize * 0.8)
            .height(this.iconSize * 0.65)
            .fill(this.color)
            .radius(this.iconSize * 0.15)
          // 小三角尾巴
          Polygon()
            .points(this.bubbleTailPoints())
            .fill(this.color)
            .width(this.iconSize * 0.2)
            .height(this.iconSize * 0.2)
            .margin({ left: -this.iconSize * 0.3, top: this.iconSize * 0.5 })
          // 加号
          Column() {
            Rect().width(this.iconSize * 0.28).height(this.iconSize * 0.06)
              .fill('#FFFFFF').borderRadius(this.iconSize * 0.03)
            Rect().width(this.iconSize * 0.06).height(this.iconSize * 0.28)
              .fill('#FFFFFF').borderRadius(this.iconSize * 0.03)
              .margin({ top: -this.iconSize * 0.06 })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .margin({ top: -this.iconSize * 0.02 })
        }
        .alignContent(Alignment.Center)
      } else {
        // 默认：圆点
        Circle()
          .width(this.iconSize * 0.5)
          .height(this.iconSize * 0.5)
          .fill(this.color)
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .alignContent(Alignment.Center)
  }

  private trianglePoints(): Array<[number, number]> {
    const s: number = this.iconSize;
    return [
      [s * 0.43, 0],
      [s * 0.85, s * 0.62],
      [0, s * 0.62]
    ];
  }

  private checkmarkPoints(): Array<[number, number]> {
    const s: number = this.iconSize;
    return [
      [0, s * 0.25],
      [s * 0.15, s * 0.1],
      [s * 0.4, s * 0.45],
      [s * 0.6, 0],
      [s * 0.45, s * 0.4],
      [s * 0.35, s * 0.35]
    ];
  }

  private pencilTipPoints(): Array<[number, number]> {
    const s: number = this.iconSize;
    return [
      [0, 0],
      [s * 0.22, s * 0.17],
      [0, s * 0.35]
    ];
  }

  private bubbleTailPoints(): Array<[number, number]> {
    const s: number = this.iconSize;
    return [
      [0, 0],
      [s * 0.2, 0],
      [0, s * 0.2]
    ];
  }
}
