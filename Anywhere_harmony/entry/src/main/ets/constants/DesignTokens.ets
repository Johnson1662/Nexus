export class Colors {
  static readonly surface0: string = '#FFFFFF';
  static readonly surface1: string = '#F4F5F7';
  static readonly surface2: string = '#E5E7EB';
  static readonly surfaceElevated: string = '#FFFFFF';
  static readonly userBubble: string = '#1A7F4B';

  static readonly foreground: string = '#1C1E21';
  static readonly foregroundMuted: string = '#6B717A';
  static readonly foregroundLight: string = '#9CA3AB';

  static readonly accent: string = '#1A7F4B';
  static readonly accentDark: string = '#126839';
  static readonly accentLight: string = '#E2F3E9';
  static readonly accentTransparent: string = '#1A7F4B12';

  static readonly success: string = '#059669';
  static readonly successLight: string = '#DCFCE7';
  static readonly warning: string = '#D97706';
  static readonly warningLight: string = '#FEF3C7';
  static readonly error: string = '#DC2626';
  static readonly errorLight: string = '#FEE2E2';

  static readonly border: string = '#D4D6DA';
  static readonly borderLight: string = '#EFEFEF';
  static readonly borderFocus: string = '#1A7F4B';

  static readonly shadowColor: string = '#00000008';
  static readonly shadowColorStrong: string = '#00000014';
  static readonly shadowAccent: string = '#1A7F4B14';
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
