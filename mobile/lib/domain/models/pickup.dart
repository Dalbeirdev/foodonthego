import 'cart.dart';

/// What has become of a customer's pickup choice.
///
/// The server derives this on every read rather than storing it, and the client
/// never derives it at all. A cart reading `SELECTED` while the restaurant has
/// since edited its hours is a question only the backend can answer, and a
/// screen that worked it out for itself would be one release away from
/// disagreeing about whether somebody may be charged.
enum PickupSelectionStatus {
  none('NONE'),
  selected('SELECTED'),
  stale('STALE'),
  invalid('INVALID');

  const PickupSelectionStatus(this.wireValue);

  final String wireValue;

  /// An unknown status is not read as "fine".
  ///
  /// A build that meets a status this version has never heard of knows the
  /// server is saying something it cannot interpret, and the safe reading of
  /// that is that nothing has been settled.
  static PickupSelectionStatus fromWire(Object? value) {
    if (value is String) {
      for (final PickupSelectionStatus status in PickupSelectionStatus.values) {
        if (status.wireValue == value) return status;
      }
    }

    return PickupSelectionStatus.none;
  }

  bool get isUsable => this == PickupSelectionStatus.selected;
}

/// One selectable interval, and the opaque id that names it.
///
/// **The id is the whole of what goes back to the server.** The times here are
/// for rendering; nothing in this class is ever sent, and there is no
/// constructor a client could use to invent a window of its own.
class PickupOption {
  const PickupOption({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.isRecommended,
    DateTime? localStartAt,
    DateTime? localEndAt,
  }) : localStartAt = localStartAt ?? startAt,
       localEndAt = localEndAt ?? endAt;

  /// Opaque, server-minted, and short-lived. Not parsed, not decomposed, not
  /// inspected — it carries no structure to read.
  final String id;

  /// The absolute instants, for comparing.
  final DateTime startAt;
  final DateTime endAt;

  /// The same moments as the counter's clock shows them, for reading.
  final DateTime localStartAt;
  final DateTime localEndAt;

  /// The server's recommendation, not the client's guess at one.
  final bool isRecommended;

  static PickupOption? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final DateTime? start = _time(json['start_at']);
    final DateTime? end = _time(json['end_at']);

    if (id == null || start == null || end == null) return null;

    return PickupOption(
      id: id,
      startAt: start,
      endAt: end,
      localStartAt: wallClockOf(json['start_at']),
      localEndAt: wallClockOf(json['end_at']),
      isRecommended: json['is_recommended'] == true,
    );
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// The clock face the server wrote, kept as written.
///
/// **`DateTime.parse` throws the offset away.** Given
/// `2026-09-07T13:40:00+05:30` it hands back the right instant flagged UTC, and
/// the only two things a client can then do with it are show it in UTC or
/// convert it to the phone's zone — so a Delhi pickup on a phone set to London
/// renders as 8:10 am. The time on the door is 1:40 pm.
///
/// Dart has no timezone database in core, and rather than take a dependency to
/// convert into a zone the server has already converted into, this reads the
/// wall-clock fields straight out of the string. The server decided the offset
/// — daylight saving included — and this keeps its answer.
///
/// The absolute instant is kept alongside, in [PickupOption.startAt], because
/// comparisons need it. One is for arithmetic and the other is for reading, and
/// conflating them is how an afternoon becomes a morning.
///
/// Top-level rather than private to one model: every instant the server sends
/// needs this treatment, and Module 14's quote expiry is the second caller. A
/// screen reaching for `.toLocal()` instead is the bug this exists to prevent.
DateTime? wallClockOf(Object? value) {
  if (value is! String) return null;

  final RegExpMatch? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(value);

  if (match == null) return null;

  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
}

/// What the customer has chosen, as the server currently reads it.
class PickupSelection {
  const PickupSelection({
    required this.status,
    this.startAt,
    this.endAt,
    this.timezone,
    this.selectedAt,
    DateTime? localStartAt,
    DateTime? localEndAt,
  }) : localStartAt = localStartAt ?? startAt,
       localEndAt = localEndAt ?? endAt;

  const PickupSelection.none() : this(status: PickupSelectionStatus.none);

  final PickupSelectionStatus status;

  /// The absolute instants, for comparing.
  final DateTime? startAt;
  final DateTime? endAt;

  /// The same moments on the counter's clock, for reading.
  final DateTime? localStartAt;
  final DateTime? localEndAt;

  /// The restaurant's IANA zone. A pickup happens at the counter, on the
  /// counter's clock, and this travels beside the instants rather than being
  /// baked into them.
  final String? timezone;

  final DateTime? selectedAt;

  bool get hasWindow => startAt != null && endAt != null;

  static PickupSelection fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const PickupSelection.none();

