import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/data/repositories/api_order_repository.dart';
import 'package:foodonthego/domain/models/order_timeline.dart';
import 'package:foodonthego/domain/models/placed_order.dart';
import 'package:foodonthego/domain/models/tracked_order.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The real repository against a real response envelope.
///
/// **THIS FILE EXISTS BECAUSE ITS ABSENCE COST A DEVICE RUN.** Every widget
/// test in this project drives a fake repository, so the code that turns an
/// actual HTTP body into a model was never once executed by the suite. The
/// first version of `tracking()` unwrapped the envelope twice — `data['data']`
/// where `ApiClient` had already returned `data` — so every real call threw,
/// and nothing found out until an iOS simulator talked to a real server.
///
/// The bodies below are copied from what the API actually returns, not from
/// what the models would like to receive. That distinction is the whole point:
/// a fixture written from the model's point of view would have had the same
/// blind spot as the fake.
void main() {
  ApiOrderRepository repositoryReturning(Map<String, dynamic> envelope) =>
      ApiOrderRepository(
        ApiClient(
          httpClient: MockClient(
            (http.Request request) async => http.Response(
              jsonEncode(envelope),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
          tokenReader: () async => 'a-token',
        ),
      );

  /// The tracking response, as `GET /customer/orders/{id}` actually sends it.
  Map<String, dynamic> trackingEnvelope() => <String, dynamic>{
    'data': <String, dynamic>{
      'id': 'a2f2017b-d106-4659-aa3a-df77c7837da5',
      'order_number': 'FOTG-260909-9KFSGX9HVP',
      'status': 'COOKING',
      'status_title': 'Your food is being prepared',
      'status_subtitle': 'Your food is being prepared.',
      'currency': 'INR',
      'order_version': 3,
      'is_active': true,
      'status_updated_at': '2026-09-09T22:50:44+05:30',
      'placed_at': '2026-09-09T22:50:28+05:30',
      'customer_safe_reason': null,
      'restaurant': <String, dynamic>{
        'id': 'r-1',
        'name': 'Highway Spice Kitchen',
      },
      'pickup': <String, dynamic>{
        'start_at': '2026-09-10T00:50:28+05:30',
        'end_at': '2026-09-10T01:00:28+05:30',
        'timezone': 'Asia/Kolkata',
      },
      'commercial': <String, dynamic>{
        'items_subtotal': <String, dynamic>{
          'amount_minor': 24900,
          'currency': 'INR',
        },
        'charges': <Object?>[],
        'discounts': <Object?>[],
        'payable_total': <String, dynamic>{
          'amount_minor': 24900,
          'currency': 'INR',
        },
      },
      'items': <Object?>[],
      'payment': <String, dynamic>{'id': 'p-1', 'status': 'CAPTURED'},
      'pickup_credential': <String, dynamic>{
        'available': true,
        'expires_at': '2026-09-11T01:00:28+05:30',
      },
      'timeline': <Object?>[
        <String, dynamic>{
          'status': 'PLACED',
          'state': 'COMPLETED',
          'title': 'Order placed',
          'occurred_at': '2026-09-09T22:50:28+05:30',
          'note': null,
        },
        <String, dynamic>{
          'status': 'COOKING',
          'state': 'CURRENT',
          'title': 'Your food is being prepared',
          'occurred_at': '2026-09-09T22:50:44+05:30',
          'note': null,
        },
        <String, dynamic>{
          'status': 'READY',
          'state': 'UPCOMING',
          'title': 'Ready for pickup',
          'occurred_at': null,
          'note': null,
        },
      ],
      'server_time': '2026-09-09T22:51:00+05:30',
    },
  };

  test('tracking reads the envelope the server actually sends', () async {
    final TrackedOrder tracked = await repositoryReturning(trackingEnvelope())
        .tracking('a2f2017b-d106-4659-aa3a-df77c7837da5');

    // The assertion that the double-unwrap would have failed: it threw a
    // FormatException before ever getting here.
    expect(tracked.order.status, PlacedOrderStatus.cooking);
    expect(tracked.version, 3);
    expect(tracked.isActive, isTrue);
    expect(tracked.pickupCredentialAvailable, isTrue);
    expect(tracked.order.statusTitle, 'Your food is being prepared');
    expect(tracked.order.orderNumber, 'FOTG-260909-9KFSGX9HVP');
  });

  test(
    'the timeline survives the wire with its states and its nulls',
    () async {
      final TrackedOrder tracked = await repositoryReturning(trackingEnvelope())
          .tracking('a2f2017b-d106-4659-aa3a-df77c7837da5');

      expect(tracked.timeline, hasLength(3));

      expect(tracked.timeline[0].state, OrderTimelineStepState.completed);
      expect(tracked.timeline[1].state, OrderTimelineStepState.current);
      expect(tracked.timeline[2].state, OrderTimelineStepState.upcoming);

      expect(tracked.timeline[0].occurredAt, isNotNull);

      // An upcoming step's null time has to survive parsing as a null. A model
      // that quietly substituted `now()` would tell a customer their food was
      // ready at an hour it was not.
      expect(tracked.timeline[2].occurredAt, isNull);
    },
  );

  test(
    'a payment target parses, with no order number and no timeline',
    () async {
      final Map<String, dynamic> envelope = trackingEnvelope();
      final Map<String, dynamic> data =
          envelope['data']! as Map<String, dynamic>;

      data['status'] = 'AWAITING_PAYMENT';
      data['order_number'] = null;
      data['is_active'] = false;
      data['timeline'] = <Object?>[];
      data['pickup_credential'] = <String, dynamic>{'available': false};

      final TrackedOrder tracked = await repositoryReturning(envelope)
          .tracking('a2f2017b-d106-4659-aa3a-df77c7837da5');

      /*
     * The exact case the device test opened, and the one the suite had no way
     * to reach: a customer tracking an order that was created but never paid
     * for. It must parse rather than throw -- a FormatException here is the
     * screen saying "We couldn't load this order" about an order that exists.
     */
      expect(tracked.order.orderNumber, isNull);
      expect(tracked.order.status, PlacedOrderStatus.awaitingPayment);
      expect(tracked.timeline, isEmpty);
      expect(tracked.pickupCredentialAvailable, isFalse);
    },
  );

  test(
    'the orders list reads active and past from the same envelope',
    () async {
      final Map<String, dynamic> summary = <String, dynamic>{
        'id': 'o-1',
        'order_number': 'FOTG-260909-9KFSGX9HVP',
        'status': 'PLACED',
        'status_title': 'Order placed',
        'currency': 'INR',
        'commercial': <String, dynamic>{
          'items_subtotal': <String, dynamic>{
            'amount_minor': 24900,
            'currency': 'INR',
          },
          'charges': <Object?>[],
          'discounts': <Object?>[],
          'payable_total': <String, dynamic>{
            'amount_minor': 24900,
            'currency': 'INR',
          },
        },
      };

      final List<PlacedOrder> orders = await repositoryReturning(
        <String, dynamic>{
          'data': <String, dynamic>{
            'active': <Object?>[summary],
            'past': <Object?>[],
            'orders': <Object?>[summary],
          },
        },
      ).mine();

      expect(orders, hasLength(1));
      expect(orders.single.statusLabel, 'Order placed');
    },
  );
}
