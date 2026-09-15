import 'package:flutter/foundation.dart';

/// The analytics boundary.
///
/// Module 02 defines *where* events are raised and what they are called; it
/// deliberately ships no third-party SDK. Choosing a vendor now would embed a
/// tracking library — and its network calls — in an app that has no privacy
/// policy or consent flow yet.
///
/// **Naming convention:** `object_verb`, lower snake case, past tense for things
/// that happened (`home_viewed`) and imperative for intent (`plan_journey_tapped`).
///
/// **What may never be in a payload:** a name, an email, a phone number, a
/// precise location, an address, a payment detail or an order's contents. Events
/// carry what was interacted with, never who the person is.
abstract interface class Analytics {
  void log(String event, {Map<String, Object?> properties});
}

/// Names declared centrally so a typo cannot silently create a second funnel.
class AnalyticsEvents {
  const AnalyticsEvents._();

  static const String homeViewed = 'home_viewed';
  static const String planJourneyTapped = 'plan_journey_tapped';
  static const String journeyCardTapped = 'journey_card_tapped';
  static const String orderCardTapped = 'order_card_tapped';
  static const String quickActionTapped = 'quick_action_tapped';
  static const String tripsTabOpened = 'trips_tab_opened';
  static const String ordersTabOpened = 'orders_tab_opened';
  static const String notificationsTabOpened = 'notifications_tab_opened';
  static const String profileTabOpened = 'profile_tab_opened';
  static const String homeRefreshed = 'home_refreshed';
  static const String unbuiltFeatureOpened = 'unbuilt_feature_opened';
}

/// Prints in debug, discards in release. Replaced when a vendor is chosen.
class DebugAnalytics implements Analytics {
  const DebugAnalytics();

  @override
  void log(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) {
    if (kDebugMode) {
      debugPrint('[analytics] $event ${properties.isEmpty ? '' : properties}');
    }
  }
}

/// Does nothing. The default until a vendor and a consent flow exist.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  void log(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) {}
}
