import 'cart.dart';
import 'money.dart';
import 'pickup.dart';
import 'pre_checkout.dart';

/// What has become of a checkout quote.
///
/// Two of these the server stores and two it works out on every read. The
/// client makes that distinction nowhere: it renders what it is told.
enum CheckoutStatus {
  active('ACTIVE'),
  stale('STALE'),
  expired('EXPIRED'),
  consumed('CONSUMED');

  const CheckoutStatus(this.wireValue);

  final String wireValue;

  /// An unknown status is not read as usable.
  ///
  /// A build meeting a status it has never heard of knows the server is saying
  /// something it cannot interpret, and the safe reading of that is not "carry
  /// on to a payment screen".
  static CheckoutStatus fromWire(Object? value) {
    if (value is String) {
      for (final CheckoutStatus status in CheckoutStatus.values) {
        if (status.wireValue == value) return status;
      }
    }

    return CheckoutStatus.stale;
  }

  bool get isUsable => this == CheckoutStatus.active;
}

/// One line of the commercial breakdown.
///
/// **A component the server did not send does not exist.** The client never
/// invents a zero row for a missing charge: an absent component means nobody
/// configured that rule, and rendering "Tax  ₹0.00" would state a decision the
/// platform has not made.
class CommercialLine {
  const CommercialLine({required this.code, required this.amount});

  /// A stable code the screen maps to a label. Unknown codes are still shown,
  /// using the code itself, rather than dropped — a charge a customer is paying
  /// must appear even on a build that predates it.
  final String code;

  final Money amount;

  static CommercialLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? code = json['code'] as String?;
    final Money? amount = Money.fromJson(json['amount']);

    if (code == null || amount == null) return null;

    return CommercialLine(code: code, amount: amount);
  }
}

/// What the customer will pay, and what each part of it is for.
class CommercialSummary {
  const CommercialSummary({
    required this.itemsSubtotal,
    required this.payableTotal,
    this.charges = const <CommercialLine>[],
    this.discounts = const <CommercialLine>[],
    this.hasConfiguredAdjustments = false,
  });

  final Money itemsSubtotal;
  final Money payableTotal;
  final List<CommercialLine> charges;
  final List<CommercialLine> discounts;

  /// The server saying so explicitly, rather than the client inferring it from
  /// an empty list. "Nothing is configured" and "the charges failed to send"
  /// look identical otherwise, and only one is a state to render as a price.
  final bool hasConfiguredAdjustments;

  static CommercialSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final Money? subtotal = Money.fromJson(json['items_subtotal']);
    final Money? payable = Money.fromJson(json['payable_total']);

    if (subtotal == null || payable == null) return null;

    List<CommercialLine> lines(Object? raw) => <CommercialLine>[
      for (final Object? entry in (raw as List<Object?>? ?? const <Object?>[]))
        if (CommercialLine.fromJson(entry) case final CommercialLine line) line,
    ];

    return CommercialSummary(
      itemsSubtotal: subtotal,
      payableTotal: payable,
      charges: lines(json['charges']),
      discounts: lines(json['discounts']),
      hasConfiguredAdjustments: json['has_configured_adjustments'] == true,
    );
  }
}

/// The journey a purchase sits on, as context.
class CheckoutJourney {
  const CheckoutJourney({this.origin, this.destination});

  final String? origin;
  final String? destination;

  bool get isReadable => origin != null && destination != null;

  static CheckoutJourney fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const CheckoutJourney();

    return CheckoutJourney(
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
    );
  }
}

/// Everything the server says about this purchase, right now.
class Checkout {
  const Checkout({
    required this.status,
    required this.readyForPayment,
    required this.commercial,
    this.checkoutId,
    this.restaurantName,
    this.journey = const CheckoutJourney(),
    this.pickup = const PickupSelection.none(),
    this.items = const <CartLine>[],
    this.expiresAt,
    DateTime? localExpiresAt,
    this.validation,
  }) : localExpiresAt = localExpiresAt ?? expiresAt;

  /// Null when no quote could be written — a basket nobody can buy is not
  /// given a price.
  final String? checkoutId;

  final CheckoutStatus status;

  /// **Read from the server, never derived.** A screen that worked this out
  /// from the issue list would be a second implementation of the rule, and the
  /// day the two disagree somebody reaches a payment for a kitchen that shut.
  final bool readyForPayment;

  final CommercialSummary commercial;
  final String? restaurantName;
  final CheckoutJourney journey;
  final PickupSelection pickup;
  final List<CartLine> items;

  /// The absolute instant the quote lapses, for comparing.
  final DateTime? expiresAt;

  /// The same moment as the counter's clock shows it, for reading.
  ///
  /// **Not `expiresAt.toLocal()`.** That renders the phone's zone, which on a
  /// device set to London puts "held until 8:10 am" under a 1:40 pm Delhi
  /// pickup — a third clock in a body the server took care to write on one.
  /// The offset the server chose is kept exactly as it sent it.
  final DateTime? localExpiresAt;

  /// Module 12's revalidation and Module 13's pickup layer, as the server
  /// reported them. The reasons behind a refusal.
  final PreCheckoutResult? validation;

  static Checkout? fromJson(Map<String, dynamic> data) {
    final CommercialSummary? commercial = CommercialSummary.fromJson(
      data['commercial'],
    );

    if (commercial == null) return null;

    final Map<String, dynamic> pickup =
        (data['pickup'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    return Checkout(
      checkoutId: data['checkout_id'] as String?,
      status: CheckoutStatus.fromWire(data['status']),
      readyForPayment: data['ready_for_payment'] == true,
      commercial: commercial,
      restaurantName:
          (data['restaurant'] as Map<String, dynamic>?)?['name'] as String?,
      journey: CheckoutJourney.fromJson(data['journey']),
      pickup: PickupSelection.fromJson(pickup['selection']),
      items: <CartLine>[
        for (final Object? raw
            in (data['items'] as List<Object?>? ?? const <Object?>[]))
          if (CartLine.fromJson(raw) case final CartLine line) line,
      ],
      expiresAt: data['expires_at'] is String
          ? DateTime.tryParse(data['expires_at'] as String)
          : null,
      localExpiresAt: wallClockOf(data['expires_at']),
      validation: data['validation'] is Map<String, dynamic>
          ? PreCheckoutResult.fromJson(<String, dynamic>{
              ...data['validation'] as Map<String, dynamic>,
              'pickup': pickup,
            })
          : null,
    );
  }
}
