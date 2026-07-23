import 'package:flutter/material.dart';

/// Design tokens — Refined minimalist greyscale + confident blue accent.
/// Inspired by Linear / Apple system aesthetics: soft cool neutrals,
/// a single confident accent, borderless surfaces lifted by diffuse shadows.
class AppColors {
  AppColors._();

  // ── Light ──
  static const _bg = Color(0xFFF6F7F9); // soft cool off-white (not dead grey)
  static const _srf = Color(0xFFFFFFFF); // pure surface
  static const _srf2 = Color(0xFFEEF0F4); // subtle cool fill (chips / inputs)
  static const _srfElevated = Color(0xFFFFFFFF);
  static const _fg = Color(0xFF16181D); // near-black, slightly cool
  static const _fgMuted = Color(0xFF6B7280); // legible slate grey
  static const _fgLight = Color(0xFF9AA1AD);
  static const accent = Color(0xFF2563EB); // confident, modern blue (not plastic sky)
  static const accentDark = Color(0xFF1D4ED8);
  static const accentLight = Color(0xFFE8EFFE); // soft accent tint
  static const _userBubble = Color(0xFFEEF1F6); // cool soft tint
  static const _border = Color(0xFFE6E8EC);
  static const success = Color(0xFF30B959);
  static const error = Color(0xFFF0493E);
  static const warning = Color(0xFFE08A00);
  static const terminalBg = Color(0xFF16181D);
  static const terminalFg = Color(0xFFD8DAE0);
  static const inlineCodeBg = Color(0xFFEDEFF3);
  static const diffAdd = Color(0xFF30B959);
  static const diffDel = Color(0xFFF0493E);

  // ── Dark ──
  static const _darkBg = Color(0xFF0E0F13); // deep near-black, faintly cool
  static const _darkSrf = Color(0xFF1A1C22);
  static const _darkSrf2 = Color(0xFF16181D);
  static const _darkSrfElevated = Color(0xFF24262D);
  static const _darkFg = Color(0xFFEDEEF2);
  static const _darkFgMuted = Color(0xFF8A8F99);
  static const _darkUserBubble = Color(0xFF2A2D35);
  static const _darkBorder = Color(0xFF2C2F37);
  static const darkAccent = Color(0xFF5B8DEF); // brighter accent for dark bg
  static const darkAccentLight = Color(0xFF16263F);
  static const darkInlineCodeBg = Color(0xFF24262D);

  // ── Public const aliases (for use in const constructors) ──
  static const background = _bg;
  static const surface = _srf;
  static const surface2 = _srf2;
  static const surfaceElevated = _srfElevated;
  static const foreground = _fg;
  static const foregroundMuted = _fgMuted;
  static const foregroundLight = _fgLight;
  static const border = _border;
  static const userBubble = _userBubble;

  // ── Context-aware helpers (call with context) ──
  static Color backgroundCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkBg : _bg;
  static Color surfaceCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkSrf : _srf;
  static Color surface1(BuildContext c) => surfaceCtx(c);
  static Color surface2Ctx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkSrf2 : _srf2;
  static Color surfaceElevatedCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkSrfElevated : _srfElevated;
  static Color foregroundCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkFg : _fg;
  static Color foregroundC(BuildContext c) => foregroundCtx(c);
  static Color foregroundM(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkFgMuted : _fgMuted;
  static Color foregroundMutedCtx(BuildContext c) => foregroundM(c);
  static Color foregroundLightCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkFgMuted : _fgLight;
  static Color borderCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkBorder : _border;
  static Color userBubbleCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? _darkUserBubble : _userBubble;
  static Color accentCtx(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkAccent : accent;
}

/// Soft, diffuse shadows — the core of the "premium" lift.
/// Light mode uses a faint cool shadow; dark mode leans on tonal
/// separation (lighter surface vs deeper bg) and a subtle dark shadow.
class AppShadows {
  AppShadows._();

  /// Gentle resting elevation for cards / list rows.
  static List<BoxShadow> soft(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x0F1A1A2E),
        blurRadius: 12,
        spreadRadius: 0,
        offset: Offset(0, 2),
      ),
    ];
  }

  /// Stronger elevation for primary actions / floating elements.
  static List<BoxShadow> lift(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const [
        BoxShadow(
          color: Color(0x55000000),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x161A1A2E),
        blurRadius: 20,
        offset: Offset(0, 6),
      ),
    ];
  }
}

