import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';

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
  static readonly diffAddition: Resource = $r('app.color.diff_addition');
  static readonly diffDeletion: Resource = $r('app.color.diff_deletion');
  static readonly diffAdditionBg: Resource = $r('app.color.diff_addition_bg');
  static readonly diffDeletionBg: Resource = $r('app.color.diff_deletion_bg');
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
  static readonly xlg: number = 20; // lg→xl 之间平滑过渡
  static readonly xl: number = 24;
  static readonly xxl: number = 32;
  static readonly xxxl: number = 40;
}

export class Layout {
  static readonly pageGutter: number = 24;
  static readonly contentWidth: string = 'calc(100% - 48vp)';
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
  static readonly sm: number = 13;
  static readonly md: number = 14;
  static readonly base: number = 16;
  static readonly lg: number = 16;
  static readonly xl: number = 18;
  static readonly xxl: number = 20;
  static readonly xxxl: number = 22;
  static readonly xxxxl: number = 28;
  static readonly headingLg: number = 26;
  static readonly headingXl: number = 30;
}

export interface ShadowStyle {
  radius: number;
  color: ResourceColor;
  offsetY: number;
}

export class Shadow {
  static readonly xs: ShadowStyle = { radius: 3, color: Colors.shadow, offsetY: 1 };
  static readonly sm: ShadowStyle = { radius: 6, color: Colors.shadow, offsetY: 1 };
  static readonly md: ShadowStyle = { radius: 12, color: Colors.shadow, offsetY: 3 };
  static readonly lg: ShadowStyle = { radius: 20, color: Colors.shadow, offsetY: 6 };
  /** Subtle capsule shadow for floating input bar */
  static readonly capsule: ShadowStyle = { radius: 8, color: Colors.shadow, offsetY: 2 };
}

export class Duration {
  static readonly fast: number = 200;
  static readonly normal: number = 300;
  static readonly slow: number = 500;
  static readonly springCurve: Curve = Curve.Friction; // 类型与其它字段（number）不同，故用不同命名
}

/** Animation transition presets */
export class AnimationPresets {
  /** Fade in with spring curve */
  static readonly fadeIn: TransitionEffect = TransitionEffect.OPACITY
    .animation({ curve: curves.springMotion(0.6, 0.85) });

  /** Spring motion curve for property animations */
  static readonly spring: ICurve = curves.springMotion(0.6, 0.85);
}
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
