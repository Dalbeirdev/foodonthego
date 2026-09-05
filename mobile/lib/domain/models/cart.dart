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
