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

    // 优先使用系统图标，这里只保留真正需要自定义的语义
    if (n === 'thinking')                     return $r('app.media.ic_thinking');
    if (n === 'thinking_done')                return $r('app.media.ic_check');
    if (n === 'knot' || n === 'logo')         return $r('app.media.ic_knot');

    // 以下语义建议在调用处直接使用 SymbolGlyph，此处仅作兜底兼容
    if (n === 'stop' || n === 'cancel')       return $r('app.media.ic_stop');
    if (n === 'warning' || n === 'alert')     return $r('app.media.ic_warning');
    if (n === 'edit' || n === 'pencil')       return $r('app.media.ic_edit');
    if (n === 'tool' || n === 'wrench')       return $r('app.media.ic_wrench');
    if (n === 'progress' || n === 'spinner')  return $r('app.media.ic_progress');
    if (n === 'new_chat' || n === 'compose')  return $r('app.media.ic_new_chat');
    if (n === 'waveform')                     return $r('app.media.ic_waveform');
    if (n === 'panel' || n === 'grid')        return $r('app.media.ic_panel');
    if (n === 'menu')                         return $r('app.media.ic_menu');
    if (n === 'dots' || n === 'more')         return $r('app.media.ic_dots');
    if (n === 'copy')                         return $r('app.media.ic_copy');
    if (n === 'paste')                        return $r('app.media.ic_paste');
    if (n === 'link')                         return $r('app.media.ic_link');
    if (n === 'close' || n === 'xmark')       return $r('app.media.ic_close');
    if (n === 'scan')                         return $r('app.media.ic_scan');
    if (n === 'model')                        return $r('app.media.ic_model');
    if (n === 'clear' || n === 'trash')       return $r('app.media.ic_clear');
    if (n === 'error')                        return $r('app.media.ic_error');

    // fallback
    return $r('app.media.ic_check');
  }
}
