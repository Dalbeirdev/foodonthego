import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/domain/models/active_order_summary.dart';
import 'package:foodonthego/domain/models/active_trip_summary.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_status.dart';
import 'package:foodonthego/domain/repositories/home_repository.dart';

import 'support/harness.dart';

const CustomerSummary _rahul = CustomerSummary(fullName: 'Rahul Sharma');

const ActiveTripSummary _delhiToJaipur = ActiveTripSummary(
  id: 'trip-1',
  originLabel: 'Delhi',
  destinationLabel: 'Jaipur',
  status: TripStatus.onTheRoad,
  estimatedDuration: Duration(hours: 4, minutes: 35),
  remainingDuration: Duration(hours: 2, minutes: 50),
  totalDistanceKm: 281,
  progress: 0.38,
);

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
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      wrapApp(repository: StubHomeRepository.value(dashboard), theme: theme),
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

  group('Persona B — active journey, no order', () {
    const HomeDashboard dashboard = HomeDashboard(
      customer: _rahul,
      activeTrip: _delhiToJaipur,
    );

    testWidgets('shows the journey', (WidgetTester tester) async {
      await pumpHome(tester, dashboard);

      expect(find.text('Your journey'), findsOneWidget);
      expect(find.text('Delhi'), findsOneWidget);
      expect(find.text('Jaipur'), findsOneWidget);
      expect(find.text('On the road'), findsOneWidget);
    });

    testWidgets('shows no order card — there is no order', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard);

      expect(find.text('Your order'), findsNothing);
      expect(find.textContaining('FOTG-'), findsNothing);
    });

    testWidgets('drops the explainer once there is something real to show', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, dashboard);
      expect(find.text('How FoodOnTheGo works'), findsNothing);
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
          activeTrip: _delhiToJaipur,
          activeOrder: _cookingOrder(DateTime.now()),
        ),
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
          activeTrip: _delhiToJaipur,
          activeOrder: _cookingOrder(DateTime.now()),
        ),
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
              activeTrip: const ActiveTripSummary(
                id: 'trip-2',
                originLabel: 'Indira Gandhi International Airport, New Delhi',
                destinationLabel: 'Jaipur International Airport, Rajasthan',
                status: TripStatus.onTheRoad,
                remainingDuration: Duration(hours: 3, minutes: 15),
                totalDistanceKm: 304.6,
                progress: 0.41,
                nextPickupLabel:
                    'Shree Rajasthan Highway Family Restaurant & Food Court',
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
        HomeDashboard(
          customer: _rahul,
          activeTrip: _delhiToJaipur,
          activeOrder: _cookingOrder(evening),
        ),
        theme: FotgTheme.dark(),
      );

      expect(find.textContaining('Rahul'), findsWidgets);
      expect(find.text('Your journey'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