class AppFontSize {
  AppFontSize._();
  static const double xxs = 10;
  static const double xs = 12;
  static const double sm = 13;
  static const double base = 14;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 28;
}

class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double full = 999;
}

class AppTheme {
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors._bg,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accent,
          surface: AppColors._srf,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors._bg,
          foregroundColor: AppColors._fg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: AppColors._srf,
          elevation: 1,
          shadowColor: const Color(0x141A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: AppFontSize.xxl,
            fontWeight: FontWeight.w700,
            color: AppColors._fg,
            letterSpacing: -0.4,
          ),
          headlineMedium: TextStyle(
            fontSize: AppFontSize.xl,
            fontWeight: FontWeight.w700,
            color: AppColors._fg,
            letterSpacing: -0.3,
          ),
          titleLarge: TextStyle(
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w600,
            color: AppColors._fg,
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w600,
            color: AppColors._fg,
            letterSpacing: -0.1,
            height: 1.35,
          ),
          bodyLarge: TextStyle(
            fontSize: AppFontSize.base,
            color: AppColors._fg,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: AppFontSize.sm,
            color: AppColors._fg,
            height: 1.45,
          ),
          bodySmall: TextStyle(
            fontSize: AppFontSize.xs,
            color: AppColors._fgMuted,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontSize: AppFontSize.base,
            fontWeight: FontWeight.w500,
            color: AppColors._fg,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors._srf2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          hintStyle: const TextStyle(
            color: AppColors._fgMuted,
            fontSize: AppFontSize.sm,
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors._srf2,
          selectedColor: AppColors.accentLight,
          labelStyle: const TextStyle(
            fontSize: AppFontSize.sm,
            color: AppColors._fg,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors._srf,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors._border,
          thickness: 0.5,
          space: 0,
        ),
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors._darkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.darkAccent,
          surface: AppColors._darkSrf,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors._darkBg,
          foregroundColor: AppColors._darkFg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: AppColors._darkSrf,
          elevation: 1,
          shadowColor: const Color(0x55000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: AppFontSize.xxl,
            fontWeight: FontWeight.w700,
            color: AppColors._darkFg,
            letterSpacing: -0.4,
          ),
          headlineMedium: TextStyle(
            fontSize: AppFontSize.xl,
            fontWeight: FontWeight.w700,
            color: AppColors._darkFg,
            letterSpacing: -0.3,
          ),
          titleLarge: TextStyle(
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w600,
            color: AppColors._darkFg,
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w600,
            color: AppColors._darkFg,
            letterSpacing: -0.1,
            height: 1.35,
          ),
          bodyLarge: TextStyle(
            fontSize: AppFontSize.base,
            color: AppColors._darkFg,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: AppFontSize.sm,
            color: AppColors._darkFg,
            height: 1.45,
          ),
          bodySmall: TextStyle(
            fontSize: AppFontSize.xs,
            color: AppColors._darkFgMuted,
            height: 1.4,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors._darkBorder,
          thickness: 0.5,
          space: 0,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors._darkSrf2,
          selectedColor: AppColors.darkAccentLight,
          labelStyle: const TextStyle(
            fontSize: AppFontSize.sm,
            color: AppColors._darkFg,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors._darkSrf2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.darkAccent, width: 1.5),
          ),
          hintStyle: const TextStyle(
            color: AppColors._darkFgMuted,
            fontSize: AppFontSize.sm,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors._darkSrf,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          ),
        ),
      );
}
