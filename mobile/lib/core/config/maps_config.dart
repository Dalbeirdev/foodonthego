import 'package:flutter/foundation.dart';

/// Whether this build can draw a map, and with what.
///
/// The Maps SDK key is a **different key from the routing one**, and the
/// difference is the whole of this module's key security. This one ships inside
/// the app, so it is restricted by Android package plus signing certificate and
/// by iOS bundle id, and it is restricted to the Maps SDKs — it cannot calculate
/// a route, cannot search a place, and is worth nothing to anybody who extracts
/// it. The routing key never leaves the backend.
///
/// Supplied at build time (`--dart-define=FOTG_MAPS_API_KEY=…`) so it is not a
/// literal in the repository, and read here rather than in a widget so there is
/// one place that knows whether a map is possible.
class MapsConfig {
  const MapsConfig._();

  /// Empty in any build that was not given one — including every automated test
  /// and this project's web harness.
  static const String apiKey = String.fromEnvironment('FOTG_MAPS_API_KEY');

  static bool get hasKey => apiKey.isNotEmpty;

  /// The platforms this product ships to.
  ///
  /// Android and iOS. The web build exists only as a verification harness and
  /// deliberately does not carry a Maps key: putting one in a page served from
  /// a static directory would publish it.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Whether to attempt a map at all.
  ///
  /// When false the route screen shows its map-unavailable state — which is a
  /// required state in its own right, not a fallback bolted on: a customer whose
  /// map tiles will not load must still see where they are going, how far it is
  /// and how long it takes.
  static bool get canRenderMap => hasKey && isSupportedPlatform;
}
