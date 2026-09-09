import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/placed_order.dart';
import '../../domain/payments/payment_handoff.dart';
import '../../domain/repositories/order_repository.dart';
import 'providers.dart';

/// Why placing an order or paying for it did not work.
enum OrderFailure {
  network,

  /// The quote timed out, or the basket moved under it. The customer goes back
  /// to checkout for a fresh one rather than being shown an id they never saw.
  quoteGone,
  quoteExpired,
  quoteStale,

  orderGone,
  alreadyPaid,
  notPayable,

  /// The provider said no. The customer can act on this.
  declined,

  /// We could not ask. The customer cannot act on this and must not be told
  /// their card was refused — those are different sentences.
  gatewayUnavailable,

  /// A result came back that the server would not accept.
  verificationFailed,

  /// This build cannot open a provider checkout at all.
  paymentUnavailable,

  unauthorized,
  rateLimited,
  serverError,
  unknown,
}

/// What the payment screen is showing.
class OrderState {
  const OrderState({
    this.order,
    this.intent,
    this.isPlacing = false,
    this.isPaying = false,
    this.failure,
    this.failureMessage,
    this.wasCancelled = false,
  });

  final PlacedOrder? order;
  final PaymentIntent? intent;

  final bool isPlacing;
  final bool isPaying;

  final OrderFailure? failure;
  final String? failureMessage;

  /// The customer closed the provider sheet. Not a failure, and shown as a
  /// neutral note rather than an error.
  final bool wasCancelled;

  bool get isPlaced => order?.isPlaced ?? false;

  bool get isBusy => isPlacing || isPaying;

  OrderState copyWith({
    PlacedOrder? order,
    PaymentIntent? intent,
    bool? isPlacing,
    bool? isPaying,
    OrderFailure? failure,
    String? failureMessage,
    bool? wasCancelled,
    bool clearFailure = false,
  }) => OrderState(
    order: order ?? this.order,
    intent: intent ?? this.intent,
    isPlacing: isPlacing ?? this.isPlacing,
    isPaying: isPaying ?? this.isPaying,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
    wasCancelled: wasCancelled ?? this.wasCancelled,
  );
}

/// Placing an order, opening a payment, and reporting the result back.
///
/// **This class never decides that an order is paid.** It hands the provider's
/// result to the server and adopts whatever order the server returns. A build
/// that set `isPaid` from a handoff result would be trusting a device, which is
/// the one thing the whole module exists to prevent.
class OrderController extends Notifier<OrderState> {
  bool _disposed = false;

  OrderRepository get _orders => ref.read(orderRepositoryProvider);

  PaymentHandoff get _handoff => ref.read(paymentHandoffProvider);

  @override
  OrderState build() {
    ref.onDispose(() => _disposed = true);

    return const OrderState();
  }

  /// Turn an accepted quote into an order, then open a payment against it.
  Future<void> place({
    required String tripId,
    required String checkoutId,
  }) async {
    if (state.isBusy) return;

    state = const OrderState(isPlacing: true);

    try {
      final PlacedOrder order = await _orders.place(
        tripId: tripId,
        checkoutId: checkoutId,
      );

      if (_disposed) return;

      state = state.copyWith(
        order: order,
        isPlacing: false,
        clearFailure: true,
      );

      await _openIntent(order);
    } on ApiException catch (error) {
      _fail(error, isPlacing: true);
    } catch (_) {
      _failUnknown(isPlacing: true);
    }
  }

  /// Reload an order this app already placed.
  Future<void> load(String orderId) async {
    try {
      final PlacedOrder order = await _orders.byId(orderId);

      if (_disposed) return;

      state = state.copyWith(order: order, clearFailure: true);
    } on ApiException catch (error) {
      _fail(error);
    } catch (_) {
      _failUnknown();
    }
  }

  Future<void> _openIntent(PlacedOrder order) async {
    if (order.isPlaced) return;

    try {
      final PaymentIntent intent = await _orders.createIntent(
        orderId: order.id,
      );

      if (_disposed) return;

      state = state.copyWith(intent: intent, clearFailure: true);
    } on ApiException catch (error) {
      _fail(error);
    } catch (_) {
      _failUnknown();
    }
  }

