import '../../core/config/app_environment.dart';
import '../../domain/models/active_order_summary.dart';
import '../../domain/models/customer_summary.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/models/placed_order.dart';

/// The three development personas the module specification calls for.
///
/// This file is the ONLY place demo content exists. It is reachable solely
/// through [FixtureHomeRepository], which is itself only constructed when
/// `AppEnvironment.current.allowsFixtures` — a compile-time constant — so a
/// production build tree-shakes the whole graph away rather than merely not
/// calling it.
enum DevelopmentPersona {
  /// Persona A — a new customer: no journey, no order.
  newCustomer,

  /// Persona B — a journey under way, nothing ordered.
  activeJourney,

  /// Persona C — a journey under way and food being cooked.
  activeOrder,

  /// The stress case: the longest realistic name, restaurant and route.
  longContent;

  String get label => switch (this) {
    DevelopmentPersona.newCustomer => 'New customer',
    DevelopmentPersona.activeJourney => 'Active journey',
    DevelopmentPersona.activeOrder => 'Active order',
    DevelopmentPersona.longContent => 'Long content',
  };
}

class DevelopmentFixtures {
  const DevelopmentFixtures._();

  static HomeDashboard dashboardFor(
    DevelopmentPersona persona, {
    DateTime? now,
  }) {
    assert(
      AppEnvironment.current.allowsFixtures,
      'Development fixtures were requested in a build that forbids them.',
    );

    final DateTime reference = now ?? DateTime.now();

    return switch (persona) {
      DevelopmentPersona.newCustomer => const HomeDashboard(
        customer: CustomerSummary(fullName: 'Rahul Sharma'),
      ),
      DevelopmentPersona.activeJourney => HomeDashboard(
        customer: const CustomerSummary(fullName: 'Rahul Sharma'),
        unreadNotificationCount: 1,
      ),
      DevelopmentPersona.activeOrder => HomeDashboard(
        customer: const CustomerSummary(fullName: 'Rahul Sharma'),
        activeOrder: ActiveOrderSummary(
          reference: 'FOTG-1024',
          restaurantName: 'Highway Spice Kitchen',
          status: PlacedOrderStatus.cooking,
          itemCount: 3,
          estimatedPickup: reference.add(const Duration(minutes: 35)),
          totalMinorUnits: 74000,
        ),
        unreadNotificationCount: 2,
      ),
      DevelopmentPersona.longContent => HomeDashboard(
        customer: const CustomerSummary(fullName: 'Rahul Krishnamurthy Sharma'),
        activeOrder: ActiveOrderSummary(
          reference: 'FOTG-100482',
          restaurantName:
              'Shree Rajasthan Highway Family Restaurant & Food Court',
          status: PlacedOrderStatus.ready,
          itemCount: 12,
          estimatedPickup: reference.add(const Duration(minutes: 8)),
          totalMinorUnits: 312500,
        ),
        unreadNotificationCount: 14,
      ),
    };
  }
}
