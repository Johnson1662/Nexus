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
