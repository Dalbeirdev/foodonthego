import 'cart.dart';
import 'cart_revalidation.dart';
import 'pickup.dart';

/// What stands between this cart and a checkout.
///
/// Deliberately not an error code. A pre-checkout response is a success: the
/// request worked, and what it says is that the customer has something to do
/// first.
enum PreCheckoutIssueCode {
  cartEmpty('CART_EMPTY'),
  lineUnavailable('LINE_UNAVAILABLE'),
  priceIncreased('PRICE_INCREASED'),
  priceDecreased('PRICE_DECREASED'),
  restaurantNotAcceptingOrders('RESTAURANT_NOT_ACCEPTING_ORDERS'),
  restaurantUnavailable('RESTAURANT_UNAVAILABLE'),
  restaurantOffRoute('RESTAURANT_OFF_ROUTE'),
  routeStale('ROUTE_STALE'),
  noPickupTimeSelected('NO_PICKUP_TIME_SELECTED'),
  pickupTimeStale('PICKUP_TIME_STALE'),
  pickupTimeInvalid('PICKUP_TIME_INVALID'),
  noFeasiblePickupWindow('NO_FEASIBLE_PICKUP_WINDOW');

  const PreCheckoutIssueCode(this.wireValue);

  final String wireValue;

  static PreCheckoutIssueCode? fromWire(Object? value) {
    if (value is! String) return null;

    for (final PreCheckoutIssueCode code in PreCheckoutIssueCode.values) {
      if (code.wireValue == value) return code;
    }

    return null;
  }
}

/// One thing in the way.
class PreCheckoutIssue {
  const PreCheckoutIssue({
    required this.message,
    required this.blocking,
    this.code,
  });

  /// Null when this build has never heard of the code. The [message] is still
  /// shown and [blocking] still respected — both come from the server, so an
  /// old build handles a new issue correctly rather than ignoring it.
  final PreCheckoutIssueCode? code;

  final String message;

  /// The server's judgement, never derived from [code].
  final bool blocking;

  static PreCheckoutIssue? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? message = json['message'] as String?;

    if (message == null) return null;

    return PreCheckoutIssue(
      code: PreCheckoutIssueCode.fromWire(json['code']),
      message: message,
      blocking: json['blocking'] == true,
    );
  }
}

/// Whether this cart could be paid for, if there were anywhere to pay.
class PreCheckoutResult {
  const PreCheckoutResult({
    required this.cart,
    required this.plan,
    required this.readyForCheckout,
    required this.selectionStatus,
    this.revalidation = const CartRevalidation.unknown(),
    this.issues = const <PreCheckoutIssue>[],
  });

  final CartView cart;
  final PickupPlan plan;
  final CartRevalidation revalidation;

  /// **Read from the server, never computed.** A screen that worked this out
  /// from [issues] would be a second implementation of the rule, and the day
  /// the two disagree a customer reaches a payment for a kitchen that has shut.
  final bool readyForCheckout;

  final PickupSelectionStatus selectionStatus;

  final List<PreCheckoutIssue> issues;

  /// What is actually stopping them, in the order it needs dealing with.
  List<PreCheckoutIssue> get blockers => <PreCheckoutIssue>[
    for (final PreCheckoutIssue issue in issues)
      if (issue.blocking) issue,
  ];

  /// Worth telling them, but not in the way. A price that has fallen lives
  /// here: nobody needs a dialogue to be charged less.
  List<PreCheckoutIssue> get notices => <PreCheckoutIssue>[
    for (final PreCheckoutIssue issue in issues)
      if (!issue.blocking) issue,
  ];

  static PreCheckoutResult fromJson(Map<String, dynamic> data) =>
      PreCheckoutResult(
        cart: CartView.fromJson(data),
        plan: PickupPlan.fromJson(data['pickup']),
        revalidation:
            CartRevalidation.fromJson(data['revalidation']) ??
            const CartRevalidation.unknown(),
        readyForCheckout: data['ready_for_checkout'] == true,
        selectionStatus: PickupSelectionStatus.fromWire(
          data['selection_status'],
        ),
        issues: <PreCheckoutIssue>[
          for (final Object? raw
              in (data['issues'] as List<Object?>? ?? const <Object?>[]))
            if (PreCheckoutIssue.fromJson(raw) case final PreCheckoutIssue i) i,
        ],
      );
}
