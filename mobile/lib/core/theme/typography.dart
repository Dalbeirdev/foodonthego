import 'package:flutter/material.dart';

/// The type scale, mirroring the web design system.
///
/// The floor is 15sp for prose and 16sp for body. This app is read at arm's
/// length on a phone mount, often in motion and often in daylight — the 12-13sp
/// that passes on a desktop dashboard is not legible there.
class FotgTypography {
  const FotgTypography._();

  /// Deliberately null: the platform's own UI font.
  ///
  /// Naming 'Roboto' here looked harmless and was a real bug. Roboto is a system
  /// font on Android but NOT on iOS, so iOS silently fell back — and on Flutter
  /// web the engine tried to fetch it from Google's CDN, which meant the app
  /// rendered no text at all on a network that could not reach it. A null family
  /// resolves to Roboto on Android and San Francisco on iOS, which is what each
  /// platform should look like anyway. Bundling a brand face, if we ever want one,
  /// is a deliberate change here plus an asset in pubspec.yaml — never an
  /// unbundled name.
  static const String? fontFamily = null;

  /// Every style is produced through here and carries [fontFamily], so a brand
  /// font — if one is ever bundled — applies to component themes as well as to
  /// body text. Constructing a bare TextStyle inside a component theme silently
  /// drops the family and leaves that one widget on the platform font.
  static TextTheme textTheme(Color primary, Color secondary) => _withFamily(
    TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.2,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.2,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.25,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(fontSize: 17, height: 1.5, color: primary),
      bodyMedium: TextStyle(fontSize: 16, height: 1.55, color: primary),
      bodySmall: TextStyle(fontSize: 15, height: 1.5, color: secondary),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      // Metadata only — timestamps and counts. Never prose.
      labelSmall: TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
    ),
  );

  static TextTheme _withFamily(TextTheme theme) =>
      fontFamily == null ? theme : theme.apply(fontFamily: fontFamily);
}
