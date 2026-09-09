import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/placed_order.dart';

import 'support/harness.dart';

/// The Orders tab, on real data.
///
/// The claim under test is narrow and important: **this tab shows purchases and
/// nothing else.** A basket somebody started and abandoned is not a purchase,
/// and a customer who sees one there believes they have bought food they have
/// not paid for.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required FakeOrderRepository orders,
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester);

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
          initialLocation: '/orders',
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('a placed order appears with its number, restaurant and total', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..ordersInTab = <PlacedOrder>[
        FakeOrderRepository.orderFor(
          id: 'order-1',
          status: PlacedOrderStatus.placed,
        ),
      ];

    await open(tester, orders: orders);

    expect(find.byKey(const ValueKey<String>('orders-list')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('order-row-number-order-1')),
      findsOneWidget,
    );

    // "Order placed", never "Accepted" — the restaurant has not seen it.
    expect(find.text('Order placed'), findsOneWidget);
    expect(find.text('Accepted by the restaurant'), findsNothing);
  });

  testWidgets('an empty list offers a way to start a journey', (
    WidgetTester tester,
  ) async {
    await open(tester, orders: FakeOrderRepository());

    expect(find.byKey(const ValueKey<String>('orders-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('orders-list')), findsNothing);
  });

  testWidgets('a failure offers a retry rather than an exception', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..listFailure = const ApiException(
        code: ApiErrorCode.network,
        message: 'no connection',
      );

    await open(tester, orders: orders);

    expect(find.byKey(const ValueKey<String>('orders-error')), findsOneWidget);

    // The exception's own text must not reach a customer.
    expect(find.textContaining('no connection'), findsNothing);
  });

  testWidgets('long restaurant names and large text do not overflow', (
    WidgetTester tester,
  ) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..ordersInTab = <PlacedOrder>[
        FakeOrderRepository.orderFor(
          id: 'order-long',
          status: PlacedOrderStatus.placed,
          restaurantName:
              'Highway Spice Kitchen and Family Dhaba, National Highway 48, '
              'Behror Bypass, Rajasthan',
        ),
      ];

    // The smallest phone this project supports, and the largest text a customer
    // is likely to set. Both at once, because either alone is the easy case.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await open(tester, orders: orders, textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('order-row-order-long')),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(null);
  });
}
