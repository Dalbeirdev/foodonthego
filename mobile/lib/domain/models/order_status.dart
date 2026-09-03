/// The lifecycle of a FoodOnTheGo order.
///
/// Declared now, in the domain layer, because three later modules need to agree
/// on it — the customer app, the restaurant dashboard and the order API. Module
/// 02 renders these states; Module 08 makes them move.
enum OrderStatus {
  placed,
  accepted,
  cooking,
  ready,
  pickedUp,
  cancelled;

  /// The customer-facing label. The internal name is not always the useful one.
  String get label => switch (this) {
    OrderStatus.placed => 'Placed',
    OrderStatus.accepted => 'Accepted',
    OrderStatus.cooking => 'Cooking',
    OrderStatus.ready => 'Ready for pickup',
    OrderStatus.pickedUp => 'Picked up',
    OrderStatus.cancelled => 'Cancelled',
  };

  /// A short sentence explaining what is happening, for the card body.
  String get explanation => switch (this) {
    OrderStatus.placed => 'Waiting for the kitchen to accept',
    OrderStatus.accepted => 'The kitchen has your order',
    OrderStatus.cooking => 'Being cooked to reach you on time',
    OrderStatus.ready => 'Waiting for you at the counter',
    OrderStatus.pickedUp => 'Collected — safe travels',
    OrderStatus.cancelled => 'This order was cancelled',
  };

  /// Position on the progress track. `cancelled` is not a step: it ends the track.
  static const List<OrderStatus> progression = <OrderStatus>[
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.cooking,
    OrderStatus.ready,
    OrderStatus.pickedUp,
  ];

  bool get isTerminal =>
      this == OrderStatus.pickedUp || this == OrderStatus.cancelled;

  bool get isActive => !isTerminal;

  int get stepIndex => progression.indexOf(this);
}
