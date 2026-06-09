import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';

export class Colors {
  // Surfaces
  static readonly surface0: Resource = $r('app.color.surface0');
  static readonly surface1: Resource = $r('app.color.surface1');
  static readonly surface2: Resource = $r('app.color.surface2');
  static readonly surfaceElevated: Resource = $r('app.color.surface_elevated');

  // Foreground
  static readonly foreground: Resource = $r('app.color.foreground');
  static readonly foregroundMuted: Resource = $r('app.color.foreground_muted');
  static readonly foregroundLight: Resource = $r('app.color.foreground_light');

  // Accent
  static readonly accent: Resource = $r('app.color.accent');
  static readonly accentDark: Resource = $r('app.color.accent_dark');
  static readonly accentLight: Resource = $r('app.color.accent_light');
  static readonly accentTransparent: Resource = $r('app.color.accent_transparent');

  // Semantic
  static readonly success: Resource = $r('app.color.success');
  static readonly successLight: Resource = $r('app.color.success_light');
  static readonly warning: Resource = $r('app.color.warning');
  static readonly warningLight: Resource = $r('app.color.warning_light');
  static readonly warningFgDark: Resource = $r('app.color.warning_fg_dark');
  static readonly error: Resource = $r('app.color.error');
  static readonly errorLight: Resource = $r('app.color.error_light');
  static readonly errorFgDark: Resource = $r('app.color.error_fg_dark');
  static readonly timeoutBg: Resource = $r('app.color.timeout_bg');
  static readonly timeoutFg: Resource = $r('app.color.timeout_fg');

  // Border
  static readonly border: Resource = $r('app.color.border');
  static readonly borderLight: Resource = $r('app.color.border_light');
  static readonly borderFocus: Resource = $r('app.color.border_focus');

  // Special
  static readonly overlayDim: Resource = $r('app.color.overlay_dim');
  static readonly terminalBg: Resource = $r('app.color.terminal_bg');
  static readonly terminalFg: Resource = $r('app.color.terminal_fg');
  static readonly inlineCodeBg: Resource = $r('app.color.inline_code_bg');
  static readonly shadow: Resource = $r('app.color.shadow');

  static readonly transparent: string = 'transparent';
}

export class Spacing {
  static readonly xxs: number = 2;
  static readonly xs: number = 4;
  static readonly sm: number = 8;
  static readonly md: number = 12;
  static readonly lg: number = 16;
  static readonly xl: number = 20;
  static readonly xxl: number = 24;
  static readonly xxxl: number = 32;
}

export class Layout {
  static readonly pageGutter: number = 20;
  static readonly contentWidth: string = 'calc(100% - 40vp)';
}

export class Radius {
  static readonly xs: number = 4;
  static readonly sm: number = 8;
  static readonly md: number = 12;
  static readonly lg: number = 16;
  static readonly xl: number = 20;
  static readonly xxl: number = 24;
  static readonly full: number = 999;
}

export class FontSize {
  static readonly xxs: number = 8;
  static readonly xs: number = 10;
  static readonly sm: number = 12;
  static readonly md: number = 14;
  static readonly base: number = 15;
  static readonly lg: number = 16;
  static readonly xl: number = 18;
  static readonly xxl: number = 20;
  static readonly xxxl: number = 24;
  static readonly xxxxl: number = 28;
}

export interface ShadowStyle {
  radius: number;
  color: ResourceColor;
  offsetY: number;
}

export class Shadow {
  static readonly sm: ShadowStyle = { radius: 4, color: Colors.shadow, offsetY: 2 };
  static readonly md: ShadowStyle = { radius: 8, color: Colors.shadow, offsetY: 4 };
  static readonly lg: ShadowStyle = { radius: 16, color: Colors.shadow, offsetY: 8 };
}

export class Duration {
  static readonly fast: number = 200;
  static readonly normal: number = 300;
  static readonly slow: number = 500;
  static readonly spring: Curve = Curve.Friction;
}

/** Get localized string via UIContext-host context (non-deprecated path). */
export function getLocalizedString(context: common.Context, res: Resource, ...args: Array<string | number>): string {
  try {
    if (args.length === 0) {
      return context.resourceManager.getStringSync(res.id);
    }
    return context.resourceManager.getStringSync(res.id, ...args);
  } catch (_err) {
    return '';
  }
}
