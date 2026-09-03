import 'package:flutter/material.dart';

/// FoodOnTheGo design tokens for Flutter.
///
/// These mirror `web/packages/ui/src/tokens.css` value for value — the same
/// palette, the same 4px spacing scale, the same radii and durations. Two
/// platforms cannot share a stylesheet, so the contract between them is
/// docs/08-design-system.md, and a change to one is a change to both.
///
/// Widgets reference these. A raw `Color(0xFF...)` or a bare `16.0` inside a
/// widget is a bug.
class FotgColors {
  const FotgColors._();

  // Brand — amber/saffron. Food, and highway signage.
  static const primary50 = Color(0xFFFFF8ED);
  static const primary100 = Color(0xFFFFEFD4);
  static const primary200 = Color(0xFFFFDAA8);
  static const primary400 = Color(0xFFFF9A38);
  static const primary500 = Color(0xFFFE7D12);
  static const primary600 = Color(0xFFEF6008);
  static const primary700 = Color(0xFFC64709);

  // Journey — deep teal. Routes, maps and ETA, never the same colour as food.
  static const secondary100 = Color(0xFFCCFBF1);
  static const secondary500 = Color(0xFF14B8A6);
  static const secondary600 = Color(0xFF0D9488);
  static const secondary700 = Color(0xFF0F766E);

  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFFAFAF9);
  static const neutral100 = Color(0xFFF5F5F4);
  static const neutral200 = Color(0xFFE7E5E4);
  static const neutral300 = Color(0xFFD6D3D1);
  static const neutral400 = Color(0xFFA8A29E);
  static const neutral500 = Color(0xFF78716C);
  static const neutral600 = Color(0xFF57534E);
  static const neutral800 = Color(0xFF292524);
  static const neutral900 = Color(0xFF1C1917);
  static const neutral950 = Color(0xFF0C0A09);

  static const success = Color(0xFF15803D);
  static const successSurface = Color(0xFFF0FDF4);
  static const warning = Color(0xFFB45309);
  static const warningSurface = Color(0xFFFFFBEB);
  static const error = Color(0xFFB91C1C);
  static const errorSurface = Color(0xFFFEF2F2);
  static const info = Color(0xFF1D4ED8);
  static const infoSurface = Color(0xFFEFF6FF);

  // Dark-theme equivalents. Saturated mid-tones lose contrast on a dark ground,
  // so the ramp lightens rather than the hex being reused.
  static const darkSuccess = Color(0xFF4ADE80);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkError = Color(0xFFF87171);
  static const darkInfo = Color(0xFF60A5FA);
}

/// 4px base scale. Anything not on it is an accident.
class FotgSpacing {
  const FotgSpacing._();

  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
}

class FotgRadius {
  const FotgRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double full = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius control = BorderRadius.all(Radius.circular(md));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Motion. Kept short — this is used in a moving vehicle, where a long transition
/// reads as lag rather than as polish.
class FotgMotion {
  const FotgMotion._();

  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve decelerate = Cubic(0, 0, 0, 1);
  static const Curve emphasized = Cubic(0.2, 0, 0, 1.2);

  /// Honours the OS "reduce motion" setting. Vestibular disorders make large
  /// transitions genuinely unpleasant, so this is an accessibility control, not a
  /// preference — every animated widget in the app routes through it.
  static Duration respectingReducedMotion(
    BuildContext context,
    Duration duration,
  ) => MediaQuery.maybeDisableAnimationsOf(context) == true
      ? Duration.zero
      : duration;
}

/// 48dp: above the 44pt/48dp floor in both the Apple HIG and WCAG 2.2, and this
/// app is tapped one-handed by someone about to drive.
class FotgSizing {
  const FotgSizing._();

  static const double touchTargetMin = 48;
  static const double controlHeightSm = 40;
  static const double controlHeightMd = 48;
  static const double controlHeightLg = 56;
  static const double bottomNavHeight = 64;
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 26;
}
