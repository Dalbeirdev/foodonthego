// KI-031: how old a cached status may be, and what the screen does past it.
//
// The rule lives on OrderTrackingState so it can be asserted at the second
// rather than described in a comment on a widget. The widget tests for the
// rendering are in order_tracking_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/tracking_config.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/shared/state/order_tracking_controller.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 18, 16, 30);

  OrderTrackingState readAt(DateTime? at) =>
      OrderTrackingState(phase: OrderTrackingPhase.loaded, fetchedAt: at);

  group('age', () {
    test('a read that has not happened has no age', () {
      expect(readAt(null).ageAt(now), isNull);
    });

    test('age is measured from the read', () {
      expect(
        readAt(now.subtract(const Duration(minutes: 7))).ageAt(now),
        const Duration(minutes: 7),
      );
    });

    test('a device clock that jumps backwards reads as just now', () {
      // Not a hypothetical: a timezone change, a manual clock edit or an NTP
      // correction can all put `now` behind `fetchedAt`. A negative age would
      // sail past every threshold below and blank a perfectly fresh screen.
      final Duration? age = readAt(now.add(const Duration(hours: 3)))
          .ageAt(now);

      expect(age, Duration.zero);
      expect(age!.isNegative, isFalse);
    });
  });

  group('what the app will vouch for', () {
    test('nothing read yet is not a stale claim', () {
      expect(readAt(null).vouchesForStatusAt(now), isTrue);
    });

    test('a fresh read is vouched for', () {
      expect(
        readAt(now.subtract(const Duration(seconds: 5)))
            .vouchesForStatusAt(now),
        isTrue,
      );
    });

    test('the boundary itself is still vouched for', () {
      // Exactly at the bound, not past it. Asserted rather than left to a `<`
      // versus `<=` that nobody reads twice.
      expect(
        readAt(now.subtract(TrackingConfig.vouchedFor)).vouchesForStatusAt(now),
        isTrue,
      );
    });

    test('one second past the boundary is not', () {
      expect(
        readAt(
          now.subtract(TrackingConfig.vouchedFor + const Duration(seconds: 1)),
        ).vouchesForStatusAt(now),
        isFalse,
      );
    });

    test('a day-old read is not', () {
      expect(
        readAt(now.subtract(const Duration(days: 1))).vouchesForStatusAt(now),
        isFalse,
      );
    });

    test('the bound is the polling budget, not a second number', () {
      // If these ever diverge it should be a decision somebody made, not a
      // constant somebody edited. The comment on TrackingConfig.vouchedFor
      // explains why they are the same; this makes changing one of them fail.
      expect(TrackingConfig.vouchedFor, TrackingConfig.pollingBudget);
    });
  });

  group('how the age is said', () {
    const AppStrings strings = AppStrings();

    test('under a minute is just now, not a count of seconds', () {
      expect(
        strings.orderTrackingUpdatedAgo(const Duration(seconds: 59)),
        'Updated just now',
      );
    });

    test('minutes are singular and plural', () {
      expect(
        strings.orderTrackingUpdatedAgo(const Duration(minutes: 1)),
        'Updated 1 minute ago',
      );
      expect(
        strings.orderTrackingUpdatedAgo(const Duration(minutes: 42)),
        'Updated 42 minutes ago',
      );
    });

    test('an hour or more is said in hours', () {
      // Three hours, not 187 minutes: arithmetic the reader should not have to
      // do to answer "is this worth trusting".
      expect(
        strings.orderTrackingUpdatedAgo(const Duration(minutes: 187)),
        'Updated 3 hours ago',
      );
      expect(
        strings.orderTrackingUpdatedAgo(const Duration(hours: 1)),
        'Updated 1 hour ago',
      );
    });

    test('beyond a day it stops counting', () {
      expect(
        strings.orderTrackingUpdatedAgo(const Duration(days: 2, hours: 5)),
        'Updated more than a day ago',
      );
    });
  });
}
