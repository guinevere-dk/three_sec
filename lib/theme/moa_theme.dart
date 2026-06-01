import 'package:flutter/material.dart';

import 'moa_design_tokens.dart';

ThemeData buildMoaTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: MoaDesignTokens.accentStrong,
        brightness: Brightness.light,
      ).copyWith(
        primary: MoaDesignTokens.accentStrong,
        secondary: MoaDesignTokens.accent,
        surface: MoaDesignTokens.surfaceSolid,
        error: MoaDesignTokens.danger,
        onPrimary: MoaDesignTokens.textPrimary,
        onSurface: MoaDesignTokens.textPrimary,
      );

  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: MoaDesignTokens.background,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: MoaDesignTokens.background,
      foregroundColor: MoaDesignTokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: MoaDesignTokens.textPrimary),
      titleTextStyle: TextStyle(
        color: MoaDesignTokens.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: MoaDesignTokens.modalBarrier,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MoaDesignTokens.surfaceSolid,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MoaDesignTokens.radiusLg),
        side: const BorderSide(color: MoaDesignTokens.stroke),
      ),
      titleTextStyle: const TextStyle(
        color: MoaDesignTokens.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: const TextStyle(
        color: MoaDesignTokens.textMuted,
        fontSize: 14,
      ),
    ),
    cardTheme: CardThemeData(
      color: MoaDesignTokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MoaDesignTokens.radiusMd),
        side: const BorderSide(color: MoaDesignTokens.stroke),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: MoaDesignTokens.surfaceAlt,
      selectedColor: MoaDesignTokens.accentSoft,
      disabledColor: MoaDesignTokens.surfaceAlt.withValues(alpha: 0.55),
      side: const BorderSide(color: MoaDesignTokens.stroke),
      labelStyle: const TextStyle(
        color: MoaDesignTokens.textMuted,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: const TextStyle(
        color: MoaDesignTokens.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MoaDesignTokens.accentStrong,
        foregroundColor: MoaDesignTokens.textPrimary,
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MoaDesignTokens.textPrimary,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: MoaDesignTokens.stroke),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MoaDesignTokens.accentStrong,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MoaDesignTokens.accentStrong,
      linearTrackColor: MoaDesignTokens.stroke,
      circularTrackColor: MoaDesignTokens.stroke,
    ),
  );
}
