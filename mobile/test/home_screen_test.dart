import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/domain/models/active_order_summary.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_status.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/home_repository.dart';

import 'support/harness.dart';

const CustomerSummary _rahul = CustomerSummary(fullName: 'Rahul Sharma');

/// The journey the home screen renders now comes from the real trips API, so a
/// test supplies it through the trip repository rather than through the
/// dashboard.
Trip _delhiToJaipur() => sampleTrip();

ActiveOrderSummary _cookingOrder(DateTime now) => ActiveOrderSummary(
  reference: 'FOTG-1024',
  restaurantName: 'Highway Spice Kitchen',
  status: OrderStatus.cooking,
  itemCount: 3,
  estimatedPickup: now.add(const Duration(minutes: 35)),
  totalMinorUnits: 74000,
);

void main() {
  // A fixed evening instant, so greeting assertions do not depend on when the
  // suite happens to run.
  final DateTime evening = DateTime(2026, 3, 14, 19, 30);

  Future<void> pumpHome(
    WidgetTester tester,
    HomeDashboard dashboard, {
    ThemeData? theme,
    List<Trip> trips = const <Trip>[],
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(dashboard),
        trips: FakeTripRepository(trips: trips),
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Persona A — new customer', () {
    const HomeDashboard dashboard = HomeDashboard(customer: _rahul);

    testWidgets('greets Rahul and leads with the journey call to action', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard);

      expect(find.textContaining('Rahul'), findsWidgets);
      expect(find.text('Where are you travelling today?'), findsOneWidget);
      expect(find.text('Plan a journey'), findsWidgets);
    });

    testWidgets('shows no journey or order section at all', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard);

      // The rule: no empty containers. If there is no journey, there is no
      // journey heading either.
      expect(find.text('Your journey'), findsNothing);
      expect(find.text('Your order'), findsNothing);
    });

    testWidgets('explains the product instead of leaving blank space', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard);

      expect(find.text('How FoodOnTheGo works'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Delhi to Jaipur'),
        300,
      );
      expect(find.textContaining('Delhi to Jaipur'), findsOneWidget);
    });
  });

  group('Persona B — a planned journey, no order', () {
    const HomeDashboard dashboard = HomeDashboard(customer: _rahul);

    testWidgets('shows the next journey, from the real API', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard, trips: <Trip>[_delhiToJaipur()]);

      expect(find.text('Your journey'), findsOneWidget);
      expect(find.textContaining('Hauz Khas'), findsWidgets);
      expect(find.textContaining('Jaipur'), findsWidgets);
      // The card says what is known and nothing more. No distance, no travel
      // time, no arrival — Module 06 is what puts those here.
      expect(find.text('Route not calculated yet'), findsOneWidget);
    });

    testWidgets('shows no progress bar for a journey nothing is tracking', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard, trips: <Trip>[_delhiToJaipur()]);

      // The Module 02 card drew progress, remaining time and a next pickup —
      // none of which exists. A bar at zero would imply the app is watching a
      // journey it cannot see.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('remaining'), findsNothing);
    });

    testWidgets('shows no order card — there is no order', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard, trips: <Trip>[_delhiToJaipur()]);

      expect(find.text('Your order'), findsNothing);
      expect(find.textContaining('FOTG-'), findsNothing);
    });

    testWidgets('drops the explainer once there is something real to show', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard, trips: <Trip>[_delhiToJaipur()]);
      expect(find.text('How FoodOnTheGo works'), findsNothing);
    });

    testWidgets('a cancelled journey is not shown as the next one', (
      WidgetTester tester,
    ) async {
      await pumpHome(
        tester,
        dashboard,
        trips: <Trip>[sampleTrip(status: TripStatus.cancelled)],
      );

      expect(find.text('Your journey'), findsNothing);
    });
  });

  group('Persona C — active journey and order', () {
    testWidgets('shows both the journey and the order', (
      WidgetTester tester,
    ) async {
      await pumpHome(
        tester,
        HomeDashboard(
          customer: _rahul,
          activeOrder: _cookingOrder(DateTime.now()),
        ),
        trips: <Trip>[_delhiToJaipur()],
      );

      expect(find.text('Your journey'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Your order'), 300);
      expect(find.text('Highway Spice Kitchen'), findsOneWidget);
      expect(find.textContaining('FOTG-1024'), findsOneWidget);
      expect(find.text('Cooking'), findsOneWidget);
    });

    testWidgets('leads with when to be there, not what was ordered', (
      WidgetTester tester,
    ) async {
      await pumpHome(
        tester,
        HomeDashboard(
          customer: _rahul,
          activeOrder: _cookingOrder(DateTime.now()),
        ),
        trips: <Trip>[_delhiToJaipur()],
      );

      await tester.scrollUntilVisible(find.text('Your order'), 300);
      expect(find.textContaining('Pickup in about'), findsOneWidget);
    });
  });

  group('Persona D — long content', () {
    testWidgets('renders the longest realistic content without overflowing', (
      WidgetTester tester,
    ) async {
      // 320dp is the narrowest surface the app claims to support.
      usePhoneSurface(tester, size: const Size(320, 720));

      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(
            HomeDashboard(
              customer: const CustomerSummary(
                fullName: 'Rahul Krishnamurthy Sharma',
              ),
              activeOrder: ActiveOrderSummary(
                reference: 'FOTG-100482',
                restaurantName:
                    'Shree Rajasthan Highway Family Restaurant & Food Court',
                status: OrderStatus.ready,
                itemCount: 12,
                estimatedPickup: DateTime.now().add(const Duration(minutes: 8)),
              ),
            ),
          ),
          trips: FakeTripRepository(
            trips: <Trip>[
              sampleTrip(
                originName: 'Indira Gandhi International Airport, Terminal 3',
                destinationName: 'Jaipur International Airport, Rajasthan',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A RenderFlex overflow would have been recorded as an exception by now.
      expect(tester.takeException(), isNull);
    });
  });

  group('loading, error and refresh', () {
    testWidgets('shows a content-shaped skeleton, not a bare spinner', (
      WidgetTester tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(customer: _rahul),
          ),
        ),
      );
      // One frame in: still loading.
      await tester.pump();

      expect(find.bySemanticsLabel('Loading your home screen'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('shows an actionable error rather than an exception', (
      WidgetTester tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.failing(
            HomeFailureKind.serverUnavailable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FoodOnTheGo is unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // Nothing resembling a raw exception reaches the screen.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('HomeLoadFailure'), findsNothing);
    });

    testWidgets('offline failure gets its own message, not the generic one', (
      WidgetTester tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.failing(HomeFailureKind.offline),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No connection'), findsOneWidget);
      expect(find.textContaining('Highway coverage'), findsOneWidget);
    });

    testWidgets('retry actually re-asks the repository', (
      WidgetTester tester,
    ) async {
      usePhoneSurface(tester);
      final StubHomeRepository repository = StubHomeRepository.failing(
        HomeFailureKind.timeout,
      );

      await tester.pumpWidget(wrapApp(repository: repository));
      await tester.pumpAndSettle();
      expect(repository.loadCount, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(repository.loadCount, 2);
    });
  });

  group('dark mode', () {
    testWidgets('renders the whole home screen', (WidgetTester tester) async {
      await pumpHome(
        tester,
        HomeDashboard(customer: _rahul, activeOrder: _cookingOrder(evening)),
        trips: <Trip>[_delhiToJaipur()],
        theme: FotgTheme.dark(),
      );

      expect(find.textContaining('Rahul'), findsWidgets);
      expect(find.text('Your journey'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
