import { Colors } from '../constants/Colors';
import { Radius, FontSize } from '../constants/DesignTokens';

export enum ButtonVariant {
  Primary = 'primary',
  Secondary = 'secondary',
  Danger = 'danger',
  Ghost = 'ghost'
}

export enum ButtonSize {
  Small = 'small',
  Medium = 'medium',
  Large = 'large'
}

@Component
export struct AppButton {
  @Prop label: string = '';
  @Prop variant: ButtonVariant = ButtonVariant.Primary;
  @Prop size: ButtonSize = ButtonSize.Medium;
  @Prop disabled: boolean = false;
  @Prop fullWidth: boolean = false;
  onClick?: () => void;
  
  private getBackgroundColor(): string {
    if (this.disabled) return Colors.surface2;
    switch (this.variant) {
      case ButtonVariant.Primary: return Colors.accent;
      case ButtonVariant.Secondary: return Colors.accentLight;
      case ButtonVariant.Danger: return Colors.error;
      case ButtonVariant.Ghost: return 'transparent';
      default: return Colors.accent;
    }
  }
  
  private getTextColor(): string {
    if (this.disabled) return Colors.foregroundMuted;
    switch (this.variant) {
      case ButtonVariant.Primary: return '#FFFFFF';
      case ButtonVariant.Secondary: return Colors.accent;
      case ButtonVariant.Danger: return '#FFFFFF';
      case ButtonVariant.Ghost: return Colors.foreground;
      default: return '#FFFFFF';
    }
  }
  
  private getHeight(): number {
    switch (this.size) {
      case ButtonSize.Small: return 36;
      case ButtonSize.Medium: return 44;
      case ButtonSize.Large: return 52;
      default: return 44;
    }
  }
  
  build() {
    Button(this.label)
      .width(this.fullWidth ? '100%' : undefined)
      .height(this.getHeight())
      .backgroundColor(this.getBackgroundColor())
      .fontColor(this.getTextColor())
      .fontSize(FontSize.md)
      .fontWeight(FontWeight.Medium)
      .borderRadius(Radius.md)
      .enabled(!this.disabled)
      .onClick(() => {
        if (this.onClick && !this.disabled) {
          this.onClick();
        }
      })
  }
}
