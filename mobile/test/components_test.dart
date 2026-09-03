import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/core/theme/status_palette.dart';
import 'package:foodonthego/domain/models/active_order_summary.dart';
import 'package:foodonthego/domain/models/order_status.dart';
import 'package:foodonthego/domain/repositories/home_repository.dart';
import 'package:foodonthego/features/home/widgets/active_order_card.dart';
import 'package:foodonthego/features/home/widgets/greeting_header.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/shared/state/connectivity.dart';
import 'package:foodonthego/shared/widgets/app_error_view.dart';
import 'package:foodonthego/shared/widgets/buttons.dart';
import 'package:foodonthego/shared/widgets/empty_state_view.dart';
import 'package:foodonthego/shared/widgets/offline_banner.dart';
import 'package:foodonthego/shared/widgets/order_status_chip.dart';

import 'support/harness.dart';

void main() {
  group('OrderStatusChip', () {
    testWidgets('renders every state with a distinct label', (
      WidgetTester tester,
    ) async {
      for (final OrderStatus status in OrderStatus.values) {
        await tester.pumpWidget(wrapWidget(OrderStatusChip(status: status)));
        await tester.pump();
        expect(
          find.text(status.label),
          findsOneWidget,
          reason: '${status.name} label missing',
        );
      }
    });

    testWidgets('carries an icon so the state is not conveyed by colour alone', (
      WidgetTester tester,
    ) async {
      // Roughly one man in twelve cannot reliably separate the amber "cooking"
      // from the green "ready" — and that is the moment that matters most.
      for (final OrderStatus status in OrderStatus.values) {
        await tester.pumpWidget(wrapWidget(OrderStatusChip(status: status)));
        await tester.pump();
        expect(
          find.byType(Icon),
          findsWidgets,
          reason: '${status.name} has no icon',
        );
      }
    });

    testWidgets('announces the state to a screen reader', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const OrderStatusChip(status: OrderStatus.cooking)),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Order status: Cooking'), findsOneWidget);
    });

    test('gives every status a visually distinct pairing', () {
      final Set<int> foregrounds = OrderStatus.values
          .map(
            (OrderStatus s) =>
                OrderStatusStyle.of(s, Brightness.light).foreground.toARGB32(),
          )
          .toSet();
      final Set<IconData> icons = OrderStatus.values
          .map((OrderStatus s) => OrderStatusStyle.of(s, Brightness.light).icon)
          .toSet();

      expect(
        icons.length,
        OrderStatus.values.length,
        reason: 'two states share an icon',
      );
      expect(foregrounds.length, greaterThanOrEqualTo(5));
    });
  });

  group('OrderStatusTrack', () {
    testWidgets('draws nothing for a cancelled order', (
      WidgetTester tester,
    ) async {
      // Drawing the remaining steps as "still to come" for an order that will
      // never reach them would be a lie.
      await tester.pumpWidget(
        wrapWidget(const OrderStatusTrack(status: OrderStatus.cancelled)),
      );
      await tester.pump();
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Progress')), findsNothing);
    });

    testWidgets('reports its position for a live order', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const OrderStatusTrack(status: OrderStatus.cooking)),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('step 3 of 5')), findsOneWidget);
    });
  });

  group('ActiveOrderCard', () {
    final DateTime now = DateTime(2026, 3, 14, 19, 0);

    ActiveOrderSummary order({required OrderStatus status, DateTime? pickup}) =>
        ActiveOrderSummary(
          reference: 'FOTG-1024',
          restaurantName: 'Highway Spice Kitchen',
          status: status,
          itemCount: 3,
          estimatedPickup: pickup,
        );

    test('never counts down past zero', () {
      // An estimate the clock has overtaken must read "ready now", not "-3 min".
      expect(
        ActiveOrderCard.minutesUntil(
          now.subtract(const Duration(minutes: 3)),
          now,
        ),
        0,
      );
      expect(
        ActiveOrderCard.minutesUntil(now.add(const Duration(minutes: 35)), now),
        35,
      );
      expect(ActiveOrderCard.minutesUntil(null, now), isNull);
    });

    testWidgets('leads with the countdown', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWidget(
          ActiveOrderCard(
            order: order(
              status: OrderStatus.cooking,
              pickup: now.add(const Duration(minutes: 35)),
            ),
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pickup in about'), findsOneWidget);
      expect(find.textContaining('35'), findsWidgets);
    });

    testWidgets('says "ready now" once the estimate has passed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(
          ActiveOrderCard(
            order: order(
              status: OrderStatus.ready,
              pickup: now.subtract(const Duration(minutes: 2)),
            ),
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready now'), findsOneWidget);
    });

    testWidgets('handles a very long restaurant name', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWidget(
          ActiveOrderCard(
            order: const ActiveOrderSummary(
              reference: 'FOTG-100482',
              restaurantName:
                  'Shree Rajasthan Highway Family Restaurant & Food Court',
              status: OrderStatus.ready,
              itemCount: 12,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('GreetingHeader', () {
    testWidgets('greets by time of day', (WidgetTester tester) async {
      const AppStrings strings = AppStrings();
      expect(
        GreetingHeader.greetingFor(DateTime(2026, 3, 14, 8), strings, 'Rahul'),
        'Good morning, Rahul',
      );
      expect(
        GreetingHeader.greetingFor(DateTime(2026, 3, 14, 14), strings, 'Rahul'),
        'Good afternoon, Rahul',
      );
      expect(
        GreetingHeader.greetingFor(DateTime(2026, 3, 14, 21), strings, 'Rahul'),
        'Good evening, Rahul',
      );
      // 04:00 is still night — "good morning" at 4am reads as broken.
      expect(
        GreetingHeader.greetingFor(DateTime(2026, 3, 14, 4), strings, 'Rahul'),
        'Good evening, Rahul',
      );
    });

    testWidgets('keeps the avatar tappable at the accessibility floor', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(
          GreetingHeader(
            customer: const CustomerSummary(fullName: 'Rahul Sharma'),
            isTravelling: false,
            onAvatarTap: () {},
            now: DateTime(2026, 3, 14, 19),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Size size = tester.getSize(
        find.bySemanticsLabel('Profile, Rahul Sharma'),
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('OfflineBanner', () {
    testWidgets('is invisible while online', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWidget(const OfflineBanner(status: ConnectivityStatus.online)),
      );
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsNothing);
    });

    testWidgets('appears when offline, without blocking the screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const OfflineBanner(status: ConnectivityStatus.offline)),
      );
      await tester.pumpAndSettle();

      expect(find.text('You are offline'), findsOneWidget);
      expect(
        find.text('Showing the latest information we have.'),
        findsOneWidget,
      );

      // A banner, not a modal. Asserted by size rather than by the absence of a
      // ModalBarrier, which MaterialApp always contains for route transitions:
      // the banner must occupy a strip, leaving the screen readable underneath.
      final double bannerHeight = tester
          .getSize(find.text('You are offline'))
          .height;
      expect(bannerHeight, lessThan(120));
    });
  });

  group('AppErrorView', () {
    testWidgets('gives each failure kind its own wording', (
      WidgetTester tester,
    ) async {
      const Map<HomeFailureKind, String> expected = <HomeFailureKind, String>{
        HomeFailureKind.offline: 'No connection',
        HomeFailureKind.timeout: 'That took too long',
        HomeFailureKind.serverUnavailable: 'FoodOnTheGo is unavailable',
        HomeFailureKind.unknown: 'Something went wrong',
      };

      for (final MapEntry<HomeFailureKind, String> entry in expected.entries) {
        await tester.pumpWidget(
          wrapWidget(AppErrorView(kind: entry.key, onRetry: () {})),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: '${entry.key.name} wording',
        );
      }
    });

    testWidgets('omits the retry button when there is nothing to retry', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const AppErrorView(kind: HomeFailureKind.unknown)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('EmptyStateView', () {
    testWidgets('teaches rather than apologises', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWidget(
          EmptyStateView(
            icon: Icons.route_rounded,
            title: 'No journeys yet',
            body:
                'Plan a journey and we will find restaurants along your route.',
            action: PrimaryButton(
              label: 'Plan a journey',
              onPressed: () {},
              expand: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No journeys yet'), findsOneWidget);
      expect(find.text('Plan a journey'), findsOneWidget);
    });
  });

  group('PrimaryButton', () {
    testWidgets('keeps its label while loading, and refuses taps', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        wrapWidget(
          PrimaryButton(
            label: 'Plan a journey',
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.pump();

      // The label staying put is what stops the layout jumping — and a jumping
      // button is exactly when somebody taps twice.
      expect(find.text('Plan a journey'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('is disabled when given no callback', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const PrimaryButton(label: 'Plan a journey')),
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('meets the touch-target floor', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWidget(PrimaryButton(label: 'Go', onPressed: () {}, expand: false)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('large text', () {
    testWidgets('the order card survives 1.4x text scaling', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: wrapWidget(
            const ActiveOrderCard(
              order: ActiveOrderSummary(
                reference: 'FOTG-1024',
                restaurantName: 'Highway Spice Kitchen',
                status: OrderStatus.cooking,
                itemCount: 3,
              ),
            ),
            theme: FotgTheme.light(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
