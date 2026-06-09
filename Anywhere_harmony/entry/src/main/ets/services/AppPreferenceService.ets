import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';

export class AppPreferenceService {
  static readonly LANGUAGE_SYSTEM: string = 'system';
  static readonly LANGUAGE_ZH: string = 'zh-Hans';
  static readonly LANGUAGE_EN: string = 'en-US';

  static readonly COLOR_SYSTEM: string = 'system';
  static readonly COLOR_LIGHT: string = 'light';
  static readonly COLOR_DARK: string = 'dark';

  static setPreferenceState(key: string, value: string): void {
    try {
      if (!AppStorage.set<string>(key, value)) {
        AppStorage.setOrCreate<string>(key, value);
      }
    } catch (_err) {
      AppStorage.setOrCreate<string>(key, value);
    }
  }

  static normalizeLanguage(value: string): string {
    if (value === AppPreferenceService.LANGUAGE_ZH || value === 'zh' || value === 'zh-CN' || value === 'zh_CN') {
      return AppPreferenceService.LANGUAGE_ZH;
    }
    if (value === AppPreferenceService.LANGUAGE_EN || value === 'en' || value === 'en_US') {
      return AppPreferenceService.LANGUAGE_EN;
    }
    return AppPreferenceService.LANGUAGE_SYSTEM;
  }

  static getRuntimeSystemLanguage(): string {
    let language: string = '';
    try {
      language = i18n.System.getSystemLanguage();
    } catch (_err) {}
    if (language.length === 0) {
      try {
        language = i18n.System.getFirstPreferredLanguage();
      } catch (_err) {}
    }
    if (language.length === 0) return 'default';

    let lower: string = language.toLowerCase();
    if (lower.startsWith('zh')) return AppPreferenceService.LANGUAGE_ZH;
    if (lower.startsWith('en')) return AppPreferenceService.LANGUAGE_EN;
    return language;
  }

  static normalizeColorMode(value: string): string {
    if (value === AppPreferenceService.COLOR_LIGHT) return AppPreferenceService.COLOR_LIGHT;
    if (value === AppPreferenceService.COLOR_DARK) return AppPreferenceService.COLOR_DARK;
    return AppPreferenceService.COLOR_SYSTEM;
  }

  static applyLanguage(value: string): boolean {
    try {
      let language: string = AppPreferenceService.normalizeLanguage(value);
      i18n.System.setAppPreferredLanguage(language === AppPreferenceService.LANGUAGE_SYSTEM ?
        AppPreferenceService.getRuntimeSystemLanguage() : language);
      return true;
    } catch (_err) {
      return false;
    }
  }

  static applyColorMode(context: common.Context, value: string): boolean {
    try {
      let mode: string = AppPreferenceService.normalizeColorMode(value);
      let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === AppPreferenceService.COLOR_LIGHT) {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (mode === AppPreferenceService.COLOR_DARK) {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      context.getApplicationContext().setColorMode(colorMode);
      return true;
    } catch (_err) {
      return false;
    }
  }
}
