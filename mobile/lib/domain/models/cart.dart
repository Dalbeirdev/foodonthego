import 'money.dart';

/// One option a customer chose, and what it cost.
class CartLineModifier {
  const CartLineModifier({
    required this.groupName,
    required this.optionName,
    this.priceDelta,
  });

  final String groupName;
  final String optionName;
  final Money? priceDelta;

  static CartLineModifier? fromJson(Map<String, dynamic> json) {
    final String? group = json['group_name'] as String?;
    final String? option = json['option_name'] as String?;

    if (group == null || option == null) return null;

    return CartLineModifier(
      groupName: group,
      optionName: option,
      priceDelta: Money.fromJson(json['price_delta']),
    );
  }
}

/// One step of the arithmetic behind a price.
///
/// The breakdown is not decoration. A customer looking at ₹778 should be able
/// to see where it came from, because a total nobody can check is a total
/// nobody trusts.
class PriceBreakdownLine {
  const PriceBreakdownLine({
    required this.label,
    required this.amount,
    this.group,
  });

  final String label;
  final Money amount;

  /// Which question this answer came from, for the addition lines.
  final String? group;

  static PriceBreakdownLine? fromJson(Map<String, dynamic> json) {
    final Money? amount = Money.fromJson(json['amount']);
    final String label =
        (json['name'] as String?) ?? (json['label'] as String?) ?? '';

    if (amount == null || label.isEmpty) return null;

    return PriceBreakdownLine(
      label: label,
      amount: amount,
      group: json['group'] as String?,
    );
  }
}

