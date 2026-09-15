import 'pickup.dart';
import 'order_timeline.dart';
import 'placed_order.dart';

/// An order, its story, and how fresh this copy of it is.
///
/// **The version is the point of this class.** A phone polling a tracking
/// endpoint can receive two answers out of order — a slow COOKING response
/// arriving after a fast READY one — and comparing status strings cannot tell
/// which is newer without the client knowing that COOKING precedes READY. It
/// must not know that: the lifecycle is the server's, and a client that
/// encodes it is a client that is wrong the moment the lifecycle changes.
///
/// A monotonically increasing integer answers "which of these two is fresher"
/// without answering "what comes next", which is exactly the amount the client
/// is allowed to know.
class TrackedOrder {
  const TrackedOrder({
    required this.order,
    required this.version,
    this.timeline = const <OrderTimelineStep>[],
    this.isActive = false,
    this.customerSafeReason,
    this.pickupCredentialAvailable = false,
    this.serverTime,
  });

  final PlacedOrder order;

  /// Increments on every status transition, server-side.
  final int version;

  final List<OrderTimelineStep> timeline;

  /// Whether anything can still happen to this order.
  ///
  /// Decided by the server from its own transition table, so this app stops
  /// refreshing a finished order without keeping its own list of which states
  /// are terminal — a list that would go stale silently.
  final bool isActive;

  /// The only explanation a customer may be shown for a rejection or
  /// cancellation, and usually null. Null is not a gap: most exceptions have
  /// nothing safe to add beyond the status itself.
  final String? customerSafeReason;

  /// Whether a pickup code exists to be fetched — **not the code**.
  ///
  /// The credential lives behind its own request. Tracking is polled, and a
  /// credential that rode along would travel every few seconds through every
  /// proxy between here and the server.
  final bool pickupCredentialAvailable;

  /// The server's clock when it answered.
  ///
  /// Freshness is measured against this rather than against the device, whose
  /// clock may be wrong by hours — and "updated 4 minutes ago" computed from a
  /// wrong clock is worse than saying nothing.
  final DateTime? serverTime;

  PlacedOrderStatus get status => order.status;

  /// Whether [other] is a newer answer about the same order than this one.
  ///
  /// Used to drop a response that overtook a fresher one. Strictly greater:
  /// an equal version carries the same status, so replacing state with it
  /// would rebuild the screen for nothing.
  bool supersededBy(TrackedOrder other) =>
      other.order.id == order.id && other.version > version;

  static TrackedOrder? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final PlacedOrder? order = PlacedOrder.fromJson(json);

    if (order == null) return null;

    final Object? version = json['order_version'];

    return TrackedOrder(
      order: order,

      /*
       * A missing version reads as 0, not as 1.
       *
       * Every real response carries at least 1, so 0 can only mean "this
       * server did not send one" -- and a stored 0 is superseded by any
       * genuine answer, which is the behaviour that keeps a client talking to
       * an older backend from pinning itself to a stale state.
       */
      version: version is int ? version : 0,

      timeline: <OrderTimelineStep>[
        for (final Object? entry
            in (json['timeline'] as List<Object?>? ?? const <Object?>[]))
          if (OrderTimelineStep.fromJson(entry) case final OrderTimelineStep s)
            s,
      ],

      isActive: json['is_active'] as bool? ?? false,
      customerSafeReason: json['customer_safe_reason'] as String?,

      pickupCredentialAvailable:
          (json['pickup_credential'] as Map<String, dynamic>?)?['available']
              as bool? ??
          false,

      serverTime: wallClockOf(json['server_time']),
    );
  }
}