    return PickupSelection(
      status: PickupSelectionStatus.fromWire(json['status']),
      startAt: PickupOption._time(json['start_at']),
      endAt: PickupOption._time(json['end_at']),
      localStartAt: wallClockOf(json['start_at']),
      localEndAt: wallClockOf(json['end_at']),
      timezone: json['timezone'] as String?,
      selectedAt: PickupOption._time(json['selected_at']),
    );
  }
}

/// The whole of what the server worked out about collecting this cart.
///
/// Every figure here is rendered and none is computed. The three durations are
/// present so a screen can explain a time rather than assert one — a list of
/// times a customer has to take on trust loses them at the first one that looks
/// wrong.
class PickupPlan {
  const PickupPlan({
    required this.serverNow,
    required this.isFeasible,
    required this.requiresRouteRefresh,
    required this.selection,
    this.timezone,
    this.estimatedArrivalAt,
    this.localEstimatedArrivalAt,
    this.travelMinutes,
    this.routeCalculatedAt,
    this.routeIsFresh = false,
    this.preparationMinutes,
    this.bufferMinutes,
    this.minimumLeadMinutes,
    this.earliestReadyAt,
    this.localEarliestReadyAt,
    this.reason,
    this.recommendedOptionId,
    this.options = const <PickupOption>[],
  });

  /// A plan nobody has asked for yet. `isFeasible` is false, deliberately: a
  /// screen that has not asked must not imply an answer.
  const PickupPlan.unknown()
    : this(
        serverNow: null,
        isFeasible: false,
        requiresRouteRefresh: false,
        selection: const PickupSelection.none(),
      );

  /// Authoritative server time. The device clock is never used to decide
  /// whether a window is still open — only the server knows that, and it is
  /// asked again at selection and again at pre-checkout.
  final DateTime? serverNow;

  final bool isFeasible;

  /// The journey's estimate has aged out. The screen offers a refresh; the
  /// client does not silently trigger one, because a routing call is billed.
  final bool requiresRouteRefresh;

  final PickupSelection selection;

  final String? timezone;

  final DateTime? estimatedArrivalAt;

  /// Arrival on the counter's clock, for reading.
  final DateTime? localEstimatedArrivalAt;

  final int? travelMinutes;
  final DateTime? routeCalculatedAt;
  final bool routeIsFresh;

  final int? preparationMinutes;
  final int? bufferMinutes;
  final int? minimumLeadMinutes;
  final DateTime? earliestReadyAt;

  /// The same moment on the counter's clock, for reading.
  final DateTime? localEarliestReadyAt;

  /// Why no pickup can be offered, when none can. A stable code the screen
  /// branches on; the customer-facing wording is the screen's own.
  final String? reason;

  final String? recommendedOptionId;
  final List<PickupOption> options;

  PickupOption? get recommended {
    for (final PickupOption option in options) {
      if (option.isRecommended) return option;
    }

    return null;
  }

  PickupOption? optionById(String id) {
    for (final PickupOption option in options) {
      if (option.id == id) return option;
    }

    return null;
  }

  static PickupPlan fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const PickupPlan.unknown();

    final Map<String, dynamic> travel =
        (json['travel'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, dynamic> preparation =
        (json['preparation'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return PickupPlan(
      serverNow: PickupOption._time(json['server_now']),
      isFeasible: json['is_feasible'] == true,
      requiresRouteRefresh: json['requires_route_refresh'] == true,
      selection: PickupSelection.fromJson(json['selection']),
      timezone: json['timezone'] as String?,
      estimatedArrivalAt: PickupOption._time(travel['estimated_arrival_at']),
      localEstimatedArrivalAt: wallClockOf(travel['estimated_arrival_at']),
      travelMinutes: _int(travel['travel_minutes']),
      routeCalculatedAt: PickupOption._time(travel['calculated_at']),
      routeIsFresh: travel['is_fresh'] == true,
      preparationMinutes: _int(preparation['preparation_minutes']),
      bufferMinutes: _int(json['buffer_minutes']),
      minimumLeadMinutes: _int(json['minimum_lead_minutes']),
      earliestReadyAt: PickupOption._time(json['earliest_ready_at']),
      localEarliestReadyAt: wallClockOf(json['earliest_ready_at']),
      reason: json['reason'] as String?,
      recommendedOptionId: json['recommended_option_id'] as String?,
      options: <PickupOption>[
        for (final Object? raw
            in (json['options'] as List<Object?>? ?? const <Object?>[]))
          if (PickupOption.fromJson(raw) case final PickupOption o) o,
      ],
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// A cart and its pickup plan, from one request.
///
/// One request for both, because the pickup screen shows the order beside the
/// time and fetching them separately would render the two a moment apart —
/// which is how a customer sees a pickup time for an order they have already
/// changed.
class PickupView {
  const PickupView({required this.cart, required this.plan});

  final CartView cart;
  final PickupPlan plan;

  static PickupView fromJson(Map<String, dynamic> data) => PickupView(
    cart: CartView.fromJson(data),
    plan: PickupPlan.fromJson(data['pickup']),
  );
}
