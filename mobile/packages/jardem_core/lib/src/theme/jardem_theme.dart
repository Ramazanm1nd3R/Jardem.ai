import 'package:flutter/material.dart';

import 'jardem_colors.dart';

/// Shared look of both Jardem.ai apps.
abstract final class JardemTheme {
  /// Family name of the Manrope font bundled in this package.
  static const String fontFamily = 'packages/jardem_core/Manrope';

  static const double radiusCard = 18;
  static const double radiusField = 14;

  /// Text style with an explicit `wght` axis value — Manrope is a variable font.
  static TextStyle text(double size, FontWeight weight, {Color color = JardemColors.navy, double? height}) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
    letterSpacing: 0,
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: JardemColors.primary,
      primary: JardemColors.primary,
      onPrimary: Colors.white,
      surface: JardemColors.surface,
      onSurface: JardemColors.navy,
      error: JardemColors.danger,
    );
    final textTheme = TextTheme(
      displaySmall: text(30, FontWeight.w800),
      headlineMedium: text(24, FontWeight.w800),
      headlineSmall: text(20, FontWeight.w800),
      titleLarge: text(18, FontWeight.w700),
      titleMedium: text(16, FontWeight.w700),
      titleSmall: text(14, FontWeight.w700),
      bodyLarge: text(16, FontWeight.w500),
      bodyMedium: text(14, FontWeight.w500),
      bodySmall: text(12, FontWeight.w500, color: JardemColors.muted),
      labelLarge: text(15, FontWeight.w700),
      labelMedium: text(13, FontWeight.w600),
      labelSmall: text(11, FontWeight.w600, color: JardemColors.muted),
    );
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusField),
      borderSide: BorderSide(color: c, width: w),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: JardemColors.background,
      fontFamily: fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: JardemColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: JardemColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text(17, FontWeight.w800),
      ),
      dividerTheme: const DividerThemeData(color: JardemColors.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hoverColor: Colors.transparent,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: text(14, FontWeight.w500, color: JardemColors.faint),
        errorStyle: text(12, FontWeight.w600, color: JardemColors.danger),
        errorMaxLines: 2,
        border: border(JardemColors.border),
        enabledBorder: border(JardemColors.border),
        focusedBorder: border(JardemColors.primary, 1.5),
        errorBorder: border(JardemColors.danger),
        focusedErrorBorder: border(JardemColors.danger, 1.5),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text(18, FontWeight.w800),
        contentTextStyle: text(14, FontWeight.w500, color: JardemColors.muted, height: 1.4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: JardemColors.navy,
        contentTextStyle: text(14, FontWeight.w600, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: JardemColors.primary, textStyle: text(14, FontWeight.w700)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: JardemColors.primary),
    );
  }
}
