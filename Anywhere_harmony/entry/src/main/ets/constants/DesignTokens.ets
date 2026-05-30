import { resourceManager } from '@kit.LocalizationKit';

export class Colors {
  // Surfaces
  static readonly surface0: Resource = $r('app.color.surface0');
  static readonly surface1: Resource = $r('app.color.surface1');
  static readonly surface2: Resource = $r('app.color.surface2');
  static readonly surfaceElevated: Resource = $r('app.color.surface_elevated');
  static readonly userBubble: Resource = $r('app.color.user_bubble');

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
  static readonly onboardingBg: Resource = $r('app.color.onboarding_bg');
  static readonly inlineCodeBg: Resource = $r('app.color.inline_code_bg');

  // String fallbacks for runtime logic (no dark-mode switch needed for these)
  static readonly transparent: string = 'transparent';
  static readonly colorWhite: string = '#FFFFFF';
  static readonly colorBlack: string = '#000000';
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
  color: string;
  offsetY: number;
}

export class Shadow {
  static readonly sm: ShadowStyle = { radius: 4, color: '#00000008', offsetY: 2 };
  static readonly md: ShadowStyle = { radius: 8, color: '#00000010', offsetY: 4 };
  static readonly lg: ShadowStyle = { radius: 16, color: '#00000015', offsetY: 8 };
}

export class Duration {
  static readonly fast: number = 150;
  static readonly normal: number = 250;
  static readonly slow: number = 400;
  static readonly slower: number = 600;
}

/** Get localized string. Caches result to avoid repeated resourceManager lookups. */
export function getLocalizedString(res: Resource): string {
  return getContext().resourceManager.getStringSync(res);
}