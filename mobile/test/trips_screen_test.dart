import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/features/trips/trip_detail_screen.dart';
import 'package:foodonthego/features/trips/trip_planner_screen.dart';

import 'support/harness.dart';

/// The journeys list, the detail screen, and what neither of them claims.
void main() {
  Future<void> openTrips(
    WidgetTester tester, {
    FakeTripRepository? trips,
  }) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        trips: trips,
        initialLocation: '/trips',
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('shows each journey as its two ends', (
      WidgetTester tester,
    ) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(trips: <Trip>[sampleTrip()]),
      );

      expect(
        find.text('Hauz Khas Village → Jaipur International Airport'),
        findsOneWidget,
      );
    });

    testWidgets('never shows a distance, a duration or an arrival time', (
      WidgetTester tester,
    ) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(
          trips: <Trip>[
            sampleTrip(id: 'a'),
            sampleTrip(id: 'b'),
          ],
        ),
      );

      // Two journeys, both across 235 km of Rajasthan, and the app says only
      // that it has not worked the route out. This is the assertion that fails
      // the day somebody adds a placeholder that looks like a real answer.
      expect(find.text('Route not calculated yet'), findsNWidgets(2));
      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('min'), findsNothing);
      expect(find.textContaining('Arrives'), findsNothing);
    });

    testWidgets('an empty list invites a first journey', (
      WidgetTester tester,
    ) async {
      await openTrips(tester, trips: FakeTripRepository());

      expect(find.text('No journeys yet'), findsOneWidget);
      expect(find.text('Plan your first journey'), findsOneWidget);
    });

    testWidgets('a failure offers a retry rather than an empty list', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository()
        ..nextListError = const ApiException(
          code: ApiErrorCode.network,
          message: 'offline',
          status: 0,
        );

      await openTrips(tester, trips: trips);

      // "No journeys yet" over a failed request is a lie about somebody's data.
      expect(find.text('No journeys yet'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(trips.listReads, greaterThan(1));
    });
  });

  group('scopes', () {
    testWidgets('planned and discarded, and nothing that cannot be filled', (
      WidgetTester tester,
    ) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(trips: <Trip>[sampleTrip()]),
      );

      expect(find.text('Planned'), findsOneWidget);
      expect(find.text('Discarded'), findsOneWidget);
      // Nothing in this module observes a journey happening, so a "Past" tab
      // would be a tab that never fills.
      expect(find.text('Past'), findsNothing);
    });

    testWidgets('discarded shows only discarded journeys', (
      WidgetTester tester,
    ) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(
          trips: <Trip>[
            sampleTrip(id: 'open-1'),
            sampleTrip(id: 'gone-1', status: TripStatus.cancelled),
          ],
        ),
      );

      expect(find.text('DISCARDED'), findsNothing);

      await tester.tap(find.text('Discarded'));
      await tester.pumpAndSettle();

      // Spelled out as a word, not signalled by a grey. Somebody who cannot
      // distinguish the two greys still reads it.
      expect(find.text('DISCARDED'), findsOneWidget);
    });
  });

  group('discarding', () {
    testWidgets('asks first, and a refusal changes nothing', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository(
        trips: <Trip>[sampleTrip()],
      );
      await openTrips(tester, trips: trips);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard journey').last);
      await tester.pumpAndSettle();

      expect(find.text('Discard this journey?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(trips.discardCount, 0);
    });

    testWidgets('confirming discards it and leaves the planned list', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository(
        trips: <Trip>[sampleTrip()],
      );
      await openTrips(tester, trips: trips);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard journey').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(trips.discardCount, 1);
      expect(find.text('Journey discarded'), findsOneWidget);
      // Filtered by the server's rules on a re-read, not locally.
      expect(find.text('No journeys yet'), findsOneWidget);
    });

    testWidgets('a discarded journey offers no further action', (
      WidgetTester tester,
    ) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(
          trips: <Trip>[sampleTrip(status: TripStatus.cancelled)],
        ),
      );

      await tester.tap(find.text('Discarded'));
      await tester.pumpAndSettle();

      // A menu offering an action the server will refuse teaches people not to
      // trust the menu.
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });
  });

  group('navigation', () {
    testWidgets('the FAB opens the planner', (WidgetTester tester) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(trips: <Trip>[sampleTrip()]),
      );

      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Plan a journey'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TripPlannerScreen), findsOneWidget);
    });

    testWidgets('a row opens the journey', (WidgetTester tester) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(trips: <Trip>[sampleTrip()]),
      );

      await tester.tap(
        find.text('Hauz Khas Village → Jaipur International Airport'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TripDetailScreen), findsOneWidget);
    });

    testWidgets('the detail screen shows both ends and no route', (
      WidgetTester tester,
    ) async {
      await openTrips(
        tester,
        trips: FakeTripRepository(trips: <Trip>[sampleTrip()]),
      );

      await tester.tap(
        find.text('Hauz Khas Village → Jaipur International Airport'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Setting off from'), findsOneWidget);
      expect(find.text('Going to'), findsOneWidget);
      expect(find.text('Route not calculated yet'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('a journey that is not on the account reads as gone', (
      WidgetTester tester,
    ) async {
      usePhoneSurface(tester);

      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          trips: FakeTripRepository(),
          // Somebody else's journey id, or one that has been discarded on
          // another device. The two are indistinguishable, deliberately.
          initialLocation: '/trips/ananya-trip-uuid',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('That journey is no longer on your account.'),
        findsOneWidget,
      );
    });
  });
}
