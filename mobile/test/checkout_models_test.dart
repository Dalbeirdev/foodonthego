import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/checkout.dart';
import 'package:foodonthego/domain/models/money.dart';

/// Parsing what the server says about a purchase.
///
/// The theme is that **the client decides nothing here**. Every figure and every
/// verdict below is read from the response; the tests that matter are the ones
/// where a plausible client-side derivation would give a different answer, and
/// the parser is required to keep the server's.
void main() {
  Map<String, dynamic> money(int minor) => <String, dynamic>{
    'amount_minor': minor,
    'currency': 'INR',
  };

  Map<String, dynamic> body({
    String status = 'ACTIVE',
    bool readyForPayment = true,
    int subtotal = 49_800,
    int? payable,
    List<Map<String, dynamic>> charges = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> discounts = const <Map<String, dynamic>>[],
    bool? hasConfiguredAdjustments,
    String? expiresAt = '2026-09-07T12:10:00+05:30',
    List<Map<String, dynamic>> issues = const <Map<String, dynamic>>[],
  }) => <String, dynamic>{
    'checkout_id': 'quote-aaa1f3c',
    'status': status,
    'currency': 'INR',
    'restaurant': <String, dynamic>{'name': 'Highway Spice Kitchen'},
    'journey': <String, dynamic>{'origin': 'Delhi', 'destination': 'Jaipur'},
    'pickup': <String, dynamic>{
      'selection': <String, dynamic>{
        'status': 'SELECTED',
        'start_at': '2026-09-07T13:40:00+05:30',
        'end_at': '2026-09-07T13:50:00+05:30',
        'timezone': 'Asia/Kolkata',
      },
    },
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'line-1',
        'name': 'Paneer Tikka',
        'quantity': 2,
        'unit_price': money(24_900),
        'line_total': money(49_800),
      },
    ],
    'commercial': <String, dynamic>{
      'items_subtotal': money(subtotal),
      'payable_total': money(payable ?? subtotal),
      'charges': charges,
      'discounts': discounts,
      if (hasConfiguredAdjustments case final bool flag)
        'has_configured_adjustments': flag,
    },
    'expires_at': expiresAt,
    'ready_for_payment': readyForPayment,
    'validation': <String, dynamic>{
      'ready_for_checkout': readyForPayment,
      'selection_status': 'SELECTED',
      'issues': issues,
    },
  };

  // --- the money ------------------------------------------------------------

  test('the payable total is read, never re-added from the parts', () {
    // The server says the parts sum to 498 and the payable is 560. They do not
    // agree, and that is the point: a client that summed the rows would show
    // 498 and take a payment for 560. Whatever the server's reason — a rounding
    // rule, a component this build has never heard of — its total is the one
    // the customer agrees to.
    final Checkout checkout = Checkout.fromJson(
      body(
        subtotal: 49_800,
        payable: 56_000,
        charges: <Map<String, dynamic>>[
          <String, dynamic>{'code': 'TAX', 'amount': money(2_490)},
        ],
      ),
    )!;

    expect(checkout.commercial.payableTotal.amountMinor, 56_000);
    expect(checkout.commercial.itemsSubtotal.amountMinor, 49_800);
  });

  test('a component the server did not send does not exist', () {
    final Checkout checkout = Checkout.fromJson(body())!;

    expect(checkout.commercial.charges, isEmpty);
    expect(checkout.commercial.discounts, isEmpty);

    // And nothing invented a zero row to fill the gap.
    expect(checkout.commercial.hasConfiguredAdjustments, isFalse);
  });

  test('a charge configured as zero is a row, not an absence', () {
    // The difference this whole design turns on. "Nobody has configured a
    // packaging fee" and "the packaging fee is set to nothing" are different
    // facts, and only the second is a line on a receipt.
    final Checkout checkout = Checkout.fromJson(
      body(
        charges: <Map<String, dynamic>>[
          <String, dynamic>{'code': 'PACKAGING_FEE', 'amount': money(0)},
        ],
        hasConfiguredAdjustments: true,
      ),
    )!;

    expect(checkout.commercial.charges, hasLength(1));
    expect(checkout.commercial.charges.single.code, 'PACKAGING_FEE');
    expect(checkout.commercial.charges.single.amount.amountMinor, 0);
  });

  test('an unknown charge code survives parsing', () {
    // An old build meeting a charge introduced after it shipped. Dropping it
    // would hide money the customer is being asked to pay.
    final Checkout checkout = Checkout.fromJson(
      body(
        charges: <Map<String, dynamic>>[
          <String, dynamic>{'code': 'CONGESTION_LEVY', 'amount': money(1_500)},
        ],
        hasConfiguredAdjustments: true,
      ),
    )!;

    expect(checkout.commercial.charges.single.code, 'CONGESTION_LEVY');
  });

  test('an empty charge list with the flag set is believed', () {
    // The flag is the server's statement, not a summary of the lists. A client
    // that recomputed it from `charges.isEmpty` would contradict the server,
    // and the whole point of sending it is that the client does not decide.
    final Checkout checkout = Checkout.fromJson(
      body(hasConfiguredAdjustments: true),
    )!;

    expect(checkout.commercial.charges, isEmpty);
    expect(checkout.commercial.hasConfiguredAdjustments, isTrue);
  });

  test('a total sent as a decimal is refused rather than rounded', () {
    // Rupees where minor units belong. Rounding it here would introduce exactly
    // the error integer money exists to prevent, so the whole body is refused.
    final Map<String, dynamic> data = body();
    (data['commercial'] as Map<String, dynamic>)['payable_total'] =
        <String, dynamic>{'amount_minor': 498.5, 'currency': 'INR'};

    expect(Checkout.fromJson(data), isNull);
  });

  test('money is formatted from the minor units, never from a float', () {
    final Money total = Checkout.fromJson(body(subtotal: 32_900))!
        .commercial
        .payableTotal;

    expect(total.amountMinor, 32_900);
    expect(total.format(locale: 'en_IN'), '₹329');
  });

  // --- readiness ------------------------------------------------------------

  test('readiness is the server flag, not an empty issue list', () {
    // The case that matters: no issues in the body, and the server still says
    // no. A client deriving readiness from `issues.isEmpty` would send this
    // customer to a payment screen.
    final Checkout checkout = Checkout.fromJson(body(readyForPayment: false))!;

    expect(checkout.readyForPayment, isFalse);
    expect(checkout.validation!.issues, isEmpty);
  });

  test('readiness is false when the field is missing', () {
    final Map<String, dynamic> data = body()..remove('ready_for_payment');

    expect(Checkout.fromJson(data)!.readyForPayment, isFalse);
  });

  test('a blocking issue is separated from a notice', () {
    final Checkout checkout = Checkout.fromJson(
      body(
        readyForPayment: false,
        issues: <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'LINE_UNAVAILABLE',
            'message': 'Paneer Tikka has sold out.',
            'blocking': true,
          },
          <String, dynamic>{
            'code': 'PRICE_DECREASED',
            'message': 'One price has come down.',
            'blocking': false,
          },
        ],
      ),
    )!;

    expect(checkout.validation!.blockers, hasLength(1));
    expect(checkout.validation!.notices, hasLength(1));
    expect(checkout.validation!.blockers.single.message, contains('sold out'));
  });

  // --- the quote's own state ------------------------------------------------

  test('each status round trips', () {
    for (final CheckoutStatus status in CheckoutStatus.values) {
      expect(Checkout.fromJson(body(status: status.wireValue))!.status, status);
    }
  });

  test('a status this build has never heard of is not read as usable', () {
    final CheckoutStatus status = Checkout.fromJson(body(status: 'SETTLING'))!
        .status;

    expect(status.isUsable, isFalse);

    // Not merely "not active" — it must not be silently treated as expired
    // either, which would offer a refresh that fixes nothing.
    expect(status, CheckoutStatus.stale);
  });

  test('an absent status is not read as usable', () {
    final Map<String, dynamic> data = body()..remove('status');

    expect(Checkout.fromJson(data)!.status.isUsable, isFalse);
  });

  // --- one response, one clock ---------------------------------------------

  test('the expiry keeps the clock the server wrote it on', () {
    final Checkout checkout = Checkout.fromJson(body())!;

    // The wall-clock reading, exactly as sent: 12:10, not 6:40 UTC and not
    // whatever the test machine's zone would make of it.
    expect(checkout.localExpiresAt!.hour, 12);
    expect(checkout.localExpiresAt!.minute, 10);

    // And the instant is kept beside it for comparing — the same moment, six
    // and a half hours' offset apart.
    expect(checkout.expiresAt!.toUtc().hour, 6);
    expect(checkout.expiresAt!.toUtc().minute, 40);
  });

  test('the pickup window keeps the clock too', () {
    final Checkout checkout = Checkout.fromJson(body())!;

    expect(checkout.pickup.localStartAt!.hour, 13);
    expect(checkout.pickup.localEndAt!.hour, 13);
    expect(checkout.pickup.localEndAt!.minute, 50);
  });

  test('a missing expiry is null rather than a fabricated one', () {
    final Checkout checkout = Checkout.fromJson(body(expiresAt: null))!;

    expect(checkout.expiresAt, isNull);
    expect(checkout.localExpiresAt, isNull);
  });

  // --- the rest of the body -------------------------------------------------

  test('a checkout with no quote still parses', () {
    // What the server sends for a basket it will not price. The screen needs
    // the reasons, and they are in the same body.
    final Map<String, dynamic> data = body(readyForPayment: false)
      ..['checkout_id'] = null;

    final Checkout checkout = Checkout.fromJson(data)!;

    expect(checkout.checkoutId, isNull);
    expect(checkout.readyForPayment, isFalse);
  });

  test('a body with no commercial block is refused whole', () {
    // A checkout screen without a total has nothing honest to draw.
    final Map<String, dynamic> data = body()..remove('commercial');

    expect(Checkout.fromJson(data), isNull);
  });

  test('the journey reads as sent', () {
    final Checkout checkout = Checkout.fromJson(body())!;

    expect(checkout.journey.origin, 'Delhi');
    expect(checkout.journey.destination, 'Jaipur');
    expect(checkout.journey.isReadable, isTrue);
  });

  test('a half-known journey is not readable', () {
    final Map<String, dynamic> data = body();
    (data['journey'] as Map<String, dynamic>)['destination'] = null;

    expect(Checkout.fromJson(data)!.journey.isReadable, isFalse);
  });

  test('the lines carry their configuration', () {
    final Map<String, dynamic> data = body();
    (data['items'] as List<Map<String, dynamic>>).single['variant_name'] =
        'Large';
    (data['items'] as List<Map<String, dynamic>>).single['modifiers'] =
        <Map<String, dynamic>>[
          <String, dynamic>{'group_name': 'Spice', 'option_name': 'Mild'},
        ];

    final Checkout checkout = Checkout.fromJson(data)!;

    expect(checkout.items.single.configurationSummary, 'Large · Mild');
  });
}
