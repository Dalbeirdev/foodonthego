import 'cart.dart';
import 'money.dart';

/// What revalidation found wrong with a cart line.
///
/// Deliberately not an [ApiErrorCode]. A revalidation response is a success:
/// the request worked, and what it says is that the world moved. Treating these
/// as errors is how a price change ends up on an error screen instead of in
/// front of the customer who needs to decide about it.
enum CartFinding {
  priceIncreased('PRICE_INCREASED'),
  priceDecreased('PRICE_DECREASED'),
  itemUnavailable('ITEM_UNAVAILABLE'),
  variantUnavailable('VARIANT_UNAVAILABLE'),
  modifierUnavailable('MODIFIER_UNAVAILABLE');

  const CartFinding(this.wireValue);

  final String wireValue;

  /// Unknown findings are not silently dropped.
  ///
  /// A code this build has never heard of means the server knows something
  /// about this line that the client does not, and the safe reading of that is
  /// not "carry on". [CartLineVerdict.blocksOrdering] comes from the server's
  /// own flag for exactly this reason, so a new finding blocks correctly on an
  /// old build.
  static CartFinding? fromWire(Object? value) {
    if (value is! String) return null;

    for (final CartFinding finding in CartFinding.values) {
      if (finding.wireValue == value) return finding;
    }

    return null;
  }

  bool get isPriceChange =>
      this == CartFinding.priceIncreased || this == CartFinding.priceDecreased;
}

/// What revalidation found on one line.
class CartLineVerdict {
  const CartLineVerdict({
    required this.cartItemId,
    required this.name,
    required this.quantity,
    required this.blocksOrdering,
    this.variantName,
    this.finding,
    this.message,
    this.sourceCode,
    this.priceWhenAdded,
    this.priceNow,
  });

  final String cartItemId;
  final String name;
  final String? variantName;
  final int quantity;

  final CartFinding? finding;

  /// The server's own judgement, not derived from [finding].
  ///
  /// A build that meets a finding it does not recognise still knows whether the
  /// customer may proceed, because the server said so in a field this class
  /// reads directly.
  final bool blocksOrdering;

  /// The server's words, safe to show. The client branches on the code.
  final String? message;

  /// The refusal the pricing path gave, where the finding is a coarse bucket.
  final String? sourceCode;

  final Money? priceWhenAdded;

  /// Null when the line cannot be priced at all. Not zero — a dish that cannot
  /// be bought does not cost nothing.
  final Money? priceNow;

  bool get isSettled => finding == null;

  static CartLineVerdict? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['cart_item_id'] as String?;

    if (id == null) return null;

    return CartLineVerdict(
      cartItemId: id,
      name: (json['name'] as String?) ?? '',
      variantName: json['variant_name'] as String?,
      quantity: _int(json['quantity']) ?? 1,
      finding: CartFinding.fromWire(json['finding']),
      blocksOrdering: json['blocks_ordering'] == true,
      message: json['message'] as String?,
      sourceCode: json['source_code'] as String?,
      priceWhenAdded: Money.fromJson(json['price_when_added']),
      priceNow: Money.fromJson(json['price_now']),
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// Whether a cart still means what it said.
class CartRevalidation {
  const CartRevalidation({
    required this.canProceed,
    required this.unchanged,
    required this.restaurantAcceptingOrders,
    this.lines = const <CartLineVerdict>[],
    this.totalsIfAccepted,
  });

  /// A cart that has not been checked. Not "everything is fine": [canProceed]
  /// is false, because a screen that has not asked must not imply an answer.
  const CartRevalidation.unknown()
    : this(
        canProceed: false,
        unchanged: false,
        restaurantAcceptingOrders: false,
      );

  final bool canProceed;

  /// Nothing moved at all, price changes included.
  final bool unchanged;

  final bool restaurantAcceptingOrders;

  final List<CartLineVerdict> lines;

  /// What the cart would cost if the customer accepted every price change.
  ///
  /// Null the moment a line cannot be priced: a total worked out around a
  /// missing dish describes a cart nobody has.
  final CartTotals? totalsIfAccepted;

  /// The findings worth putting in front of the customer, in the order they
  /// need dealing with: what blocks them first, then what merely changed.
  List<CartLineVerdict> get problems => <CartLineVerdict>[
    for (final CartLineVerdict line in lines)
      if (line.blocksOrdering) line,
    for (final CartLineVerdict line in lines)
      if (!line.blocksOrdering && !line.isSettled) line,
  ];

  bool get hasBlockingProblem =>
      lines.any((CartLineVerdict line) => line.blocksOrdering);

  CartLineVerdict? verdictFor(String cartItemId) {
    for (final CartLineVerdict line in lines) {
      if (line.cartItemId == cartItemId) return line;
    }

    return null;
  }

  static CartRevalidation? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    return CartRevalidation(
      canProceed: json['can_proceed'] == true,
      unchanged: json['unchanged'] == true,
      restaurantAcceptingOrders: json['restaurant_accepting_orders'] == true,
      lines: <CartLineVerdict>[
        for (final Object? raw
            in (json['lines'] as List<Object?>? ?? const <Object?>[]))
          if (CartLineVerdict.fromJson(raw) case final CartLineVerdict v) v,
      ],
      totalsIfAccepted: CartTotals.fromJson(json['totals_if_accepted']),
    );
  }
}

/// A cart, and the answer to whether it still holds.
class RevalidatedCart {
  const RevalidatedCart({required this.view, required this.revalidation});

  final CartView view;
  final CartRevalidation revalidation;

  static RevalidatedCart fromJson(Map<String, dynamic> data) => RevalidatedCart(
    view: CartView.fromJson(data),
    revalidation:
        CartRevalidation.fromJson(data['revalidation']) ??
        const CartRevalidation.unknown(),
  );
}
