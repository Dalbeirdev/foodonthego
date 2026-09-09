import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/tracking_config.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/tracked_order.dart';
import 'providers.dart';

/// Where the tracking screen is, as one value rather than five booleans.
///
/// A screen driven by `isLoading && !hasError && data != null` grows a state
/// nobody designed the first time two of those are true at once. This enum has
/// one member per thing the screen can actually be showing.
enum OrderTrackingPhase {
  /// Nothing known yet. The only state with no order to render.
  loading,

  /// An order, fetched from the server, current as of [OrderTrackingState.fetchedAt].
  loaded,

  /// An order, and a refresh in flight over the top of it.
  ///
  /// Distinct from [loading] because the screen keeps showing what it has: a
  /// spinner replacing a perfectly good order every twenty seconds would make
  /// the screen unusable.
  refreshing,

  /// An order this app already had, and no way to check it right now.
  ///
  /// **Never rendered as current.** The screen says when it was last read and
  /// that it may have changed since.
  offline,

  /// The request failed and there is nothing cached to fall back on.
  error,

  /// Not this customer's order, or the session has gone.
  unauthorized,

  /// No such order for this customer.
  ///
  /// The server answers 404 for an order belonging to somebody else and for one
  /// that does not exist, and this app does not try to tell them apart — the
  /// whole point of that response is that they are indistinguishable.
  notFound,
}

/// What the tracking screen is showing.
@immutable
class OrderTrackingState {
  const OrderTrackingState({
    this.phase = OrderTrackingPhase.loading,
    this.tracked,
    this.fetchedAt,
    this.pollingStopped = false,
  });

  final OrderTrackingPhase phase;

  /// The last order this app successfully read. Survives an offline phase,
  /// because a stale order clearly labelled stale is more use than nothing.
  final TrackedOrder? tracked;

  /// When [tracked] was read, by the device's clock.
  ///
  /// Used only for "how long ago", never for deciding what is true. The
  /// server's own clock arrives in the response for that.
  final DateTime? fetchedAt;

  /// Whether the timer has stopped and only a manual refresh remains.
  final bool pollingStopped;

  bool get hasOrder => tracked != null;

  OrderTrackingState copyWith({
    OrderTrackingPhase? phase,
    TrackedOrder? tracked,
    DateTime? fetchedAt,
    bool? pollingStopped,
  }) => OrderTrackingState(
    phase: phase ?? this.phase,
    tracked: tracked ?? this.tracked,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    pollingStopped: pollingStopped ?? this.pollingStopped,
  );
}

