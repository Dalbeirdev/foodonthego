import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/checkout.dart';
import '../../domain/repositories/checkout_repository.dart';
import 'providers.dart';

/// Why the checkout screen has nothing to show, or why a check did not take.
enum CheckoutFailure {
  network,
  tripGone,
  cartGone,
  cartEmpty,

  /// The quote no longer resolves. The screen prepares a fresh one rather than
  /// explaining an id the customer never saw.
  quoteGone,

  unauthorized,
  rateLimited,
  serverError,
  unknown,
}

/// What the checkout screen is showing.
class CheckoutState {
  const CheckoutState({
    this.checkout,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isValidating = false,
    this.loadFailure,
    this.failure,
    this.failureMessage,
    this.hasLoaded = false,
  });

  /// Null until the first answer arrives. A screen that has not asked shows a
  /// wait, never a price.
  final Checkout? checkout;

  final bool isLoading;
  final bool isRefreshing;
  final bool isValidating;

  final CheckoutFailure? loadFailure;
  final CheckoutFailure? failure;
  final String? failureMessage;

  final bool hasLoaded;

  /// **The server's answer, never derived here.**
  ///
  /// Null — not asked yet — is not a yes, and neither is an empty issue list on
  /// a response whose own flag says no.
  bool get readyForPayment => checkout?.readyForPayment ?? false;

  /// Whether the quote on screen is one the server would still honour.
  bool get isUsable => checkout?.status.isUsable ?? false;

  bool get hasExpired => checkout?.status == CheckoutStatus.expired;

  bool get isStale => checkout?.status == CheckoutStatus.stale;

  CheckoutState copyWith({
    Checkout? checkout,
    bool? isLoading,
    bool? isRefreshing,
    bool? isValidating,
    CheckoutFailure? loadFailure,
    CheckoutFailure? failure,
    String? failureMessage,
    bool? hasLoaded,
    bool clearLoadFailure = false,
    bool clearFailure = false,
  }) => CheckoutState(
    checkout: checkout ?? this.checkout,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isValidating: isValidating ?? this.isValidating,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
    hasLoaded: hasLoaded ?? this.hasLoaded,
  );
}

/// Preparing a checkout and asking whether it still stands.
///
/// **This class computes no amount and decides no readiness.** It fetches what
/// the server worked out and renders it. There is no arithmetic here on purpose:
/// a client that could produce its own total would be a second answer to a
/// question that must have exactly one, and this is the screen where a customer
/// agrees to a figure.
class CheckoutController extends Notifier<CheckoutState> {
  String? _tripId;
  bool _disposed = false;

  CheckoutRepository get _checkout => ref.read(checkoutRepositoryProvider);

  @override
  CheckoutState build() {
    ref.onDispose(() => _disposed = true);

    return const CheckoutState();
  }

  Future<void> open({required String tripId}) async {
    _tripId = tripId;

    state = const CheckoutState(isLoading: true);

    await _prepare();
  }

  /// A pull-to-refresh, or the customer tapping Refresh on an expired quote.
  ///
  /// Always prepares afresh rather than re-validating what is held: a quote
  /// that has expired cannot be revived, and one that has gone stale is stale
  /// precisely because the facts moved.
  Future<void> refresh() async {
    if (_tripId == null) return;

    state = state.copyWith(isRefreshing: true, clearFailure: true);

    await _prepare();
  }

  Future<void> retry() async {
    if (_tripId == null) return;

    state = state.copyWith(isLoading: true, clearLoadFailure: true);

    await _prepare();
  }

  Future<void> _prepare() async {
    final String? tripId = _tripId;

    if (tripId == null) return;

    try {
      final Checkout checkout = await _checkout.prepare(tripId: tripId);

      if (_disposed) return;

      state = state.copyWith(
        checkout: checkout,
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        clearLoadFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        loadFailure: _failureFor(error),
      );
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        loadFailure: CheckoutFailure.unknown,
      );
    }
  }

  /// Asks the server whether this exact quote could still be paid for.
  ///
  /// What the Proceed to Payment button does in Module 14. It hands off to
  /// nothing: Module 15 owns the payment, and this is the last question asked
  /// before that boundary.
  Future<void> validate() async {
    final String? tripId = _tripId;
    final String? checkoutId = state.checkout?.checkoutId;

    if (tripId == null || checkoutId == null || state.isValidating) return;

    state = state.copyWith(isValidating: true, clearFailure: true);

    try {
      final Checkout checkout = await _checkout.validate(
        tripId: tripId,
        checkoutId: checkoutId,
      );

      if (_disposed) return;

      state = state.copyWith(checkout: checkout, isValidating: false);
    } on ApiException catch (error) {
      if (_disposed) return;

      final CheckoutFailure failure = _failureFor(error);

      state = state.copyWith(
        isValidating: false,
        failure: failure,
        failureMessage: error.message,
      );

      // A quote the server no longer knows about cannot be explained to a
      // customer who never saw its id. Preparing a fresh one is the only
      // honest response, and it is what the screen would offer anyway.
      if (failure == CheckoutFailure.quoteGone) await _prepare();
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isValidating: false,
        failure: CheckoutFailure.unknown,
      );
    }
  }

  CheckoutFailure _failureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => CheckoutFailure.network,
    ApiErrorCode.tripNotFound ||
    ApiErrorCode.notFound => CheckoutFailure.tripGone,
    ApiErrorCode.cartNotFound => CheckoutFailure.cartGone,
    ApiErrorCode.cartEmpty => CheckoutFailure.cartEmpty,
    ApiErrorCode.checkoutQuoteNotFound ||
    ApiErrorCode.checkoutQuoteExpired ||
    ApiErrorCode.checkoutQuoteStale ||
    ApiErrorCode.checkoutQuoteConsumed => CheckoutFailure.quoteGone,
    ApiErrorCode.unauthenticated => CheckoutFailure.unauthorized,
    ApiErrorCode.rateLimited => CheckoutFailure.rateLimited,
    ApiErrorCode.serverError => CheckoutFailure.serverError,
    _ => CheckoutFailure.unknown,
  };
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);