/// What a configuration costs, with the arithmetic shown.
class PriceBreakdown {
  const PriceBreakdown({
    required this.base,
    required this.additions,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  final PriceBreakdownLine base;
  final List<PriceBreakdownLine> additions;
  final Money unitPrice;
  final int quantity;
  final Money lineTotal;

  /// The paid additions only. A free choice belongs in the list the server
  /// sends — it confirms the choice landed — and not in a column of charges.
  List<PriceBreakdownLine> get paidAdditions => <PriceBreakdownLine>[
    for (final PriceBreakdownLine line in additions)
      if (!line.amount.isZero) line,
  ];

  static PriceBreakdown? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final Object? rawBase = json['base'];

    if (rawBase is! Map<String, dynamic>) return null;

    final PriceBreakdownLine? base = PriceBreakdownLine.fromJson(rawBase);
    final Money? unit = Money.fromJson(json['unit_price']);
    final Money? total = Money.fromJson(json['line_total']);

    if (base == null || unit == null || total == null) return null;

    return PriceBreakdown(
      base: base,
      additions: <PriceBreakdownLine>[
        for (final Object? raw
            in (json['additions'] as List<Object?>? ?? const []))
          if (raw is Map<String, dynamic>)
            if (PriceBreakdownLine.fromJson(raw)
                case final PriceBreakdownLine l)
              l,
      ],
      unitPrice: unit,
      quantity: _int(json['quantity']) ?? 1,
      lineTotal: total,
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// What the customer has so far, as much of it as a badge needs.
///
/// Module 11 builds no cart screen, so this is deliberately thin: a count, a
/// restaurant and a subtotal. Enough for "2 items · ₹778" and not enough to
/// render a cart from, because a half-built cart screen is worse than none.
class CartSummary {
  const CartSummary({
    required this.itemCount,
    required this.lineCount,
    this.id,
    this.restaurantId,
    this.restaurantName,
    this.subtotal,
  });

  const CartSummary.empty() : this(itemCount: 0, lineCount: 0);

  final String? id;
  final String? restaurantId;
  final String? restaurantName;

  /// Individual things, counting quantities — two paneer tikka is two.
  final int itemCount;

  /// Distinct configurations.
  final int lineCount;

  /// The sum of the lines.
  ///
  /// A subtotal and never a total: there are no taxes, fees or charges yet,
  /// and calling it a total would promise a figure nobody has calculated.
  final Money? subtotal;

  bool get isEmpty => itemCount == 0;

  static CartSummary fromJson(Map<String, dynamic> data) {
    final Object? cart = data['cart'];

    final int items = _int(data['item_count']) ?? 0;
    final int lines = _int(data['line_count']) ?? 0;

    if (cart is! Map<String, dynamic>) {
      return CartSummary(itemCount: items, lineCount: lines);
    }

    return CartSummary(
      id: cart['id'] as String?,
      restaurantId: cart['restaurant_id'] as String?,
      restaurantName: cart['restaurant_name'] as String?,
      itemCount: items,
      lineCount: lines,
      subtotal: Money.fromJson(cart['subtotal']),
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// The server's answer to "add this to my cart".
///
/// Every figure here was calculated by the server. The client's preview was a
/// guess for the sake of a responsive screen; this is what the customer is
/// actually committed to.
class CartAddition {
  const CartAddition({
    required this.cartId,
    required this.cartItemId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.cart,
    this.breakdown,
    this.mergedWithExistingLine = false,
  });

  final String cartId;
  final String cartItemId;
  final int quantity;
  final Money unitPrice;
  final Money lineTotal;

  /// True when this went into a line the customer already had.
  final bool mergedWithExistingLine;

  final PriceBreakdown? breakdown;
  final CartSummary cart;

  static CartAddition? fromJson(Map<String, dynamic> data) {
    final String? cartId = data['cart_id'] as String?;
    final String? itemId = data['cart_item_id'] as String?;
    final Money? unit = Money.fromJson(data['unit_price']);
    final Money? total = Money.fromJson(data['line_total']);

    if (cartId == null || itemId == null || unit == null || total == null) {
      return null;
    }

    final Object? cart = data['cart'];

    return CartAddition(
      cartId: cartId,
      cartItemId: itemId,
      quantity: _int(data['quantity']) ?? 1,
      unitPrice: unit,
      lineTotal: total,
      mergedWithExistingLine: data['merged_with_existing_line'] == true,
      breakdown: PriceBreakdown.fromJson(data['breakdown']),
      cart: cart is Map<String, dynamic>
          ? CartSummary.fromJson(<String, dynamic>{
              'cart': cart,
              'item_count': cart['item_count'],
              'line_count': cart['line_count'],
            })
          : const CartSummary.empty(),
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// One line of a cart: a configured dish, and what it costs.
///
/// The names are the server's snapshots, taken when the line was added. A
/// restaurant that renames a dish tomorrow does not rewrite what the customer
/// chose today, and this class carries what they chose rather than what the
/// menu currently says.
class CartLine {
  const CartLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.itemId,
    this.variantName,
    this.specialInstructions,
    this.modifiers = const <CartLineModifier>[],
  });

  /// The cart line's own id — what a quantity change or a removal addresses.
  /// Not the menu item's; two lines can be the same dish configured
  /// differently, and they are edited independently.
  final String id;

  /// The menu item, for reopening the dish to change a choice.
  final String? itemId;

  final String name;
  final String? variantName;

  final int quantity;
  final Money unitPrice;
  final Money lineTotal;

  final String? specialInstructions;
  final List<CartLineModifier> modifiers;

  /// The chosen options as one line of text: "Large · Mild · Extra Cheese".
  ///
  /// Assembled here rather than in a widget so the cart screen and any later
  /// receipt describe a configuration the same way.
  String get configurationSummary => <String>[
    if (variantName case final String v) v,
    for (final CartLineModifier m in modifiers) m.optionName,
  ].join(' · ');

  bool get hasNote => (specialInstructions ?? '').trim().isNotEmpty;

  static CartLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;
    final Money? unit = Money.fromJson(json['unit_price']);
    final Money? total = Money.fromJson(json['line_total']);

    // A line missing its id cannot be edited, and one missing a price cannot be
    // shown honestly. Either way it is dropped rather than rendered with a gap
    // where a figure should be — see [Cart.fromJson] for what the screen does
    // about the difference that leaves.
    if (id == null || name == null || unit == null || total == null) {
      return null;
    }

    return CartLine(
      id: id,
      itemId: json['item_id'] as String?,
      name: name,
      variantName: json['variant_name'] as String?,
      quantity: _int(json['quantity']) ?? 1,
      unitPrice: unit,
      lineTotal: total,
      specialInstructions: json['special_instructions'] as String?,
      modifiers: <CartLineModifier>[
        for (final Object? raw
            in (json['modifiers'] as List<Object?>? ?? const <Object?>[]))
          if (raw is Map<String, dynamic>)
            if (CartLineModifier.fromJson(raw) case final CartLineModifier m) m,
      ],
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// What a cart costs, broken down.
///
/// Every figure is the server's. Nothing here is added up on the device: a
/// client that computed its own total would eventually disagree with the one
/// the customer is charged, and the disagreement would surface at the counter.
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.tax,
    required this.packagingFee,
    required this.platformFee,
    required this.total,
  });

  final Money subtotal;
  final Money tax;
  final Money packagingFee;
  final Money platformFee;
  final Money total;

  /// The charges worth a row of their own.
  ///
  /// A zero fee is not shown. "Platform fee ₹0.00" is a line a customer has to
  /// read to discover it is nothing, and a summary is easier to check the
  /// fewer nothings it contains. The total is always shown, zero or not.
  List<({String kind, Money amount})> get charges =>
      <({String kind, Money amount})>[
        if (!tax.isZero) (kind: 'tax', amount: tax),
        if (!packagingFee.isZero) (kind: 'packaging', amount: packagingFee),
        if (!platformFee.isZero) (kind: 'platform', amount: platformFee),
      ];

  static CartTotals? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final Money? subtotal = Money.fromJson(json['subtotal']);
    final Money? total = Money.fromJson(json['total']);

    if (subtotal == null || total == null) return null;

    final Money zero = Money(amountMinor: 0, currency: total.currency);

    return CartTotals(
      subtotal: subtotal,
      tax: Money.fromJson(json['tax']) ?? zero,
      packagingFee: Money.fromJson(json['packaging_fee']) ?? zero,
      platformFee: Money.fromJson(json['platform_fee']) ?? zero,
      total: total,
    );
  }
}

/// A customer's cart, in full.
///
/// The thing [CartSummary] is the badge-sized view of. Both are parsed from the
/// server; neither is assembled on the device from the other.
class Cart {
  const Cart({
    required this.id,
    required this.lines,
    required this.totals,
    required this.itemCount,
    required this.lineCount,
    this.restaurantId,
    this.restaurantName,
    this.tripId,
    this.expiresAt,
  });

  final String id;
  final String? restaurantId;
  final String? restaurantName;
  final String? tripId;

  final List<CartLine> lines;
  final CartTotals totals;

  /// Individual things, counting quantities. The server's count, not
  /// `lines.length` and not a sum computed here — a line the client could not
  /// read must not quietly reduce the number the customer is shown.
  final int itemCount;

  /// Distinct configurations, as the server counted them.
  final int lineCount;

  final DateTime? expiresAt;

  /// True when a line the server sent could not be read.
  ///
  /// The screen says so rather than showing a shorter cart than the customer
  /// has. A total that does not match the visible lines is alarming; a total
  /// that matches lines quietly omitted is worse.
  bool get hasUnreadableLines => lines.length != lineCount;

  static Cart? fromJson(Object? json, {int itemCount = 0, int lineCount = 0}) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final CartTotals? totals = CartTotals.fromJson(json['totals']);

    if (id == null || totals == null) return null;

    return Cart(
      id: id,
      restaurantId: json['restaurant_id'] as String?,
      restaurantName: json['restaurant_name'] as String?,
      tripId: json['trip_id'] as String?,
      lines: <CartLine>[
        for (final Object? raw
            in (json['items'] as List<Object?>? ?? const <Object?>[]))
          if (CartLine.fromJson(raw) case final CartLine line) line,
      ],
      totals: totals,
      itemCount: itemCount,
      lineCount: lineCount,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    );
  }
}

/// The server's answer to "what is in my cart".
///
/// A cart or the absence of one, and never an error for the absence. A customer
/// who has added nothing has an empty cart, and a client that treated "no cart"
/// as a failure would show an error on a perfectly ordinary screen.
class CartView {
  const CartView({required this.itemCount, required this.lineCount, this.cart});

  const CartView.empty() : this(itemCount: 0, lineCount: 0);

  final Cart? cart;
  final int itemCount;
  final int lineCount;

  bool get isEmpty => cart == null || cart!.lines.isEmpty;

  /// The badge's figure, from the same read the screen uses.
  Money? get subtotal => cart?.totals.subtotal;

  static CartView fromJson(Map<String, dynamic> data) {
    final int items = _int(data['item_count']) ?? 0;
    final int lines = _int(data['line_count']) ?? 0;

    return CartView(
      cart: Cart.fromJson(data['cart'], itemCount: items, lineCount: lines),
      itemCount: items,
      lineCount: lines,
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}
