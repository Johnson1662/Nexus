export class Colors {
  // Pure white and ultra-light grays to match Paseo style
  static readonly surface0: string = '#FFFFFF';
  static readonly surface1: string = '#F4F5F7';
  static readonly surface2: string = '#E5E7EB';
  static readonly surfaceElevated: string = '#FFFFFF';

  // Text — high contrast, never pure black
  static readonly foreground: string = '#1C1E21';
  static readonly foregroundMuted: string = '#6B717A';
  static readonly foregroundLight: string = '#9CA3AB';

  // Single accent
  static readonly accent: string = '#1A7F4B';
  static readonly accentDark: string = '#126839';
  static readonly accentLight: string = '#E2F3E9';
  static readonly accentTransparent: string = '#1A7F4B12';

  // Status
  static readonly success: string = '#059669';
  static readonly successLight: string = '#DCFCE7';
  static readonly warning: string = '#D97706';
  static readonly warningLight: string = '#FEF3C7';
  static readonly error: string = '#DC2626';
  static readonly errorLight: string = '#FEE2E2';

  // Borders
  static readonly border: string = '#D4D6DA';
  static readonly borderLight: string = '#EFEFEF';
  static readonly borderFocus: string = '#1A7F4B';

  // Shadows
  static readonly shadowColor: string = '#00000008';
  static readonly shadowColorStrong: string = '#00000014';
  static readonly shadowAccent: string = '#1A7F4B14';
}

export class Radius {
  static readonly sm: number = 6;
  static readonly md: number = 10;
  static readonly lg: number = 14;
  static readonly xl: number = 18;
  static readonly full: number = 999;
}

export class Spacing {
  static readonly xs: number = 3;
  static readonly sm: number = 6;
  static readonly md: number = 10;
  static readonly lg: number = 14;
  static readonly xl: number = 20;
  static readonly xxl: number = 28;
}

export class FontSize {
  static readonly xs: number = 11;
  static readonly sm: number = 13;
  static readonly base: number = 15;
  static readonly md: number = 17;
  static readonly lg: number = 20;
}
