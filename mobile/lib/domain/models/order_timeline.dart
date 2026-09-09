import 'pickup.dart';
import 'placed_order.dart';

/// Where one step of the timeline stands, **as the server decided it**.
///
/// The client does not work this out. A build that reasoned "COOKING is
/// current, so ACCEPTED must be done" would be re-implementing the lifecycle in
/// Dart, and would be wrong the first time the lifecycle changed without an app
/// release — which is precisely the release this app cannot force a customer to
/// install before their next order.
enum OrderTimelineStepState {
  completed('COMPLETED'),
  current('CURRENT'),
  upcoming('UPCOMING'),

  /// The order ended here instead of continuing.
  ///
  /// Rendered differently from [completed] on purpose: a tick beside "your
  /// order was refused" reads as an achievement.
  exception('EXCEPTION');

  const OrderTimelineStepState(this.wireValue);

  final String wireValue;

  /// An unrecognised state reads as [upcoming].
  ///
  /// Of the four, upcoming is the only one that claims nothing: it shows no
  /// timestamp, no tick and no emphasis. A default of `completed` would put a
  /// tick against a step the server never said had happened.
  static OrderTimelineStepState fromWire(Object? value) {
    if (value is String) {
      for (final OrderTimelineStepState state
          in OrderTimelineStepState.values) {
        if (state.wireValue == value) return state;
      }
    }

    return OrderTimelineStepState.upcoming;
  }
}

/// One entry in the order's story.
class OrderTimelineStep {
  const OrderTimelineStep({
    required this.status,
    required this.state,
    required this.title,
    this.occurredAt,
    this.note,
  });

  final PlacedOrderStatus status;
  final OrderTimelineStepState state;

  /// The server's wording, not the app's.
  ///
  /// Sent with every step so a state this build has never heard of still
  /// renders a sentence rather than a raw enum value.
  final String title;

  /// When it happened, or null because it has not.
  ///
  /// **Never substituted for.** A step with a made-up time is the one error a
  /// customer cannot detect: it tells them their food was ready at an hour it
  /// was not, and nothing on the screen contradicts it.
  final DateTime? occurredAt;

  /// The only free text the server may put here, and only when somebody wrote
  /// it deliberately for a customer.
  final String? note;

  bool get isCompleted => state == OrderTimelineStepState.completed;

  bool get isCurrent => state == OrderTimelineStepState.current;

  bool get isException => state == OrderTimelineStepState.exception;

  static OrderTimelineStep? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? title = json['title'] as String?;

    if (title == null) return null;

    return OrderTimelineStep(
      status: PlacedOrderStatus.fromWire(json['status']),
      state: OrderTimelineStepState.fromWire(json['state']),
      title: title,
      occurredAt: wallClockOf(json['occurred_at']),
      note: json['note'] as String?,
    );
  }
}
