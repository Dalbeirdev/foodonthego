import 'checkout.dart';
import 'money.dart';
import 'pickup.dart';

/// Where an order stands with respect to money, and nothing else.
///
/// **Deliberately not [OrderStatus].** That enum, declared speculatively in
/// Module 02, carries `cooking`, `ready` and `pickedUp` — a fulfilment workflow
/// nobody has specified and which the server does not send. Reusing it here
/// would mean a screen switching on states the API can never produce, and a
/// silent decision that those are the right states. When fulfilment is
/// specified, one of the two goes; until then they are separate because they
/// describe different things.
enum PlacedOrderStatus {
  /// Not an order. A payment target.
  ///
  /// Carries no order number and no pickup credential, and never appears in the
  /// Orders tab. Showing one to a customer as a purchase would tell them they
  /// had bought food they have not paid for.
  awaitingPayment('AWAITING_PAYMENT'),

  /// The order. Reached only from a captured payment.
  ///
  /// Replaces `paid` since Module 16. The old name asked a question about money
  /// of a record that no longer answers it — whether the customer paid is read
  /// from the payment, and whether an order exists is read from here.
  placed('PLACED'),

  paymentFailed('PAYMENT_FAILED'),
  cancelled('CANCELLED'),

  /// Declared, and not yet reachable.
  ///
  /// The server can send these the moment Modules 18–22 begin setting them, and
  /// a build that did not know them would fall back to `awaitingPayment` and
  /// tell a customer their collected order was unpaid. Knowing a state and
  /// implementing its workflow are different things: nothing here drives any
  /// screen beyond a label.
  accepted('ACCEPTED'),
  rejected('REJECTED'),
  cooking('COOKING'),
  ready('READY'),
  pickedUp('PICKED_UP'),
  refunded('REFUNDED');

  const PlacedOrderStatus(this.wireValue);

  final String wireValue;

  /// An unknown status is not read as paid.
  ///
  /// A build meeting a state it has never heard of knows the server is saying
  /// something it cannot interpret, and the safe reading of that is never "the
  /// money is in".
  static PlacedOrderStatus fromWire(Object? value) {
    if (value is String) {
      for (final PlacedOrderStatus status in PlacedOrderStatus.values) {
        if (status.wireValue == value) return status;
      }
    }

    return PlacedOrderStatus.awaitingPayment;
  }

  /// Whether this is a real order rather than a payment target.
  bool get isPlacedOrder =>
      this != PlacedOrderStatus.awaitingPayment &&
      this != PlacedOrderStatus.paymentFailed;

  bool get acceptsPayment =>
      this == PlacedOrderStatus.awaitingPayment ||
      this == PlacedOrderStatus.paymentFailed;

  /// Whether a pickup credential is worth asking the server for.
  bool get canBeCollected =>
      this == PlacedOrderStatus.placed ||
      this == PlacedOrderStatus.accepted ||
      this == PlacedOrderStatus.cooking ||
      this == PlacedOrderStatus.ready;

  /// What a customer is shown.
  ///
  /// "Order placed", never "Accepted" — the restaurant has not seen it yet, and
  /// a label that implied otherwise would be the app promising on their behalf.
  String get label => switch (this) {
    PlacedOrderStatus.awaitingPayment => 'Awaiting payment',
    PlacedOrderStatus.placed => 'Order placed',
    PlacedOrderStatus.paymentFailed => 'Payment failed',
    PlacedOrderStatus.cancelled => 'Cancelled',
    PlacedOrderStatus.accepted => 'Accepted by the restaurant',
    PlacedOrderStatus.rejected => 'Declined by the restaurant',
    PlacedOrderStatus.cooking => 'Being prepared',
    PlacedOrderStatus.ready => 'Ready for pickup',
    PlacedOrderStatus.pickedUp => 'Collected',
    PlacedOrderStatus.refunded => 'Refunded',
  };
}

/// One extra on an order line, as it was when the order was placed.
class OrderLineModifier {
  const OrderLineModifier({
    required this.group,
    required this.option,
    required this.priceDelta,
  });

  final String group;
  final String option;
  final Money priceDelta;

  static OrderLineModifier? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? group = json['group'] as String?;
    final String? option = json['option'] as String?;
    final Money? delta = Money.fromJson(json['price_delta']);

    if (group == null || option == null || delta == null) return null;

    return OrderLineModifier(group: group, option: option, priceDelta: delta);
  }
}

/// One dish on an order, at the name and price it was sold under.
///
/// These are snapshots. The server does not resolve them back through the menu
/// and neither does this app: a receipt that changed when a restaurant renamed
/// a dish would not be a receipt.
class OrderLine {
  const OrderLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.variant,
    this.specialInstructions,
    this.modifiers = const <OrderLineModifier>[],
  });

  final String id;
  final String name;
  final String? variant;
  final int quantity;
  final Money unitPrice;
  final Money lineTotal;
  final String? specialInstructions;
  final List<OrderLineModifier> modifiers;

  static OrderLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;
    final Money? unit = Money.fromJson(json['unit_price']);
    final Money? total = Money.fromJson(json['line_total']);
    final Object? quantity = json['quantity'];

    if (id == null || name == null || unit == null || total == null) {
      return null;
    }

    return OrderLine(
      id: id,
      name: name,
      variant: json['variant'] as String?,
      quantity: quantity is int ? quantity : 1,
      unitPrice: unit,
      lineTotal: total,
      specialInstructions: json['special_instructions'] as String?,
      modifiers: <OrderLineModifier>[
        for (final Object? entry
            in (json['modifiers'] as List<Object?>? ?? const <Object?>[]))
          if (OrderLineModifier.fromJson(entry) case final OrderLineModifier m)
            m,
      ],
    );
  }
}

