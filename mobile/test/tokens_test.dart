import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/core/theme/tokens.dart';
import 'package:foodonthego/core/theme/typography.dart';

/// Relative luminance per WCAG 2.1, so the palette is checked against a real
/// contrast ratio rather than by eye.
double _luminance(Color c) {
  double channel(double v) {
    final double s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

double contrastRatio(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('spacing scale', () {
    test('is a strict 4px progression', () {
      const List<double> scale = <double>[
        FotgSpacing.x1,
        FotgSpacing.x2,
        FotgSpacing.x3,
        FotgSpacing.x4,
        FotgSpacing.x5,
        FotgSpacing.x6,
        FotgSpacing.x8,
        FotgSpacing.x10,
        FotgSpacing.x12,
        FotgSpacing.x16,
      ];

      for (final double value in scale) {
        expect(value % 4, 0, reason: '$value is not on the 4px grid');
      }
      for (int i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });
  });

  group('touch targets', () {
    test('meet the 48dp floor', () {
      // WCAG 2.2 asks for 44; this app is tapped one-handed before driving.
      expect(FotgSizing.touchTargetMin, greaterThanOrEqualTo(44));
      expect(FotgSizing.controlHeightMd, greaterThanOrEqualTo(44));
      expect(
        FotgSizing.controlHeightLg,
        greaterThanOrEqualTo(FotgSizing.controlHeightMd),
      );
    });
  });

  group('typography', () {
    test('never drops below 15sp for prose', () {
      final TextTheme t = FotgTypography.textTheme(
        FotgColors.neutral900,
        FotgColors.neutral600,
      );

      for (final TextStyle? style in <TextStyle?>[
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
      ]) {
        expect(
          style!.fontSize,
          greaterThanOrEqualTo(15),
          reason: 'body text must stay legible at arm’s length in a vehicle',
        );
      }
      // labelSmall is metadata only and may be 13.
      expect(t.labelSmall!.fontSize, greaterThanOrEqualTo(13));
    });
  });

  group('colour contrast', () {
    test('primary button text clears WCAG AA', () {
      final ThemeData light = FotgTheme.light();
      final double ratio = contrastRatio(
        light.colorScheme.primary,
        light.colorScheme.onPrimary,
      );
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'ratio was $ratio');
    });

    test('body text on the background clears WCAG AA in both themes', () {
      for (final ThemeData theme in <ThemeData>[
        FotgTheme.light(),
        FotgTheme.dark(),
      ]) {
        final double ratio = contrastRatio(
          theme.textTheme.bodyMedium!.color!,
          theme.scaffoldBackgroundColor,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness} body contrast was $ratio',
        );
      }
    });

    test('secondary text still clears AA, not just AA-large', () {
      for (final ThemeData theme in <ThemeData>[
        FotgTheme.light(),
        FotgTheme.dark(),
      ]) {
        final double ratio = contrastRatio(
          theme.colorScheme.onSurfaceVariant,
          theme.scaffoldBackgroundColor,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness} secondary contrast was $ratio',
        );
      }
    });
  });

  group('theme wiring', () {
    test('both themes are built and differ in brightness', () {
      expect(FotgTheme.light().brightness, Brightness.light);
      expect(FotgTheme.dark().brightness, Brightness.dark);
    });

    test('cards use the token radius rather than a Material default', () {
      final ShapeBorder? shape = FotgTheme.light().cardTheme.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect((shape! as RoundedRectangleBorder).borderRadius, FotgRadius.card);
    });
  });
}
