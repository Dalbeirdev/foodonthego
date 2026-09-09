import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/order_status_report.dart';
import 'package:foodonthego/domain/models/pickup_credential.dart';
import 'package:foodonthego/domain/models/placed_order.dart';
import 'package:foodonthego/features/orders/order_confirmation_screen.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// The confirmation screen, and the one rule it exists to keep.
///
/// **After a capture, never offer to pay again.** Every state below that could
/// possibly follow a capture is checked for the absence of a payment
/// affordance — including the network-failure case, where the app does not know
/// whether the money moved and must not guess, because only one of the two
/// possible guesses can be undone.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required FakeOrderRepository orders,
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [orderRepositoryProvider.overrideWithValue(orders)],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppStringsDelegate(),
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppStringsDelegate.supportedLocales,
            home: const OrderConfirmationScreen(orderId: 'order-uuid-1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// The assertion that matters most, applied to every paid-for state.
  void expectsNoWayToPay(WidgetTester tester) {
    for (final String forbidden in <String>[
      'Pay',
      'Pay now',
      'Retry payment',
    ]) {
      expect(
        find.widgetWithText(ElevatedButton, forbidden),
        findsNothing,
        reason: 'A paid-for state offered "$forbidden".',
      );
      expect(
        find.widgetWithText(FilledButton, forbidden),
        findsNothing,
        reason: 'A paid-for state offered "$forbidden".',
      );
    }
  }

  testWidgets('an order still being created says the money is safe', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusReport = OrderStatusReport(
        state: OrderCreationState.creating,
        isPaidFor: true,
        order: FakeOrderRepository.orderFor(
          id: 'order-uuid-1',
          status: PlacedOrderStatus.awaitingPayment,
          orderNumber: null,
        ),
        message: "We're finishing your order. Please don't pay again.",
      );

    await open(tester, orders: orders);

    expect(
      find.byKey(const ValueKey<String>('confirmation-settling')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('confirmation-payment-confirmed')),
      findsOneWidget,
    );
    expect(find.textContaining("don't pay again"), findsOneWidget);

    expectsNoWayToPay(tester);
  });

  testWidgets('a recovering order is shown identically to a creating one', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusReport = OrderStatusReport(
        state: OrderCreationState.recovering,
        isPaidFor: true,
        order: FakeOrderRepository.orderFor(
          id: 'order-uuid-1',
          status: PlacedOrderStatus.awaitingPayment,
          orderNumber: null,
        ),
        message: "We're finishing your order. Please don't pay again.",
      );

    await open(tester, orders: orders);

    expect(
      find.byKey(const ValueKey<String>('confirmation-settling')),
      findsOneWidget,
    );
    expectsNoWayToPay(tester);
  });

  testWidgets('a placed order shows its number, total and pickup code', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusReport = OrderStatusReport(
        state: OrderCreationState.placed,
        isPaidFor: true,
        order: FakeOrderRepository.orderFor(
          id: 'order-uuid-1',
          status: PlacedOrderStatus.placed,
        ),
      )
      ..credential = const PickupCredential(
        code: 'K7M4P2QR',
        qrPayload: 'foodonthego://pickup/v1/opaque',
        version: 1,
      );

    await open(tester, orders: orders);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('confirmation-order-number')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('confirmation-total')),
      findsOneWidget,
    );
    expect(find.text('K7M4P2QR'), findsOneWidget);

    // "Waiting for restaurant confirmation" — never "Accepted".
    expect(
      find.byKey(const ValueKey<String>('confirmation-awaiting-restaurant')),
      findsOneWidget,
    );
    expect(find.textContaining('Accepted'), findsNothing);

    expectsNoWayToPay(tester);
  });

  testWidgets('the pickup code is announced character by character', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusReport = OrderStatusReport(
        state: OrderCreationState.placed,
        isPaidFor: true,
        order: FakeOrderRepository.orderFor(
          id: 'order-uuid-1',
          status: PlacedOrderStatus.placed,
        ),
      )
      ..credential = const PickupCredential(
        code: 'K7M4P2QR',
        qrPayload: 'foodonthego://pickup/v1/opaque',
        version: 1,
      );

    await open(tester, orders: orders);
    await tester.pumpAndSettle();

    // Spoken as separate characters. "K7M4P2QR" read as a word is unusable to
    // somebody who has to say it to a person behind a counter.
    /*
     * Asserted on the Semantics widget rather than through
     * find.bySemanticsLabel.
     *
     * That finder matches against nodes in the merged semantics tree, where an
     * ancestor's label can absorb this one and the match silently fails even
     * though the label is exactly right — which is what happened here first.
     * The widget's own property is the claim being made: this text is announced
     * as separated characters.
     */
    final Iterable<String> labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((Semantics w) => w.properties.label ?? '')
        .where((String label) => label.isNotEmpty);

    expect(labels, contains('Pickup code, K 7 M 4 P 2 Q R'));

    // And the raw run of characters is NOT what a screen reader would say, so
    // the separated form is doing real work rather than matching by accident.
    expect(labels, isNot(contains('Pickup code, K7M4P2QR')));

    handle.dispose();
  });

  testWidgets('a network failure never invites a second payment', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusFailure = const ApiException(
        code: ApiErrorCode.network,
        message: 'no connection',
      );

    await open(tester, orders: orders);

    expect(
      find.byKey(const ValueKey<String>('confirmation-network-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('confirmation-no-repay')),
      findsOneWidget,
    );
    expect(find.textContaining("don't pay again"), findsOneWidget);

    expectsNoWayToPay(tester);
  });

  testWidgets('somebody elses order reads as unavailable, not as an error', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusFailure = const ApiException(
        code: ApiErrorCode.notFound,
        message: 'not found',
      );

    await open(tester, orders: orders);

    expect(
      find.byKey(const ValueKey<String>('confirmation-unauthorized')),
      findsOneWidget,
    );
    expectsNoWayToPay(tester);
  });

  testWidgets('polling stops as soon as the order is placed', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..statusReport = OrderStatusReport(
        state: OrderCreationState.placed,
        isPaidFor: true,
        order: FakeOrderRepository.orderFor(
          id: 'order-uuid-1',
          status: PlacedOrderStatus.placed,
        ),
      );

    await open(tester, orders: orders);
    await tester.pumpAndSettle();

    final int afterFirst = orders.statusCalls;

    // Well past the poll interval. A screen that kept asking would climb here,
    // and on a highway that is a battery drain a customer pays for.
    await tester.pump(const Duration(seconds: 20));

    expect(orders.statusCalls, afterFirst);
  });
}
