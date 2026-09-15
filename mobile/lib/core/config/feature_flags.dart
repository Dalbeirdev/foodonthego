import 'app_environment.dart';

/// Feature flags for capability that is designed but not yet built.
///
/// Deliberately coarse. A flag per widget becomes a second configuration
/// language nobody can reason about; these are one per *significant capability*,
/// each owned by the module that will deliver it.
///
/// The rule they enforce: in production a feature that is off is **hidden**. In
/// development it is **visible but routed to a controlled placeholder** that says
/// which module will deliver it. That is what stops a customer ever tapping a
/// button that does nothing, while still letting the team navigate the shell.
class FeatureFlags {
  const FeatureFlags({
    required this.tripPlannerEnabled,
    required this.tripsEnabled,
    required this.ordersEnabled,
    required this.notificationsEnabled,
    required this.savedPlacesEnabled,
    required this.supportEnabled,
    required this.profileEditingEnabled,
  });

  /// Nothing is built yet, so every capability is off in every environment.
  /// A module turns its own flag on when it lands, and does so here.
  const FeatureFlags.defaults()
    : tripPlannerEnabled = false, // Module 05 — Trip Planner
      tripsEnabled = false, // Module 05
      ordersEnabled = false, // Module 08 — Order Lifecycle
      notificationsEnabled = false, // Module 10 — Notifications
      savedPlacesEnabled = false, // Module 04 — Saved Addresses
      supportEnabled = false, // Module 14 — Support
      profileEditingEnabled = false; // Module 03 — Authentication

  final bool tripPlannerEnabled;
  final bool tripsEnabled;
  final bool ordersEnabled;
  final bool notificationsEnabled;
  final bool savedPlacesEnabled;
  final bool supportEnabled;
  final bool profileEditingEnabled;

  /// Whether a disabled capability should still be reachable as a placeholder.
  bool get exposesUnbuiltFeatures =>
      AppEnvironment.current.showsDevelopmentNotices;

  FeatureFlags copyWith({
    bool? tripPlannerEnabled,
    bool? tripsEnabled,
    bool? ordersEnabled,
    bool? notificationsEnabled,
    bool? savedPlacesEnabled,
    bool? supportEnabled,
    bool? profileEditingEnabled,
  }) {
    return FeatureFlags(
      tripPlannerEnabled: tripPlannerEnabled ?? this.tripPlannerEnabled,
      tripsEnabled: tripsEnabled ?? this.tripsEnabled,
      ordersEnabled: ordersEnabled ?? this.ordersEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      savedPlacesEnabled: savedPlacesEnabled ?? this.savedPlacesEnabled,
      supportEnabled: supportEnabled ?? this.supportEnabled,
      profileEditingEnabled:
          profileEditingEnabled ?? this.profileEditingEnabled,
    );
  }
}
