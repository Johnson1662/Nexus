import 'package:flutter/material.dart';
import 'storage_service.dart';

/// Manages app-level preferences — mirrors ArkTS AppPreferenceService
class AppPreferenceService extends ChangeNotifier {
  static final AppPreferenceService _instance = AppPreferenceService._();
  factory AppPreferenceService() => _instance;
  AppPreferenceService._();

  // Language: 'system' | 'zh-Hans' | 'en-US'
  String _language = 'system';
  // Color mode: 'system' | 'light' | 'dark'
  String _colorMode = 'system';
  // Preferences
  bool thinkingExpanded = true;
  bool toolCallExpanded = false;

  String get language => _language;
  String get colorMode => _colorMode;

  static String normalizeLanguage(String? val) {
    if (val == 'zh-Hans' || val == 'zh' || val == 'zh-CN' || val == 'zh_CN') {
      return 'zh-Hans';
    }
    if (val == 'en-US' || val == 'en' || val == 'en_US') {
      return 'en-US';
    }
    return 'system';
  }

  static String normalizeColorMode(String? val) {
    if (val == 'light') return 'light';
    if (val == 'dark') return 'dark';
    return 'system';
  }

  ThemeMode get themeMode {
    switch (_colorMode) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> init() async {
    final storage = await StorageService.getInstance();
    _language = normalizeLanguage(storage.getString('pref_language'));
    _colorMode = normalizeColorMode(storage.getString('pref_color_mode'));
    thinkingExpanded = storage.getString('pref_thinking_expanded') != 'false';
    toolCallExpanded = storage.getString('pref_toolcall_expanded') == 'true';
  }

  Future<void> setLanguage(String lang) async {
    _language = normalizeLanguage(lang);
    final storage = await StorageService.getInstance();
    storage.putString('pref_language', _language);
    notifyListeners();
  }

  Future<void> setColorMode(String mode) async {
    _colorMode = normalizeColorMode(mode);
    final storage = await StorageService.getInstance();
    storage.putString('pref_color_mode', _colorMode);
    notifyListeners();
  }

  Future<void> setThinkingExpanded(bool value) async {
    thinkingExpanded = value;
    final storage = await StorageService.getInstance();
    storage.putString('pref_thinking_expanded', value.toString());
  }

  Future<void> setToolCallExpanded(bool value) async {
    toolCallExpanded = value;
    final storage = await StorageService.getInstance();
    storage.putString('pref_toolcall_expanded', value.toString());
  }
}
