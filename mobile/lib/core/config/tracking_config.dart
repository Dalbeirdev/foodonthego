/// How often the tracking screen asks the server what changed.
///
/// **THIS IS NOT REALTIME, AND IS NOT LABELLED AS SUCH ANYWHERE.** Module 19
/// adds a realtime subscription; until it exists, an open tracking screen polls
/// on a timer. The screen says "Updated just now" rather than "Live", because a
/// LIVE badge over a 20-second poll is a claim the app cannot support and the
/// customer has no way to check.
///
/// The interval is a compile-time define rather than a literal so that a build
/// for a demo, a slow network or a load test can change it without a code edit
/// — and so that the number is somewhere a reader can find it.
class TrackingConfig {
  const TrackingConfig._();

  static const int _rawSeconds = int.fromEnvironment(
    'FOTG_ORDER_TRACKING_REFRESH_SECONDS',
    defaultValue: 20,
  );

  /// Twenty seconds, chosen rather than defaulted.
  ///
  /// A restaurant accepting an order is not a sub-second event; the customer is
  /// usually driving, and the cost of learning about ACCEPTED twenty seconds
  /// late is nil. The cost of learning about it one second late is a request
  /// every second from every open tracking screen, which is a load pattern
  /// nobody would choose deliberately.
  ///
  /// Clamped so a mistyped define cannot produce a request storm: anything
  /// under five seconds is treated as five.
  static Duration get refreshInterval =>
      Duration(seconds: _rawSeconds < 5 ? 5 : _rawSeconds);

  /// How long an unattended tracking screen keeps polling.
  ///
  /// A screen left open on a bedside table overnight should not spend the
  /// night talking to the server. After this it stops and offers a manual
  /// refresh; nothing is lost, because the next foreground brings a fresh read.
  static const Duration pollingBudget = Duration(minutes: 30);
}
