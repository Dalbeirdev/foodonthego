import 'active_order_summary.dart';
import 'customer_summary.dart';

/// The dashboard part of the home screen, in one value.
///
/// One model rather than several independent futures, because this part of the
/// screen has exactly one loading state and one error state — several would let
/// it show a skeleton next to a populated card next to an error, which reads as
/// broken.
///
/// Journeys are deliberately **not** here. From Module 05 they are real data
/// from `/customer/trips/next`, with their own provider and their own failure —
/// and holding a second, fixture-shaped representation of a journey alongside
/// the real one is how two parts of a screen come to disagree about whether
/// somebody is travelling.
class HomeDashboard {
  const HomeDashboard({
    required this.customer,
    this.activeOrder,
    this.unreadNotificationCount = 0,
  });

  final CustomerSummary customer;

  final ActiveOrderSummary? activeOrder;
  final int unreadNotificationCount;

  bool get hasActiveOrder => activeOrder != null;
}
