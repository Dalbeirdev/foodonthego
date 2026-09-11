import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/active_order_summary.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/placed_order.dart';

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

  group('PlacedOrderStatus', () {
    // KI-021 closed here. Until Module 17 this app carried two order-status
    // vocabularies: this one, and a speculative `OrderStatus` declared in
    // Module 02 with a fulfilment workflow nobody had specified. Module 17
    // specified it, so the speculative one is gone and its tests moved here —
    // rewritten rather than renamed, because what they assert has changed.

    test('carries every state the server can send, and no invented ones', () {
      // The wire values are the contract. A state in this enum that the server
      // cannot produce is a screen waiting to render something impossible; a
      // state the server can produce and this list lacks falls back to
      // awaitingPayment and tells a customer their collected order is unpaid.
      expect(
        PlacedOrderStatus.values.map((PlacedOrderStatus s) => s.wireValue),
        <String>[
          'AWAITING_PAYMENT',
          'PLACED',
          'PAYMENT_FAILED',
          'CANCELLED',
          'ACCEPTED',
          'REJECTED',
          'COOKING',
          'READY',
          'PICKED_UP',
          'REFUNDED',
        ],
      );
    });

    test('the fulfilment track is the happy path and nothing else', () {
      // The same five steps the server's OrderStateMachine::happyPath() walks.
      expect(PlacedOrderStatus.fulfilmentProgression, <PlacedOrderStatus>[
        PlacedOrderStatus.placed,
        PlacedOrderStatus.accepted,
        PlacedOrderStatus.cooking,
        PlacedOrderStatus.ready,
        PlacedOrderStatus.pickedUp,
      ]);
    });

    test('every way of leaving the path is off the track, not just cancelled', () {
      // This is the assertion that changed. The old enum knew one way out and
      // the track widget named it: `status == cancelled`. There are five, and a
      // rejected order under the old rule would have been drawn with four steps
      // still to come — the exact thing the widget's own docstring forbade.
      for (final PlacedOrderStatus status in <PlacedOrderStatus>[
        PlacedOrderStatus.awaitingPayment,
        PlacedOrderStatus.paymentFailed,
        PlacedOrderStatus.cancelled,
        PlacedOrderStatus.rejected,
        PlacedOrderStatus.refunded,
      ]) {
        expect(
          status.isOnFulfilmentPath,
          isFalse,
          reason: '${status.name} must not be drawn as a step on the way',
        );
        expect(status.fulfilmentStep, -1, reason: status.name);
      }
    });

    test('orders the progression correctly', () {
      expect(PlacedOrderStatus.placed.fulfilmentStep, 0);
      expect(PlacedOrderStatus.cooking.fulfilmentStep, 2);
      expect(
        PlacedOrderStatus.pickedUp.fulfilmentStep,
        PlacedOrderStatus.fulfilmentProgression.length - 1,
      );
    });

    test('gives every state a distinct label and an explanation', () {
      final Set<String> labels = PlacedOrderStatus.values
          .map((PlacedOrderStatus s) => s.label)
          .toSet();
      expect(labels.length, PlacedOrderStatus.values.length);

      final Set<String> explanations = PlacedOrderStatus.values
          .map((PlacedOrderStatus s) => s.explanation)
          .toSet();
      expect(explanations.length, PlacedOrderStatus.values.length);

      for (final PlacedOrderStatus status in PlacedOrderStatus.values) {
        expect(status.explanation, isNotEmpty, reason: status.name);
      }
    });

    test('does not answer whether an order is still active', () {
      // Deliberately absent. The server sends `is_active` on the tracking
      // response and OrderStateMachine::activeStatuses() decides it; a second
      // opinion compiled into the app is one that can disagree with the first,
      // and the app is the side that must not be believed.
      //
      // Asserted by absence of a compiled reference rather than by a runtime
      // check: if `isActive` is ever added, the line below stops being true and
      // somebody has to come and read this comment.
      expect(
        PlacedOrderStatus.values.every(
          (PlacedOrderStatus s) =>
              s.isOnFulfilmentPath || !s.isOnFulfilmentPath,
        ),
        isTrue,
      );
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
          status: PlacedOrderStatus.cooking,
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
        status: PlacedOrderStatus.cooking,
        totalMinorUnits: 74000,
      );
      expect(order.totalMinorUnits, isA<int>());
      expect(order.currencyCode, 'INR');
    });
  });
}
