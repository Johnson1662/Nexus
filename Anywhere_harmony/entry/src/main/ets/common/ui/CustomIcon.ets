/**
 * CustomIcon — 基于 SVG 资源文件的自定义图标。
 * 使用 Image + fillColor 加载 resources/base/media/ 下的 SVG 文件。
 * ArkUI 原生处理 SVG viewBox 缩放，无需手动计算坐标。
 */
import { Colors } from '../../constants/DesignTokens';

@Component
export struct CustomIcon {
  @Prop name: string = '';
  @Prop iconSize: number = 24;
  @Prop color: ResourceColor = Colors.foreground;

  build() {
    Image(this.getResource())
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }

  private getResource(): Resource {
    const n: string = this.name.toLowerCase();

    if (n === 'stop' || n === 'cancel')       return $r('app.media.ic_stop');
    if (n === 'warning' || n === 'alert')     return $r('app.media.ic_warning');
    if (n === 'edit' || n === 'pencil')       return $r('app.media.ic_edit');
    if (n === 'tool' || n === 'wrench')       return $r('app.media.ic_wrench');
    if (n === 'progress' || n === 'spinner')  return $r('app.media.ic_progress');
    if (n === 'new_chat' || n === 'compose')  return $r('app.media.ic_new_chat');
    if (n === 'thinking')                     return $r('app.media.ic_thinking');
    if (n === 'thinking_done')                return $r('app.media.ic_check');

    // fallback
    return $r('app.media.ic_check');
  }
}
