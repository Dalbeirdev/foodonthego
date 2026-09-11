import 'placed_order.dart';

/// An order in progress, as the home screen needs it.
class ActiveOrderSummary {
  const ActiveOrderSummary({
    required this.reference,
    required this.restaurantName,
    required this.status,
    this.itemCount,
    this.estimatedPickup,
    this.totalMinorUnits,
    this.currencyCode = 'INR',
  });

  /// The short human-quotable code, e.g. FOTG-1024.
  final String reference;
  final String restaurantName;
  final PlacedOrderStatus status;
  final int? itemCount;

  /// When the food should be ready. Module 08 computes it; this only displays it.
  final DateTime? estimatedPickup;

  /// Money is an integer of minor units — paise for INR — never a double.
  /// The currency travels with the amount so no widget has to assume one.
  final int? totalMinorUnits;
  final String currencyCode;
}