/// What the server says about this order's payment.
///
/// Carries no failure text. A provider's decline reason is written for a
/// merchant dashboard and the server does not relay it, so there is no field
/// here into which one could arrive.
class OrderPaymentSummary {
  const OrderPaymentSummary({
    required this.id,
    required this.status,
    this.provider,
    this.providerOrderId,
    this.verifiedAt,
    this.verificationSource,
  });

  final String id;
  final String status;
  final String? provider;
  final String? providerOrderId;
  final DateTime? verifiedAt;
  final String? verificationSource;

  static OrderPaymentSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final String? status = json['status'] as String?;

    if (id == null || status == null) return null;

    return OrderPaymentSummary(
      id: id,
      status: status,
      provider: json['provider'] as String?,
      providerOrderId: json['provider_order_id'] as String?,
      verifiedAt: wallClockOf(json['verified_at']),
      verificationSource: json['verification_source'] as String?,
    );
  }
}

/// An order that exists, at a price that no longer moves.
class PlacedOrder {
  const PlacedOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.commercial,
    this.restaurantName,
    this.pickupStartAt,
    this.pickupEndAt,
    this.pickupTimezone,
    this.placedAt,
    this.paidAt,
    this.items = const <OrderLine>[],
    this.payment,
  });

  final String id;
  final String orderNumber;
  final PlacedOrderStatus status;
  final CommercialSummary commercial;
  final String? restaurantName;

  /// Wall-clock instants, read the way Module 13 established: `DateTime.parse`
  /// discards the offset and hands back something flagged UTC, so these go
  /// through [wallClockOf] and are rendered as the restaurant's own clock.
  final DateTime? pickupStartAt;
  final DateTime? pickupEndAt;
  final String? pickupTimezone;
  final DateTime? placedAt;
  final DateTime? paidAt;

  final List<OrderLine> items;
  final OrderPaymentSummary? payment;

  /// Whether this is a placed order rather than a payment target.
  ///
  /// Renamed from isPaid in Module 16: whether the customer's money arrived is
  /// a question about the payment, and whether an order exists is a question
  /// about the order. One field cannot answer both without lying about one.
  bool get isPlaced => status.isPlacedOrder;

  static PlacedOrder? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final String? number = json['order_number'] as String?;
    final CommercialSummary? commercial = CommercialSummary.fromJson(
      json['commercial'],
    );

    if (id == null || number == null || commercial == null) return null;

    final Object? pickup = json['pickup'];
    final Map<String, dynamic> pickupMap = pickup is Map<String, dynamic>
        ? pickup
        : const <String, dynamic>{};

    final Object? restaurant = json['restaurant'];

    return PlacedOrder(
      id: id,
      orderNumber: number,
      status: PlacedOrderStatus.fromWire(json['status']),
      commercial: commercial,
      restaurantName: restaurant is Map<String, dynamic>
          ? restaurant['name'] as String?
          : null,
      pickupStartAt: wallClockOf(pickupMap['start_at']),
      pickupEndAt: wallClockOf(pickupMap['end_at']),
      pickupTimezone: pickupMap['timezone'] as String?,
      placedAt: wallClockOf(json['placed_at']),
      paidAt: wallClockOf(json['paid_at']),
      items: <OrderLine>[
        for (final Object? entry
            in (json['items'] as List<Object?>? ?? const <Object?>[]))
          if (OrderLine.fromJson(entry) case final OrderLine line) line,
      ],
      payment: OrderPaymentSummary.fromJson(json['payment']),
    );
  }
}

/// What the app needs to open a provider checkout.
///
/// [publicKeyId] is public by definition — the provider's SDK requires it in
/// the client. **There is no secret here and there never can be**: the server
/// sends none, and a field for one would be a field somebody eventually fills.
///
/// [amount] is for display. It is not sent back, and the server would not read
/// it if it were.
class PaymentIntent {
  const PaymentIntent({
    required this.order,
    required this.paymentId,
    required this.providerOrderId,
    required this.amount,
    this.provider,
    this.publicKeyId,
  });

  final PlacedOrder order;
  final String paymentId;
  final String providerOrderId;
  final Money amount;
  final String? provider;
  final String? publicKeyId;

  /// Whether a provider checkout could actually be opened with this.
  ///
  /// False when no credentials are configured, which is the current state of
  /// this project. A screen must not present a pay button that leads nowhere.
  bool get isOpenable => (publicKeyId ?? '').isNotEmpty;

  static PaymentIntent? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final PlacedOrder? order = PlacedOrder.fromJson(json['order']);
    final Object? payment = json['payment'];

    if (order == null || payment is! Map<String, dynamic>) return null;

    final String? paymentId = payment['id'] as String?;
    final String? providerOrderId = payment['provider_order_id'] as String?;
    final Money? amount = Money.fromJson(payment['amount']);

    if (paymentId == null || providerOrderId == null || amount == null) {
      return null;
    }

    return PaymentIntent(
      order: order,
      paymentId: paymentId,
      providerOrderId: providerOrderId,
      amount: amount,
      provider: payment['provider'] as String?,
      publicKeyId: payment['public_key_id'] as String?,
    );
  }
}
