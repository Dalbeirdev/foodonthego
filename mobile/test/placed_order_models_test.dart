import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/placed_order.dart';

/// Reading an order off the wire.
///
/// The theme is that a build which does not understand a response must not
/// guess in the customer's favour. An unknown status is not "paid"; a body
/// missing a total is not an order at all.
void main() {
  Map<String, dynamic> orderJson({
    String status = 'AWAITING_PAYMENT',
    Object? commercial,
    Object? payment,
  }) => <String, dynamic>{
    'id': 'order-uuid',
    'order_number': '260916-7K2M9QX4TB',
    'status': status,
    'currency': 'INR',
    'restaurant': <String, dynamic>{'id': 'r1', 'name': 'Spice Kitchen'},
    'pickup': <String, dynamic>{
      'start_at': '2026-09-16T13:20:00+05:30',
      'end_at': '2026-09-16T13:35:00+05:30',
      'timezone': 'Asia/Kolkata',
    },
    'commercial':
        commercial ??
        <String, dynamic>{
          'items_subtotal': <String, dynamic>{
            'amount_minor': 49800,
            'currency': 'INR',
          },
          'charges': <Object?>[],
          'discounts': <Object?>[],
          'payable_total': <String, dynamic>{
            'amount_minor': 49800,
            'currency': 'INR',
          },
          'has_configured_adjustments': false,
        },
    'placed_at': '2026-09-16T12:40:00+05:30',
    'paid_at': null,
    'items': <Object?>[
      <String, dynamic>{
        'id': 'line-1',
        'name': 'Paneer Tikka',
        'variant': 'Large',
        'quantity': 2,
        'unit_price': <String, dynamic>{
          'amount_minor': 24900,
          'currency': 'INR',
        },
        'line_total': <String, dynamic>{
          'amount_minor': 49800,
          'currency': 'INR',
        },
        'modifiers': <Object?>[
          <String, dynamic>{
            'group': 'Extras',
            'option': 'Extra cheese',
            'price_delta': <String, dynamic>{
              'amount_minor': 4000,
              'currency': 'INR',
            },
          },
        ],
      },
    ],
    'payment': payment,
  };

  group('PlacedOrder', () {
    test('reads the documented shape', () {
      final PlacedOrder? order = PlacedOrder.fromJson(orderJson());

      expect(order, isNotNull);
      expect(order!.orderNumber, '260916-7K2M9QX4TB');
      expect(order.status, PlacedOrderStatus.awaitingPayment);
      expect(order.restaurantName, 'Spice Kitchen');
      expect(order.commercial.payableTotal.amountMinor, 49800);
      expect(order.items, hasLength(1));
      expect(order.items.first.variant, 'Large');
      expect(order.items.first.modifiers.first.option, 'Extra cheese');
    });

    test('a paid order reads as paid', () {
      expect(
        PlacedOrder.fromJson(orderJson(status: 'PLACED'))!.isPlaced,
        isTrue,
      );
    });

    /// The important direction. A build meeting a status it has never heard of
    /// knows the server is saying something it cannot interpret, and the safe
    /// reading of that is never "the money is in".
    test('an unknown status is never read as paid', () {
      final PlacedOrder order = PlacedOrder.fromJson(
        orderJson(status: 'SOMETHING_INVENTED_LATER'),
      )!;

      expect(order.isPlaced, isFalse);
      expect(order.status, PlacedOrderStatus.awaitingPayment);
    });

    test('a body with no commercial block is not an order', () {
      final Map<String, dynamic> json = orderJson()..remove('commercial');

      expect(PlacedOrder.fromJson(json), isNull);
    });

    /// Deliberately inverted in Module 16.
    ///
    /// This used to assert that a body without an order number is not an order.
    /// It is now the ordinary shape of a payment target: the number is minted
    /// when the money is captured, so the response the app receives between
    /// creating an order and paying for it has none. Refusing to parse it took
    /// down the payment screen on device while every widget test passed against
    /// a fake that always supplied a number.
    ///
    /// The id and the commercial summary are still required, because a screen
    /// cannot render without them.
    test('a body with no order number is still a parsable payment target', () {
      final Map<String, dynamic> json = orderJson()..remove('order_number');

      final PlacedOrder? order = PlacedOrder.fromJson(json);

      expect(order, isNotNull);
      expect(order!.orderNumber, isNull);
    });

    test('a body with no id is not an order', () {
      final Map<String, dynamic> json = orderJson()..remove('id');

      expect(PlacedOrder.fromJson(json), isNull);
    });

    /// Module 13's rule, still holding. `DateTime.parse` discards the offset
    /// and hands back an instant flagged UTC, so a screen rendering it shows a
    /// pickup window hours away from the one the restaurant meant.
    test('instants keep the wall clock the server sent', () {
      final PlacedOrder order = PlacedOrder.fromJson(orderJson())!;

      expect(order.pickupStartAt!.hour, 13);
      expect(order.pickupStartAt!.minute, 20);
      expect(order.pickupTimezone, 'Asia/Kolkata');
    });

    test('a payment block is read when present and absent when not', () {
      expect(PlacedOrder.fromJson(orderJson())!.payment, isNull);

      final PlacedOrder withPayment = PlacedOrder.fromJson(
        orderJson(
          status: 'PLACED',
          payment: <String, dynamic>{
            'id': 'payment-uuid',
            'status': 'CAPTURED',
            'provider': 'razorpay',
            'provider_order_id': 'order_ABC',
            'verified_at': '2026-09-16T12:45:00+05:30',
            'verification_source': 'CLIENT_CALLBACK',
          },
        ),
      )!;

      expect(withPayment.payment!.status, 'CAPTURED');
      expect(withPayment.payment!.verifiedAt!.hour, 12);
    });
  });

  group('PaymentIntent', () {
    Map<String, dynamic> intentJson({String? publicKeyId}) => <String, dynamic>{
      'order': orderJson(),
      'payment': <String, dynamic>{
        'id': 'payment-uuid',
        'provider': 'razorpay',
        'provider_order_id': 'order_ABC123',
        'status': 'CREATED',
        'amount': <String, dynamic>{'amount_minor': 49800, 'currency': 'INR'},
        'public_key_id': ?publicKeyId,
      },
    };

    test('reads the documented shape', () {
      final PaymentIntent intent = PaymentIntent.fromJson(
        intentJson(publicKeyId: 'rzp_test_abc'),
      )!;

      expect(intent.providerOrderId, 'order_ABC123');
      expect(intent.amount.amountMinor, 49800);
      expect(intent.isOpenable, isTrue);
    });

    /// This project's actual state: no credentials, so no checkout can open.
    /// A screen must be able to tell, rather than offering a button that leads
    /// nowhere.
    test('with no public key the intent is not openable', () {
      expect(PaymentIntent.fromJson(intentJson())!.isOpenable, isFalse);
      expect(
        PaymentIntent.fromJson(intentJson(publicKeyId: ''))!.isOpenable,
        isFalse,
      );
    });

    /// There is no field for a secret, so a server that somehow sent one has
    /// nowhere to put it. Asserted rather than assumed, because the absence is
    /// the security property.
    test('an intent has no field a key secret could arrive in', () {
      final Map<String, dynamic> json = intentJson(publicKeyId: 'rzp_test_abc');
      (json['payment']! as Map<String, dynamic>)['key_secret'] =
          'should-never-be-read';

      final PaymentIntent intent = PaymentIntent.fromJson(json)!;

      expect(intent.publicKeyId, 'rzp_test_abc');
      expect(intent.toString().contains('should-never-be-read'), isFalse);
    });

    test('a body with no payment block is not an intent', () {
      expect(
        PaymentIntent.fromJson(<String, dynamic>{'order': orderJson()}),
        isNull,
      );
    });
  });

  group('PlacedOrderStatus', () {
    test('a failed payment leaves the order payable', () {
      expect(PlacedOrderStatus.paymentFailed.acceptsPayment, isTrue);
      expect(PlacedOrderStatus.awaitingPayment.acceptsPayment, isTrue);
      expect(PlacedOrderStatus.placed.acceptsPayment, isFalse);
      expect(PlacedOrderStatus.cancelled.acceptsPayment, isFalse);
    });
  });
}
