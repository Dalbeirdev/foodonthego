import 'active_order_summary.dart';
import 'active_trip_summary.dart';
import 'customer_summary.dart';

/// Everything the home screen renders, in one value.
///
/// One model rather than three independent futures, because the home screen has
/// exactly one loading state and one error state — three would let it show a
/// skeleton next to a populated card next to an error, which reads as broken.
class HomeDashboard {
  const HomeDashboard({
    required this.customer,
    this.activeTrip,
    this.activeOrder,
    this.unreadNotificationCount = 0,
  });

  final CustomerSummary customer;

  /// Null when there is no journey. The home screen must then render nothing at
  /// all for journeys — an empty "Current Journey" container is worse than no
  /// container.
  final ActiveTripSummary? activeTrip;

  final ActiveOrderSummary? activeOrder;
  final int unreadNotificationCount;

  bool get hasActiveTrip => activeTrip != null;
  bool get hasActiveOrder => activeOrder != null;

  /// A customer with neither gets the onboarding-shaped home: a large journey
  /// call to action and an explanation of what the product does.
  bool get isNewJourney => !hasActiveTrip && !hasActiveOrder;
}
