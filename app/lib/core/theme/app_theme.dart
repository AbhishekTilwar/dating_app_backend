import 'package:flutter/material.dart';

/// Crossed dating app — brand theme.
/// Colors: coral #ec675c, navy #111c3b, blue #1d4b82.
/// Uses system/Material fonts only (no runtime font download).
class AppTheme {
  static const Color brandCoral = Color(0xFFEC675C);
  static const Color brandNavy = Color(0xFF111C3B);
  static const Color brandBlue = Color(0xFF1D4B82);

  static const Color _coralLighter = Color(0xFFFAD4D1);
  static const Color _coralDark = Color(0xFFC7544A);
  static const Color _navyLight = Color(0xFF1E2D52);

  static const Color _black = brandNavy;
  static const Color _blackSoft = _navyLight;
  static const Color _accent = brandCoral;
  static const Color _accentLight = _coralLighter;
  static const Color _accentDark = _coralDark;

  static const Color _surface = Color(0xFFF8F9FC);
  static const Color _surfaceLow = Color(0xFFF2F4F8);
  static const Color _surfaceContainer = Color(0xFFEBEEF4);
  static const Color _surfaceContainerHigh = Color(0xFFE2E6EF);
  static const Color _surfaceContainerHighest = Color(0xFFD8DEE8);
  static const Color _outline = Color(0xFFD0D5DE);
  static const Color _outlineVariant = Color(0xFFE2E6EF);
  static const Color _onSurfaceVariant = Color(0xFF4A5568);
  static const Color _shadow = Color(0x1A111C3B);
  static const Color _scrim = Color(0x52111C3B);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandNavy, brandBlue],
  );

  static const LinearGradient brandGradientWithCoral = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandNavy, brandBlue, Color(0xFFB85A52)],
    stops: [0.0, 0.7, 1.0],
  );

  static TextStyle _ts({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      brightness: Brightness.light,
      primary: _black,
      onPrimary: Colors.white,
      primaryContainer: _surfaceContainerHigh,
      onPrimaryContainer: _black,
      secondary: _accent,
      onSecondary: Colors.white,
      secondaryContainer: _accentLight,
      onSecondaryContainer: _accentDark,
      tertiary: brandBlue,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFD6E4F5),
      onTertiaryContainer: brandBlue,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF991B1B),
      surface: _surface,
      onSurface: _black,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: _surfaceLow,
      surfaceContainer: _surfaceContainer,
      surfaceContainerHigh: _surfaceContainerHigh,
      surfaceContainerHighest: _surfaceContainerHighest,
      outline: _outline,
      outlineVariant: _outlineVariant,
      shadow: _shadow,
      scrim: _scrim,
      inverseSurface: _blackSoft,
      onInverseSurface: _surface,
      inversePrimary: _surfaceContainerHigh,
      surfaceTint: _black,
    );

    final base = ThemeData.light().textTheme;
    final textTheme = base.copyWith(
      bodyLarge: base.bodyLarge?.copyWith(letterSpacing: 0.15, color: _black, fontSize: 14),
      bodyMedium: base.bodyMedium?.copyWith(letterSpacing: 0.25, color: _black, fontSize: 13),
      bodySmall: base.bodySmall?.copyWith(color: _black, fontSize: 12),
      labelLarge: base.labelLarge?.copyWith(letterSpacing: 0.1, fontWeight: FontWeight.w600, color: _black, fontSize: 13),
      labelMedium: base.labelMedium?.copyWith(fontSize: 12),
      labelSmall: base.labelSmall?.copyWith(fontSize: 11),
      titleLarge: base.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: _black),
      titleMedium: base.titleMedium?.copyWith(fontSize: 15, color: _black),
      titleSmall: base.titleSmall?.copyWith(fontSize: 13, color: _black),
      headlineLarge: base.headlineLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _black),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: _black),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: _black),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: _ts(fontSize: 15, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shadowColor: _shadow,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _ts(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onPrimary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _ts(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onPrimary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        selectedLabelStyle: _ts(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: _ts(fontSize: 10),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: _ts(fontSize: 17, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        contentTextStyle: _ts(fontSize: 13, color: colorScheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _blackSoft,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
