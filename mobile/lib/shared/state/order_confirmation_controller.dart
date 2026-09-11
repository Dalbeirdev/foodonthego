import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/order_status_report.dart';
import '../../domain/models/pickup_credential.dart';
import '../../domain/models/placed_order.dart';
import '../../domain/repositories/order_repository.dart';
import 'providers.dart';

/// What the confirmation screen is showing.
///
/// **None of these is "your payment failed".** After a capture there is no
/// honest state that says so, and a phase for it would eventually be rendered
/// with a Pay button behind it — to somebody whose money has already gone.
enum OrderConfirmationPhase {
  /// First read, nothing known yet.
  loading,

  /// Money captured, order being written. The customer waits.
  creating,

  /// Money captured, and a first attempt to write the order already failed.
  ///
  /// Shown identically to [creating]; the distinction exists so support and
  /// analytics can tell a slow path from a broken one.
  recovering,

  /// The order exists.
  placed,

  /// Nothing has been taken. Offering payment here is honest.
  awaitingPayment,

  /// The request never reached the server, or its answer was unreadable.
  ///
  /// Critically NOT a payment failure: an app that cannot reach the server
  /// knows nothing about the money, and must not guess.
  networkError,

  /// This order is not this customer's, or the session has gone.
  unauthorized,
}

class OrderConfirmationState {
  const OrderConfirmationState({
    this.phase = OrderConfirmationPhase.loading,
    this.order,
    this.credential,
    this.message,
    this.attempts = 0,
  });

  final OrderConfirmationPhase phase;
  final PlacedOrder? order;
  final PickupCredential? credential;
  final String? message;

  /// How many times the server has been asked. Bounded, so a permanently stuck
  /// order stops polling rather than draining a battery on a highway.
  final int attempts;

  /// Whether the money has already left the customer's account.
  bool get isPaidFor =>
      phase == OrderConfirmationPhase.placed ||
      phase == OrderConfirmationPhase.creating ||
      phase == OrderConfirmationPhase.recovering;

  /// Whether showing a way to pay is honest.
  ///
  /// The single question the screen asks before rendering anything resembling a
  /// Pay button. False whenever the money may already be gone — including the
  /// network-error case, where the app simply does not know.
  bool get mayOfferPayment => phase == OrderConfirmationPhase.awaitingPayment;

  bool get isSettling =>
      phase == OrderConfirmationPhase.creating ||
      phase == OrderConfirmationPhase.recovering;

  OrderConfirmationState copyWith({
    OrderConfirmationPhase? phase,
    PlacedOrder? order,
    PickupCredential? credential,
    String? message,
    int? attempts,
  }) => OrderConfirmationState(
    phase: phase ?? this.phase,
    order: order ?? this.order,
    credential: credential ?? this.credential,
    message: message ?? this.message,
    attempts: attempts ?? this.attempts,
  );
}

/// Reads an order's state, and keeps reading while it is still being written.
///
/// Idempotent on the server, so polling cannot produce a second order — the
/// status endpoint either finds the order or asks the same creation service
/// every other route uses.
class OrderConfirmationController extends Notifier<OrderConfirmationState> {
  OrderConfirmationController(this.orderId);

  final String orderId;

  /// Ten attempts at three seconds is half a minute of waiting.
  ///
  /// Long enough to cover a slow worker and a bad connection; short enough that
  /// a genuinely stuck order stops polling instead of running until the app is
  /// killed. After this the screen still says the money is safe — it simply
  /// stops asking, and offers a manual retry.
  static const int maxAttempts = 10;
  static const Duration pollInterval = Duration(seconds: 3);

  Timer? _timer;

  @override
  OrderConfirmationState build() {
    ref.onDispose(() => _timer?.cancel());

    // Kicked off after the first frame so the screen can paint its loading
    // state rather than appearing blank while the first request is in flight.
    Future<void>.microtask(load);

    return const OrderConfirmationState();
  }

  OrderRepository get _orders => ref.read(orderRepositoryProvider);

  Future<void> load() async {
    try {
      final OrderStatusReport report = await _orders.statusOf(orderId);

      state = state.copyWith(
        phase: switch (report.state) {
          OrderCreationState.placed => OrderConfirmationPhase.placed,
          OrderCreationState.creating => OrderConfirmationPhase.creating,
          OrderCreationState.recovering => OrderConfirmationPhase.recovering,
          OrderCreationState.awaitingPayment =>
            OrderConfirmationPhase.awaitingPayment,
        },
        order: report.order,
        message: report.message,
        attempts: state.attempts + 1,
      );

      if (state.phase == OrderConfirmationPhase.placed) {
        _timer?.cancel();
        await _loadCredential();

        return;
      }

      if (state.isSettling && state.attempts < maxAttempts) {
        _timer?.cancel();
        _timer = Timer(pollInterval, load);
      }
    } on ApiException catch (error) {
      state = state.copyWith(
        phase: switch (error.code) {
          ApiErrorCode.unauthenticated ||
          ApiErrorCode.forbidden ||
          ApiErrorCode.notFound => OrderConfirmationPhase.unauthorized,

          // Everything else — including a timeout, a 500 and an unreadable
          // body — is a network error and NOT a payment failure. The app could
          // not ask; that says nothing about whether the money moved.
          _ => OrderConfirmationPhase.networkError,
        },
        attempts: state.attempts + 1,
      );
    }
  }

  /// The pickup code, fetched only once there is an order to collect.
  ///
  /// Failure here is deliberately not fatal to the screen. A customer who can
  /// see their order and its number but not yet its code has most of what they
  /// need, and losing the confirmation entirely over a second request would be
  /// a worse outcome than a missing code with a retry.
  Future<void> _loadCredential() async {
    if (state.order?.status.canBeCollected != true) return;

    try {
      state = state.copyWith(
        credential: await _orders.pickupCredential(orderId),
      );
    } on ApiException {
      // Left null. The screen shows the order and offers to fetch it again.
    }
  }

  /// A manual retry, for when polling has given up or the customer is impatient.
  Future<void> retry() async {
    _timer?.cancel();
    state = state.copyWith(attempts: 0);
    await load();
  }
}

final orderConfirmationProvider = NotifierProvider.autoDispose
    .family<OrderConfirmationController, OrderConfirmationState, String>(
      OrderConfirmationController.new,
    );