/// Fetches an order's tracking state, and decides when to ask again.
///
/// **TEMPORARY TRACKING REFRESH, not realtime.** Module 19 replaces the timer
/// below with a subscription. Until then this polls, and every name in here
/// says so, because the fastest way to end up with two realtime systems is to
/// call the first one realtime.
///
/// The rules the timer follows, and why:
///
///   - It stops for a terminal order. The server says whether an order is still
///     active; this class does not keep its own list of terminal states, which
///     would go stale silently the first time one was added.
///   - It stops when the app is backgrounded and takes one fresh read on
///     resume. A backgrounded app polling on a timer is a battery complaint.
///   - It backs off on failure rather than hammering a server that is already
///     unhappy.
///   - It gives up after a budget, so a screen left open overnight stops.
class OrderTrackingController extends Notifier<OrderTrackingState>
    with WidgetsBindingObserver {
  OrderTrackingController(this.orderId);

  final String orderId;

  Timer? _timer;
  DateTime? _startedAt;
  int _consecutiveFailures = 0;

  /// Guards against a slow response overwriting a fast one.
  ///
  /// Incremented per request. A response whose sequence is not the latest is
  /// discarded before it can touch state — the version check below handles the
  /// server's ordering, and this handles ours.
  int _sequence = 0;

  bool _disposed = false;

  @override
  OrderTrackingState build() {
    WidgetsBinding.instance.addObserver(this);

    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });

    scheduleMicrotask(load);

    return const OrderTrackingState();
  }

  /*
   * `lifecycle`, not `state`, and the lint is suppressed deliberately.
   *
   * WidgetsBindingObserver names this parameter `state`, which inside a
   * Notifier would shadow the notifier's own `state` -- so an assignment meant
   * for the screen's state would silently write to a local. Naming it for what
   * it is costs one ignore and removes a trap.
   */
  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (_disposed) return;

    switch (lifecycle) {
      case AppLifecycleState.resumed:
        // One read on the way back, then the timer resumes. A customer
        // returning to the app wants the current answer, not the one from
        // before they locked the phone.
        unawaited(refresh());
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
    }
  }

  /// The first read. Shows a skeleton, because there is nothing to show yet.
  Future<void> load() => _fetch(showBusy: false);

  /// A read over the top of what is already on screen.
  Future<void> refresh() => _fetch(showBusy: true);

  Future<void> _fetch({required bool showBusy}) async {
    if (_disposed) return;

    _startedAt ??= DateTime.now();

    if (showBusy && state.hasOrder) {
      state = state.copyWith(phase: OrderTrackingPhase.refreshing);
    }

    final int sequence = ++_sequence;

    try {
      final TrackedOrder tracked = await ref
          .read(orderRepositoryProvider)
          .tracking(orderId);

      if (_disposed || sequence != _sequence) {
        // A newer request has already been issued. Whatever this one says is
        // about an older moment, and adopting it would move the screen
        // backwards.
        return;
      }

      _consecutiveFailures = 0;

      /*
       * The server's own ordering, checked second.
       *
       * The sequence check above catches a response we know is stale. This
       * catches one we do not: two requests issued in order can still be
       * answered out of order by different servers behind a load balancer, and
       * only the version says which answer is newer.
       *
       * Note what is NOT done here: the client never infers that READY is
       * "after" COOKING. It compares two integers.
       */
      final TrackedOrder? existing = state.tracked;

      if (existing != null &&
          existing.order.id == tracked.order.id &&
          tracked.version < existing.version) {
        // Older answer. Keep what we have, but the screen is no longer busy.
        state = state.copyWith(phase: OrderTrackingPhase.loaded);

        return;
      }

      state = state.copyWith(
        phase: OrderTrackingPhase.loaded,
        tracked: tracked,
        fetchedAt: DateTime.now(),
      );

      _reschedule(tracked);
    } on ApiException catch (error) {
      if (_disposed || sequence != _sequence) return;

      _handleFailure(error);
    } catch (_) {
      if (_disposed || sequence != _sequence) return;

      _handleOffline();
    }
  }

  void _handleFailure(ApiException error) {
    switch (error.code) {
      case ApiErrorCode.unauthenticated:
        _stopPolling();
        state = state.copyWith(phase: OrderTrackingPhase.unauthorized);
      case ApiErrorCode.orderNotFound:
        _stopPolling();
        state = state.copyWith(phase: OrderTrackingPhase.notFound);
      default:
        _handleOffline();
    }
  }

  /// A failure the app cannot interpret is treated as "we could not ask".
  ///
  /// If there is a cached order it stays on screen, clearly marked stale. The
  /// alternative — replacing a real order with an error page because one
  /// refresh timed out on a motorway — loses the customer the information they
  /// opened the screen for.
  void _handleOffline() {
    _consecutiveFailures++;

    state = state.copyWith(
      phase: state.hasOrder
          ? OrderTrackingPhase.offline
          : OrderTrackingPhase.error,
    );

    if (state.tracked case final TrackedOrder tracked) {
      _reschedule(tracked);
    }
  }

  void _reschedule(TrackedOrder tracked) {
    _timer?.cancel();
    _timer = null;

    // Nothing more will happen to this order. Asking again forever would be
    // asking a question that has a final answer.
    if (!tracked.isActive) {
      state = state.copyWith(pollingStopped: true);

      return;
    }

    final DateTime startedAt = _startedAt ?? DateTime.now();

    if (DateTime.now().difference(startedAt) > TrackingConfig.pollingBudget) {
      state = state.copyWith(pollingStopped: true);

      return;
    }

    /*
     * Back off after failures rather than retrying at full rate.
     *
     * A server that just refused one request is not helped by the same request
     * twenty seconds later from every open screen. Doubling per failure, capped
     * at eight times the base interval so recovery is still measured in
     * minutes rather than hours.
     */
    final int multiplier = switch (_consecutiveFailures) {
      0 => 1,
      1 => 2,
      2 => 4,
      _ => 8,
    };

    _timer = Timer(TrackingConfig.refreshInterval * multiplier, () {
      if (_disposed) return;

      unawaited(_fetch(showBusy: true));
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(pollingStopped: true);
  }
}

final orderTrackingProvider = NotifierProvider.autoDispose
    .family<OrderTrackingController, OrderTrackingState, String>(
      OrderTrackingController.new,
    );
