import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Builds the light and dark themes from the tokens.
///
/// Everything visual is set here so that a screen never has to reach for a raw
/// colour or radius: a widget asks the theme, and the theme asks the tokens.
class FotgTheme {
  const FotgTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color background = isDark
        ? FotgColors.neutral950
        : FotgColors.neutral50;
    final Color surface = isDark ? FotgColors.neutral900 : FotgColors.neutral0;
    final Color surfaceRaised = isDark
        ? FotgColors.neutral800
        : FotgColors.neutral0;
    final Color textPrimary = isDark
        ? FotgColors.neutral50
        : FotgColors.neutral900;
    final Color textSecondary = isDark
        ? FotgColors.neutral400
        : FotgColors.neutral600;
    final Color border = isDark
        ? const Color(0xFF2B2522)
        : FotgColors.neutral200;
    // primary700, not primary600. White text on #EF6008 (primary600) measures
    // 3.31:1 — below the WCAG AA 4.5:1 threshold for normal text. #C64709 gives
    // 4.88:1. primary600 remains correct for decoration that carries no text.
    // A test in test/tokens_test.dart computes this ratio and fails if it regresses.
    final Color primary = isDark
        ? FotgColors.primary400
        : FotgColors.primary700;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? FotgColors.neutral950 : FotgColors.neutral0,
      primaryContainer: isDark ? const Color(0xFF2C1A10) : FotgColors.primary50,
      onPrimaryContainer: isDark
          ? FotgColors.primary200
          : FotgColors.primary700,
      secondary: isDark ? FotgColors.secondary500 : FotgColors.secondary600,
      onSecondary: FotgColors.neutral0,
      secondaryContainer: isDark
          ? const Color(0xFF0C2F2B)
          : FotgColors.secondary100,
      onSecondaryContainer: isDark
          ? FotgColors.secondary100
          : FotgColors.secondary700,
      error: isDark ? FotgColors.darkError : FotgColors.error,
      onError: FotgColors.neutral0,
      errorContainer: isDark
          ? const Color(0xFF2A1414)
          : FotgColors.errorSurface,
      onErrorContainer: isDark ? FotgColors.darkError : FotgColors.error,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceRaised,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? FotgColors.neutral50 : FotgColors.neutral900,
      onInverseSurface: isDark ? FotgColors.neutral900 : FotgColors.neutral50,
      inversePrimary: isDark ? FotgColors.primary600 : FotgColors.primary400,
    );

    final TextTheme text = FotgTypography.textTheme(textPrimary, textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: FotgTypography.fontFamily,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        // Status-bar icons must contrast with the app bar, not with the OS default.
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: FotgRadius.card,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(FotgSizing.controlHeightLg),
          shape: const RoundedRectangleBorder(borderRadius: FotgRadius.control),
          textStyle: text.labelLarge!.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          // Material's default disabled state is onSurface at 38% on a 12% fill,
          // which rendered the label of a disabled button effectively invisible —
          // a control that announces itself to a screen reader but shows nothing
          // to a sighted user. These give ~6:1, so a disabled action can still be
          // read and understood as disabled.
          disabledBackgroundColor: isDark
              ? FotgColors.neutral800
              : FotgColors.neutral200,
          disabledForegroundColor: isDark
              ? FotgColors.neutral400
              : FotgColors.neutral600,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(FotgSizing.controlHeightMd),
          shape: const RoundedRectangleBorder(borderRadius: FotgRadius.control),
          side: BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: FotgSizing.bottomNavHeight,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark ? const Color(0xFF2C1A10) : FotgColors.primary50,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: FotgRadius.pill,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall!.copyWith(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: FotgSizing.iconMd,
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: FotgRadius.sheet),
        showDragHandle: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? FotgColors.neutral800 : FotgColors.neutral100,
        side: BorderSide(color: border),
        shape: const RoundedRectangleBorder(borderRadius: FotgRadius.pill),
        labelStyle: text.labelSmall!.copyWith(
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? FotgColors.neutral50 : FotgColors.neutral900,
        contentTextStyle: text.bodySmall!.copyWith(
          color: isDark ? FotgColors.neutral900 : FotgColors.neutral50,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: FotgRadius.control),
      ),
    );
  }
}
