import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/features/trips/trip_detail_screen.dart';
import 'package:foodonthego/features/trips/trip_form_screen.dart';
import 'package:foodonthego/features/trips/widgets/trip_card.dart';

import 'support/harness.dart';

void main() {
  Future<FakeTripRepository> pumpTrips(
    WidgetTester tester, {
    List<Trip> trips = const <Trip>[],
    FakeTripRepository? repository,
    Size size = const Size(390, 844),
  }) async {
    final FakeTripRepository trip =
        repository ?? FakeTripRepository(trips: trips);

    usePhoneSurface(tester, size: size);
    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        trips: trip,
        initialLocation: '/trips',
      ),
    );
    await tester.pumpAndSettle();

    return trip;
  }

  group('the list', () {
    testWidgets('an empty account is invited to plan, not told it is empty', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester);

      expect(find.text('No journeys yet'), findsOneWidget);
      expect(find.text('Plan your first journey'), findsOneWidget);
    });

    testWidgets('journeys are listed with their route and departure', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester, trips: <Trip>[sampleTrip()]);

      expect(find.text('New Delhi → Jaipur'), findsOneWidget);
      expect(find.textContaining('Tomorrow'), findsOneWidget);
    });

    testWidgets('the soonest journey is listed first', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime.now().toUtc();

      await pumpTrips(
        tester,
        trips: <Trip>[
          sampleTrip(
            id: 'later',
            destinationCity: 'Agra',
            departureAt: now.add(const Duration(days: 6)),
          ),
          sampleTrip(
            id: 'sooner',
            destinationCity: 'Jaipur',
            departureAt: now.add(const Duration(days: 1)),
          ),
        ],
      );

      final List<Element> rows = find
          .byType(TripListItem)
          .evaluate()
          .toList(growable: false);

      expect((rows.first.widget as TripListItem).trip.id, 'sooner');
    });

    testWidgets('a loading list shows a skeleton, not a bare spinner', (
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
          trips: FakeTripRepository(trips: <Trip>[sampleTrip()]),
          initialLocation: '/trips',
        ),
      );

      // One frame only: the data has not arrived.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('a failed load offers a retry that really re-asks', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository repository = FakeTripRepository();
      repository.nextListError = const ApiException(
        code: ApiErrorCode.serverError,
        message: 'boom',
        status: 500,
      );

      await pumpTrips(tester, repository: repository);

      expect(find.text('Try again'), findsOneWidget);

      final int before = repository.listReads;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repository.listReads, greaterThan(before));
    });

    testWidgets('losing the network says so instead of showing a stack trace', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository repository = FakeTripRepository();
      repository.nextListError = const ApiException.network();

      await pumpTrips(tester, repository: repository);

      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });

  group('the scopes', () {
    testWidgets('past and cancelled have their own empty wording', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester, trips: <Trip>[sampleTrip()]);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      expect(find.text('No past journeys'), findsOneWidget);

      await tester.tap(find.text('Cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('No cancelled journeys'), findsOneWidget);
    });

    testWidgets('past shows departed journeys and upcoming does not', (
      WidgetTester tester,
    ) async {
      await pumpTrips(
        tester,
        trips: <Trip>[
          sampleTrip(
            id: 'gone',
            destinationCity: 'Agra',
            departureAt: DateTime.now().toUtc().subtract(
              const Duration(days: 3),
            ),
            hasDeparted: true,
            isEditable: false,
          ),
        ],
      );

      expect(find.text('No journeys yet'), findsOneWidget);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('New Delhi → Agra'), findsOneWidget);
      expect(find.text('Departed'), findsOneWidget);
    });

    testWidgets('a cancelled journey is labelled in words, not by colour', (
      WidgetTester tester,
    ) async {
      await pumpTrips(
        tester,
        trips: <Trip>[
          sampleTrip(status: TripStatus.cancelled, isEditable: false),
        ],
      );

      await tester.tap(find.text('Cancelled'));
      await tester.pumpAndSettle();

      expect(find.text('CANCELLED'), findsOneWidget);
    });
  });

  group('the row menu', () {
    testWidgets('names its own row rather than saying "Options"', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester, trips: <Trip>[sampleTrip()]);

      final Finder menu = find.descendant(
        of: find.byType(TripListItem),
        matching: find.byType(PopupMenuButton<int>),
      );

      expect(
        tester.widget<PopupMenuButton<int>>(menu).tooltip,
        'Options for New Delhi → Jaipur',
      );
    });

    testWidgets('a departed journey offers no actions at all', (
      WidgetTester tester,
    ) async {
      await pumpTrips(
        tester,
        trips: <Trip>[
          sampleTrip(
            departureAt: DateTime.now().toUtc().subtract(
              const Duration(days: 2),
            ),
            hasDeparted: true,
            isEditable: false,
          ),
        ],
      );

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      // A menu offering an edit the server would refuse teaches people not to
      // trust the menu.
      expect(
        find.descendant(
          of: find.byType(TripListItem),
          matching: find.byType(PopupMenuButton<int>),
        ),
        findsNothing,
      );
    });
  });

  group('cancelling', () {
    testWidgets('asks first, and keeping it changes nothing', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository repository = await pumpTrips(
        tester,
        trips: <Trip>[sampleTrip()],
      );

      await tester.tap(
        find.descendant(
          of: find.byType(TripListItem),
          matching: find.byType(PopupMenuButton<int>),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel journey').last);
      await tester.pumpAndSettle();

      expect(find.text('Cancel this journey?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(repository.cancelCount, 0);
    });

    testWidgets('confirming cancels through the server and reports it', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository repository = await pumpTrips(
        tester,
        trips: <Trip>[sampleTrip()],
      );

      await tester.tap(
        find.descendant(
          of: find.byType(TripListItem),
          matching: find.byType(PopupMenuButton<int>),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel journey').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Train booked instead');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel journey'));
      await tester.pumpAndSettle();

      expect(repository.cancelCount, 1);
      expect(repository.lastCancelReason, 'Train booked instead');
      expect(find.text('Journey cancelled'), findsOneWidget);
    });

    testWidgets('a cancelled journey leaves the upcoming list', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester, trips: <Trip>[sampleTrip()]);

      await tester.tap(
        find.descendant(
          of: find.byType(TripListItem),
          matching: find.byType(PopupMenuButton<int>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel journey').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel journey'));
      await tester.pumpAndSettle();

      // The list is re-read from the server rather than filtered locally, so
      // this asserts the server's rule and not a second copy of it.
      expect(find.text('No journeys yet'), findsOneWidget);
    });

    testWidgets('a refused cancellation is reported and nothing is claimed', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository repository = await pumpTrips(
        tester,
        trips: <Trip>[sampleTrip()],
      );

      repository.nextWriteError = const ApiException(
        code: ApiErrorCode.tripNotEditable,
        message: 'server wording the app never shows',
        status: 422,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(TripListItem),
          matching: find.byType(PopupMenuButton<int>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel journey').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel journey'));
      await tester.pumpAndSettle();

      expect(find.textContaining('can no longer be changed'), findsOneWidget);
      expect(find.text('Journey cancelled'), findsNothing);
      // Still there. Nothing was removed on the strength of a failed request.
      expect(find.text('New Delhi → Jaipur'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('a row opens the journey', (WidgetTester tester) async {
      await pumpTrips(tester, trips: <Trip>[sampleTrip()]);

      await tester.tap(find.text('New Delhi → Jaipur'));
      await tester.pumpAndSettle();

      expect(find.byType(TripDetailScreen), findsOneWidget);
    });

    testWidgets('the empty state opens the planner', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester);

      await tester.tap(find.text('Plan your first journey'));
      await tester.pumpAndSettle();

      expect(find.byType(TripFormScreen), findsOneWidget);
    });

    testWidgets('the action button opens the planner once there is a list', (
      WidgetTester tester,
    ) async {
      await pumpTrips(tester, trips: <Trip>[sampleTrip()]);

      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Plan a journey'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TripFormScreen), findsOneWidget);
    });
  });

  group('narrow screens', () {
    testWidgets('the scope labels never break mid-word at 320dp', (
      WidgetTester tester,
    ) async {
      await pumpTrips(
        tester,
        trips: <Trip>[sampleTrip()],
        size: const Size(320, 720),
      );

      // Whole words, and no RenderFlex overflow. The Module 04 type selector
      // rendered "Othe r" before this rule was learned.
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
