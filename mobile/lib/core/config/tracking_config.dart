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

  /// How old a cached status may be and still be shown *as the status*.
  ///
  /// KI-031: the screen used to show a cached order behind a banner saying it
  /// "may have changed", and half an hour old looked exactly like two days old.
  /// A customer glancing at "Your food is being prepared" does not read the
  /// banner first; they read the four words that answer their question, and
  /// those four words can be a day out of date.
  ///
  /// The bound is [pollingBudget] rather than a new number, and deliberately
  /// so: that is how long this app is willing to keep a status fresh. Past it
  /// the app has already stopped maintaining the read, so a status older than
  /// that is one the app has given up on. Vouching for it afterwards would be
  /// claiming something it decided not to check.
  ///
  /// Past this the screen says it cannot tell you where the order is, and says
  /// when it last knew. What does *not* expire stays on screen — the order
  /// number, the restaurant, the items, the amount paid, the pickup window the
  /// customer asked for. None of those change while nobody is looking.
  static const Duration vouchedFor = pollingBudget;
}
