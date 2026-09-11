import 'placed_order.dart';

/// The server's answer to "where is my order?".
///
/// **There is no failure case, and that is the design.** After a capture no
/// honest answer tells the customer their payment did not work — the money has
/// left their account. A variant for it would eventually get used, and the
/// screen behind it would offer a Pay button to somebody who has already paid.
enum OrderCreationState {
  placed('PLACED'),

  /// Money captured, order still being written.
  creating('ORDER_CREATION_PENDING'),

  /// Money captured, and a first attempt to write the order already failed.
  ///
  /// Distinct from [creating] so support can tell a slow path from a broken
  /// one. Identical from the customer's side: same message, same absence of a
  /// Pay button.
  recovering('ORDER_RECOVERY_REQUIRED'),

  awaitingPayment('AWAITING_PAYMENT');

  const OrderCreationState(this.wireValue);

  final String wireValue;

  /// An unrecognised state is treated as "still working", never as unpaid.
  ///
  /// The asymmetry is deliberate. Reading an unknown state as awaiting payment
  /// would show a Pay button to a customer whose money may already be gone;
  /// reading it as in-progress shows a wait. One of those mistakes is
  /// recoverable.
  static OrderCreationState fromWire(Object? value) {
    if (value is String) {
      for (final OrderCreationState state in OrderCreationState.values) {
        if (state.wireValue == value) return state;
      }
    }

    return OrderCreationState.creating;
  }
}

/// A state, whether the money is already gone, and the order as it stands.
class OrderStatusReport {
  const OrderStatusReport({
    required this.state,
    required this.isPaidFor,
    required this.order,
    this.message,
  });

  final OrderCreationState state;

  /// Whether the customer's money has already left their account.
  ///
  /// Read from the server rather than inferred from [state]. Inferring it means
  /// every client re-implements the rule, and one of them eventually gets it
  /// wrong in the direction that charges somebody twice.
  final bool isPaidFor;

  final PlacedOrder? order;

  /// The server's customer-facing wording, when it has one.
  final String? message;

  /// Whether offering a way to pay is honest.
  bool get mayOfferPayment => !isPaidFor;

  static OrderStatusReport? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;

    final OrderCreationState state = OrderCreationState.fromWire(
      value['state'],
    );

    return OrderStatusReport(
      state: state,
      // Absent is read as paid-for, for the same reason an unknown state is:
      // the safe default is the one that does not invite a second payment.
      isPaidFor: value['is_paid_for'] is bool
          ? value['is_paid_for'] as bool
          : state != OrderCreationState.awaitingPayment,
      order: PlacedOrder.fromJson(value['order']),
      message: value['message'] as String?,
    );
  }
}
