import '../../core/config/app_environment.dart';
import '../../domain/models/active_order_summary.dart';
import '../../domain/models/active_trip_summary.dart';
import '../../domain/models/customer_summary.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/models/order_status.dart';

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
        activeTrip: const ActiveTripSummary(
          id: 'trip-dev-1',
          originLabel: 'Delhi',
          destinationLabel: 'Jaipur',
          status: TripStatus.onTheRoad,
          estimatedDuration: Duration(hours: 4, minutes: 35),
          remainingDuration: Duration(hours: 2, minutes: 50),
          totalDistanceKm: 281,
          progress: 0.38,
        ),
        unreadNotificationCount: 1,
      ),
      DevelopmentPersona.activeOrder => HomeDashboard(
        customer: const CustomerSummary(fullName: 'Rahul Sharma'),
        activeTrip: const ActiveTripSummary(
          id: 'trip-dev-1',
          originLabel: 'Delhi',
          destinationLabel: 'Jaipur',
          status: TripStatus.onTheRoad,
          estimatedDuration: Duration(hours: 4, minutes: 35),
          remainingDuration: Duration(hours: 1, minutes: 5),
          totalDistanceKm: 281,
          progress: 0.72,
          nextPickupLabel: 'Highway Spice Kitchen',
        ),
        activeOrder: ActiveOrderSummary(
          reference: 'FOTG-1024',
          restaurantName: 'Highway Spice Kitchen',
          status: OrderStatus.cooking,
          itemCount: 3,
          estimatedPickup: reference.add(const Duration(minutes: 35)),
          totalMinorUnits: 74000,
        ),
        unreadNotificationCount: 2,
      ),
      DevelopmentPersona.longContent => HomeDashboard(
        customer: const CustomerSummary(fullName: 'Rahul Krishnamurthy Sharma'),
        activeTrip: const ActiveTripSummary(
          id: 'trip-dev-2',
          originLabel: 'Indira Gandhi International Airport, New Delhi',
          destinationLabel: 'Jaipur International Airport, Rajasthan',
          status: TripStatus.onTheRoad,
          estimatedDuration: Duration(hours: 5, minutes: 20),
          remainingDuration: Duration(hours: 3, minutes: 15),
          totalDistanceKm: 304.6,
          progress: 0.41,
          nextPickupLabel:
              'Shree Rajasthan Highway Family Restaurant & Food Court',
        ),
        activeOrder: ActiveOrderSummary(
          reference: 'FOTG-100482',
          restaurantName:
              'Shree Rajasthan Highway Family Restaurant & Food Court',
          status: OrderStatus.ready,
          itemCount: 12,
          estimatedPickup: reference.add(const Duration(minutes: 8)),
          totalMinorUnits: 312500,
        ),
        unreadNotificationCount: 14,
      ),
    };
  }
}
