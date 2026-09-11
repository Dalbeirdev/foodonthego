import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/tracking_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_timeline.dart';
import 'package:foodonthego/domain/models/placed_order.dart';
import 'package:foodonthego/domain/models/tracked_order.dart';

import 'support/harness.dart';

/// The tracking screen, and the two things it must never do.
///
/// It must never invent progress the server did not report, and it must never
/// move backwards because a slow answer arrived late. Everything else on the
/// screen is presentation; those two are correctness.
void main() {
  TrackedOrder tracked({
    required PlacedOrderStatus status,
    required int version,
    List<OrderTimelineStep> timeline = const <OrderTimelineStep>[],
    bool isActive = true,
    String? reason,
    bool credential = true,
  }) => TrackedOrder(
    order: FakeOrderRepository.orderFor(
      id: 'order-1',
      status: status,
      orderNumber: 'FOTG-260918-K4M9PQ2X7B',
      statusTitle: switch (status) {
        PlacedOrderStatus.placed => 'Order placed',
        PlacedOrderStatus.accepted => 'Restaurant accepted your order',
        PlacedOrderStatus.cooking => 'Your food is being prepared',
        PlacedOrderStatus.ready => 'Ready for pickup',
        PlacedOrderStatus.pickedUp => 'Picked up',
        PlacedOrderStatus.rejected => "Restaurant couldn't accept this order",
        _ => status.label,
      },
    ),
    version: version,
    timeline: timeline,
    isActive: isActive,
    customerSafeReason: reason,
    pickupCredentialAvailable: credential,
  );

  OrderTimelineStep step(
    PlacedOrderStatus status,
    OrderTimelineStepState state, {
    DateTime? at,
    String? note,
  }) => OrderTimelineStep(
    status: status,
    state: state,
    title: switch (status) {
      PlacedOrderStatus.placed => 'Order placed',
      PlacedOrderStatus.accepted => 'Restaurant accepted your order',
      PlacedOrderStatus.cooking => 'Your food is being prepared',
      PlacedOrderStatus.ready => 'Ready for pickup',
      PlacedOrderStatus.pickedUp => 'Picked up',
      PlacedOrderStatus.rejected => "Restaurant couldn't accept this order",
      _ => status.label,
    },
    occurredAt: at,
    note: note,
  );

  Future<void> open(
    WidgetTester tester, {
    required FakeOrderRepository orders,
    double textScale = 1.0,
    Size size = const Size(390, 844),
    DateTime Function()? clock,
  }) async {
    usePhoneSurface(tester, size: size);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          orders: orders,
          trackingClock: clock,
          initialLocation: '/orders/order-1/track',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // ------------------------------------------------------------- the states

  testWidgets('a placed order shows its status and its whole timeline', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(
        status: PlacedOrderStatus.placed,
        version: 1,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.current,
            at: DateTime(2026, 9, 18, 16, 1),
          ),
          step(PlacedOrderStatus.accepted, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.cooking, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      );

    await open(tester, orders: orders);

    expect(find.byKey(const ValueKey<String>('tracking-status')), findsOne);
    expect(find.text('Order placed'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('tracking-timeline')), findsOne);
    expect(find.text('Ready for pickup'), findsOne);
  });

  testWidgets('a cooking order shows the steps it has passed', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(
        status: PlacedOrderStatus.cooking,
        version: 3,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: DateTime(2026, 9, 18, 16, 1),
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: DateTime(2026, 9, 18, 16, 3),
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.current,
            at: DateTime(2026, 9, 18, 16, 5),
          ),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      );

    await open(tester, orders: orders);

    expect(find.text('Your food is being prepared'), findsWidgets);
  });

  /// The branch, checked on the screen rather than only in the API test.
  testWidgets('a rejected order shows no steps it will never reach', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(
        status: PlacedOrderStatus.rejected,
        version: 2,
        isActive: false,
        reason: 'An item became unavailable.',
        credential: false,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: DateTime(2026, 9, 18, 16, 1),
          ),
          step(
            PlacedOrderStatus.rejected,
            OrderTimelineStepState.exception,
            at: DateTime(2026, 9, 18, 16, 4),
          ),
        ],
      );

    await open(tester, orders: orders);

    expect(find.byKey(const ValueKey<String>('tracking-reason')), findsOne);
    expect(find.text('An item became unavailable.'), findsOne);

    // The assertion that matters: a refused order is not still queued to cook.
    expect(find.text('Your food is being prepared'), findsNothing);
    expect(find.text('Ready for pickup'), findsNothing);
  });

  // -------------------------------------------------------- the race, twice

  /// A slow COOKING answer arriving after a fast READY one.
  ///
  /// The screen must stay READY. This is the failure a customer would notice
  /// and could not explain: standing at a counter watching their order go
  /// backwards.
  testWidgets('an older response cannot move the status backwards', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackingResponses.addAll(<TrackedOrder>[
        tracked(status: PlacedOrderStatus.ready, version: 4),
        tracked(status: PlacedOrderStatus.cooking, version: 3),
      ]);

    await open(tester, orders: orders);

    expect(find.text('Ready for pickup'), findsWidgets);

    // The late, older answer arrives.
    await tester.tap(find.byKey(const ValueKey<String>('tracking-refresh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Ready for pickup'),
      findsWidgets,
      reason: 'a stale response must not regress the screen',
    );
    expect(find.text('Your food is being prepared'), findsNothing);
  });

  testWidgets('a newer response does update the status', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackingResponses.addAll(<TrackedOrder>[
        tracked(status: PlacedOrderStatus.cooking, version: 3),
        tracked(status: PlacedOrderStatus.ready, version: 4),
      ]);

    await open(tester, orders: orders);

    expect(find.text('Your food is being prepared'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('tracking-refresh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    /*
     * The control for the test above.
     *
     * Without this, a client that ignored every response after the first would
     * pass the regression test perfectly.
     */
    expect(find.text('Ready for pickup'), findsWidgets);
  });

  // ----------------------------------------------------------- the failures

  testWidgets('a lost connection keeps the order and says it is stale', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(status: PlacedOrderStatus.cooking, version: 3);

    await open(tester, orders: orders);

    expect(find.text('Your food is being prepared'), findsWidgets);

    orders.trackingFailure = const ApiException(
      code: ApiErrorCode.serverError,
      message: 'unreachable',
      status: 500,
    );

    await tester.tap(find.byKey(const ValueKey<String>('tracking-refresh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The order stays. A customer on a motorway does not lose the screen they
    // opened because one refresh timed out.
    expect(find.text('Your food is being prepared'), findsWidgets);

    // And it is clearly not current.
    expect(find.byKey(const ValueKey<String>('tracking-offline')), findsOne);
  });

  testWidgets('somebody elses order reads as unavailable', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackingFailure = const ApiException(
        code: ApiErrorCode.orderNotFound,
        message: 'no such order',
        status: 404,
      );

    await open(tester, orders: orders);

    expect(find.byKey(const ValueKey<String>('tracking-not-found')), findsOne);
  });

  // -------------------------------------------------------------- the rules

  testWidgets('the screen never claims to be live', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(status: PlacedOrderStatus.cooking, version: 3);

    await open(tester, orders: orders);

    /*
     * Module 19 adds realtime. Until then a LIVE badge over a 20-second poll
     * is a claim the app cannot support and the customer cannot check.
     */
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('Live'), findsNothing);
  });

  testWidgets('the pickup window is described as requested, not estimated', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(status: PlacedOrderStatus.ready, version: 4);

    await open(tester, orders: orders);

    expect(find.text('Requested pickup'), findsOne);
    expect(find.textContaining('Not a live estimate'), findsOne);
  });

  testWidgets('nothing on the screen offers to change the order', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(status: PlacedOrderStatus.cooking, version: 3);

    await open(tester, orders: orders);

    // The customer app displays order state and does not decide it. A control
    // here that moved an order would be a security defect, not a feature.
    for (final String forbidden in <String>[
      'Mark as ready',
      'Cancel order',
      'Confirm pickup',
      'Picked up',
    ]) {
      expect(find.text(forbidden), findsNothing, reason: forbidden);
    }
  });

  testWidgets('the timeline stays readable on a small phone at large text', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..trackedOrder = tracked(
        status: PlacedOrderStatus.cooking,
        version: 3,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: DateTime(2026, 9, 18, 16, 1),
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: DateTime(2026, 9, 18, 16, 3),
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.current,
            at: DateTime(2026, 9, 18, 16, 5),
          ),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      );

    await open(
      tester,
      orders: orders,
      textScale: 2.0,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('tracking-timeline')), findsOne);
  });

  // ------------------------------------------- KI-031: how stale is too stale

  FakeOrderRepository cookingOrder() =>
      FakeOrderRepository()
        ..trackedOrder = tracked(
          status: PlacedOrderStatus.cooking,
          version: 3,
          timeline: <OrderTimelineStep>[
            step(
              PlacedOrderStatus.placed,
              OrderTimelineStepState.completed,
              at: DateTime(2026, 9, 18, 16, 1),
            ),
            step(
              PlacedOrderStatus.accepted,
              OrderTimelineStepState.completed,
              at: DateTime(2026, 9, 18, 16, 3),
            ),
            step(
              PlacedOrderStatus.cooking,
              OrderTimelineStepState.current,
              at: DateTime(2026, 9, 18, 16, 6),
            ),
            step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
            step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
          ],
        );

  testWidgets('a fresh read says how fresh it is', (WidgetTester tester) async {
    await open(tester, orders: cookingOrder());

    expect(find.byKey(const ValueKey<String>('tracking-freshness')), findsOne);
    expect(find.text('Updated just now'), findsOne);
  });

  testWidgets('a status too old to rely on is not shown as the status', (
    WidgetTester tester,
  ) async {
    // The read happens at the real now; the screen is asked to render it a day
    // later. This is the case the old screen got wrong: it would have shown
    // "Your food is being prepared" in a headline, and a customer reading four
    // words does not read the banner underneath them first.
    await open(
      tester,
      orders: cookingOrder(),
      clock: () => DateTime.now().add(const Duration(days: 1)),
    );

    expect(
      find.byKey(const ValueKey<String>('tracking-status-unknown')),
      findsOne,
    );
    expect(
      find.text("We can't tell you where this order is right now"),
      findsOne,
    );
    expect(find.text('Updated more than a day ago'), findsOne);

    // The claim about now is gone. Both of it.
    expect(find.byKey(const ValueKey<String>('tracking-hero')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('tracking-timeline')),
      findsNothing,
    );
    expect(find.text('Your food is being prepared'), findsNothing);
  });

  testWidgets('what does not go stale stays on the screen', (
    WidgetTester tester,
  ) async {
    // Refusing to guess the status is not a reason to hide the order. The
    // number, the restaurant, the items and the amount paid are the same facts
    // they were a day ago, and a customer standing at a counter needs them.
    await open(
      tester,
      orders: cookingOrder(),
      clock: () => DateTime.now().add(const Duration(days: 1)),
    );

    expect(
      find.byKey(const ValueKey<String>('tracking-order-number')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('tracking-restaurant')), findsOne);

    // Scrolled to rather than asserted in place: a ListView does not build a
    // child that is nowhere near the viewport, so findsOne on the payment card
    // would be a claim about layout rather than about the card existing.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('tracking-payment')),
      240,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const ValueKey<String>('tracking-payment')), findsOne);
    expect(find.byKey(const ValueKey<String>('tracking-total')), findsOne);
  });

  testWidgets('a read just inside the bound is still shown as the status', (
    WidgetTester tester,
  ) async {
    // The other side of the boundary, so the test above is proved to be about
    // age rather than about the clock override doing something odd.
    await open(
      tester,
      orders: cookingOrder(),
      clock: () => DateTime.now().add(
        TrackingConfig.vouchedFor - const Duration(minutes: 1),
      ),
    );

    expect(find.byKey(const ValueKey<String>('tracking-hero')), findsOne);
    expect(find.byKey(const ValueKey<String>('tracking-timeline')), findsOne);
    expect(
      find.byKey(const ValueKey<String>('tracking-status-unknown')),
      findsNothing,
    );
    expect(find.text('Updated 29 minutes ago'), findsOne);
  });

  testWidgets('the screen fits at every width we support', (
    WidgetTester tester,
  ) async {
    // A mid-order timeline, because it is the tallest of the ordinary states:
    // five steps, three of them carrying a time. Testing the placed state
    // would test the easy one.
    FakeOrderRepository cooking() =>
        FakeOrderRepository()
          ..trackedOrder = tracked(
            status: PlacedOrderStatus.cooking,
            version: 3,
            timeline: <OrderTimelineStep>[
              step(
                PlacedOrderStatus.placed,
                OrderTimelineStepState.completed,
                at: DateTime(2026, 9, 18, 16, 1),
              ),
              step(
                PlacedOrderStatus.accepted,
                OrderTimelineStepState.completed,
                at: DateTime(2026, 9, 18, 16, 3),
              ),
              step(
                PlacedOrderStatus.cooking,
                OrderTimelineStepState.current,
                at: DateTime(2026, 9, 18, 16, 6),
              ),
              step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
              step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
            ],
          );

    for (final Size size in <Size>[
      const Size(320, 720),
      const Size(360, 740),
      const Size(375, 812),
      const Size(390, 844),
      const Size(412, 892),
      const Size(430, 932),
    ]) {
      await open(tester, orders: cooking(), size: size);

      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      expect(
        find.byKey(const ValueKey<String>('tracking-status')),
        findsOne,
        reason: 'the status hero must survive $size',
      );
      expect(
        find.byKey(const ValueKey<String>('tracking-timeline')),
        findsOne,
        reason: 'the timeline must survive $size',
      );
    }
  });
}
