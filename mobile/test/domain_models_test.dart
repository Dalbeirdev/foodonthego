import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/active_order_summary.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_status.dart';

void main() {
  group('CustomerSummary', () {
    test('greets with the first name only', () {
      expect(
        const CustomerSummary(fullName: 'Rahul Sharma').greetingName,
        'Rahul',
      );
      expect(
        const CustomerSummary(fullName: 'Rahul Krishnamurthy Sharma')
            .greetingName,
        'Rahul',
      );
    });

    test(
      'takes initials from the first and last name, skipping the middle',
      () {
        expect(const CustomerSummary(fullName: 'Rahul Sharma').initials, 'RS');
        expect(
          const CustomerSummary(fullName: 'Rahul Krishnamurthy Sharma')
              .initials,
          'RS',
        );
        expect(const CustomerSummary(fullName: 'Rahul').initials, 'R');
      },
    );

    test('does not fall over on empty or whitespace-only names', () {
      expect(const CustomerSummary(fullName: '').greetingName, 'there');
      expect(const CustomerSummary(fullName: '   ').initials, '?');
    });

    test(
      'collapses repeated whitespace rather than producing blank initials',
      () {
        expect(
          const CustomerSummary(fullName: 'Rahul    Sharma').initials,
          'RS',
        );
      },
    );
  });

  group('OrderStatus', () {
    test('exposes every state the specification requires', () {
      expect(OrderStatus.values.map((OrderStatus s) => s.name), <String>[
        'placed',
        'accepted',
        'cooking',
        'ready',
        'pickedUp',
        'cancelled',
      ]);
    });

    test(
      'treats picked up and cancelled as terminal, everything else as active',
      () {
        expect(OrderStatus.pickedUp.isTerminal, isTrue);
        expect(OrderStatus.cancelled.isTerminal, isTrue);
        for (final OrderStatus status in <OrderStatus>[
          OrderStatus.placed,
          OrderStatus.accepted,
          OrderStatus.cooking,
          OrderStatus.ready,
        ]) {
          expect(
            status.isActive,
            isTrue,
            reason: '${status.name} should be active',
          );
        }
      },
    );

    test('keeps cancelled off the progress track', () {
      // Cancelled is not a step: an order that will never reach "ready" must not
      // be drawn as though it is on its way there.
      expect(OrderStatus.progression, isNot(contains(OrderStatus.cancelled)));
      expect(OrderStatus.cancelled.stepIndex, -1);
    });

    test('orders the progression correctly', () {
      expect(OrderStatus.placed.stepIndex, 0);
      expect(OrderStatus.cooking.stepIndex, 2);
      expect(
        OrderStatus.pickedUp.stepIndex,
        OrderStatus.progression.length - 1,
      );
    });

    test('gives every state a distinct label and an explanation', () {
      final Set<String> labels = OrderStatus.values
          .map((OrderStatus s) => s.label)
          .toSet();
      expect(labels.length, OrderStatus.values.length);
      for (final OrderStatus status in OrderStatus.values) {
        expect(status.explanation, isNotEmpty);
      }
    });
  });

  group('HomeDashboard', () {
    const CustomerSummary rahul = CustomerSummary(fullName: 'Rahul Sharma');

    test('carries no journey of its own', () {
      // Module 05 moved journeys onto the real API, and the dashboard stopped
      // holding a second, fixture-shaped copy. This test exists so a future
      // change that reintroduces one has to argue with it: two representations
      // of the same journey are how two parts of a screen come to disagree.
      const HomeDashboard dashboard = HomeDashboard(customer: rahul);

      expect(dashboard.hasActiveOrder, isFalse);
    });

    test('knows whether an order is on', () {
      const HomeDashboard dashboard = HomeDashboard(
        customer: rahul,
        activeOrder: ActiveOrderSummary(
          reference: 'FOTG-1024',
          restaurantName: 'Highway Spice Kitchen',
          status: OrderStatus.cooking,
        ),
      );

      expect(dashboard.hasActiveOrder, isTrue);
    });
  });

  group('ActiveOrderSummary', () {
    test('carries money as integer minor units with its currency', () {
      const ActiveOrderSummary order = ActiveOrderSummary(
        reference: 'FOTG-1024',
        restaurantName: 'Highway Spice Kitchen',
        status: OrderStatus.cooking,
        totalMinorUnits: 74000,
      );
      expect(order.totalMinorUnits, isA<int>());
      expect(order.currencyCode, 'INR');
    });
  });
}