  /// Hand the customer to the provider, then give the result to the server.
  Future<void> pay() async {
    final PaymentIntent? intent = state.intent;

    if (intent == null || state.isBusy) return;

    state = state.copyWith(
      isPaying: true,
      wasCancelled: false,
      clearFailure: true,
    );

    final PaymentHandoffResult result = await _handoff.open(intent);

    if (_disposed) return;

    switch (result) {
      case PaymentHandoffCancelled():
        state = state.copyWith(isPaying: false, wasCancelled: true);

      case PaymentHandoffUnavailable(reason: final String reason):
        state = state.copyWith(
          isPaying: false,
          failure: OrderFailure.paymentUnavailable,
          failureMessage: reason,
        );

      case PaymentHandoffFailed(message: final String message):
        state = state.copyWith(
          isPaying: false,
          failure: OrderFailure.declined,
          failureMessage: message,
        );

      case PaymentHandoffSucceeded(
        providerOrderId: final String providerOrderId,
        providerPaymentId: final String providerPaymentId,
        signature: final String signature,
      ):
        await _verify(
          orderId: intent.order.id,
          providerOrderId: providerOrderId,
          providerPaymentId: providerPaymentId,
          signature: signature,
        );
    }
  }

  /// The server checks the provider's result. Whatever it says is the answer.
  Future<void> _verify({
    required String orderId,
    required String providerOrderId,
    required String providerPaymentId,
    required String signature,
  }) async {
    try {
      final PlacedOrder order = await _orders.verifyPayment(
        orderId: orderId,
        providerOrderId: providerOrderId,
        providerPaymentId: providerPaymentId,
        signature: signature,
      );

      if (_disposed) return;

      state = state.copyWith(order: order, isPaying: false, clearFailure: true);
    } on ApiException catch (error) {
      _fail(error, isPaying: true);
    } catch (_) {
      _failUnknown(isPaying: true);
    }
  }

  void _fail(
    ApiException error, {
    bool isPlacing = false,
    bool isPaying = false,
  }) {
    if (_disposed) return;

    final OrderFailure failure = switch (error.code) {
      ApiErrorCode.checkoutQuoteNotFound => OrderFailure.quoteGone,
      ApiErrorCode.checkoutQuoteExpired => OrderFailure.quoteExpired,
      ApiErrorCode.checkoutQuoteStale => OrderFailure.quoteStale,
      ApiErrorCode.checkoutQuoteConsumed => OrderFailure.quoteGone,
      ApiErrorCode.orderNotFound => OrderFailure.orderGone,
      ApiErrorCode.orderAlreadyPaid => OrderFailure.alreadyPaid,
      ApiErrorCode.orderNotPayable => OrderFailure.notPayable,
      ApiErrorCode.paymentDeclined => OrderFailure.declined,
      ApiErrorCode.paymentGatewayUnavailable => OrderFailure.gatewayUnavailable,
      // A signature or amount that did not check out is not told to the
      // customer as a card problem. Nothing about their card was wrong.
      ApiErrorCode.paymentSignatureInvalid ||
      ApiErrorCode.paymentAmountMismatch ||
      ApiErrorCode.paymentNotFound => OrderFailure.verificationFailed,
      ApiErrorCode.unauthenticated => OrderFailure.unauthorized,
      ApiErrorCode.rateLimited => OrderFailure.rateLimited,
      ApiErrorCode.network => OrderFailure.network,
      _ =>
        (error.status ?? 0) >= 500
            ? OrderFailure.serverError
            : OrderFailure.unknown,
    };

    state = state.copyWith(
      isPlacing: isPlacing ? false : state.isPlacing,
      isPaying: isPaying ? false : state.isPaying,
      failure: failure,
      failureMessage: error.message,
    );
  }

  void _failUnknown({bool isPlacing = false, bool isPaying = false}) {
    if (_disposed) return;

    state = state.copyWith(
      isPlacing: isPlacing ? false : state.isPlacing,
      isPaying: isPaying ? false : state.isPaying,
      failure: OrderFailure.unknown,
    );
  }
}

final orderControllerProvider = NotifierProvider<OrderController, OrderState>(
  OrderController.new,
);
