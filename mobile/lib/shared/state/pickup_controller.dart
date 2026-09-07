import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/pickup.dart';
import '../../domain/models/pre_checkout.dart';
import '../../domain/repositories/pickup_repository.dart';
import 'providers.dart';

/// Why the pickup screen has nothing to show, or why a choice did not take.
///
/// Separate cases because the customer's next move differs for each. "Something
/// went wrong with your pickup time" is not a move.
enum PickupFailure {
  network,

  offline,

  /// The journey is gone, or was never this customer's.
  tripGone,

  /// No cart on this journey.
  cartGone,

  cartEmpty,

  /// The chosen time no longer resolves — expired, or never theirs. The screen
  /// reloads the options rather than explaining a distinction the server
  /// deliberately does not draw.
  optionExpired,

  /// The order changed since the times were worked out.
  optionStale,

  /// The window is no longer one the kitchen can honour.
  timeUnavailable,

  /// The journey's estimate has aged out. The customer refreshes the journey;
  /// this app never triggers a billed routing call on its own.
  routeStale,

  /// The kitchen has stopped taking orders.
  notAcceptingOrders,

  /// The restaurant is gone, or no longer on this journey.
  restaurantUnavailable,

  unauthorized,

  rateLimited,

  serverError,

  unknown,
}

/// What the pickup screen is showing.
class PickupState {
  const PickupState({
    this.plan = const PickupPlan.unknown(),
    this.preCheckout,
    this.isLoading = false,
    this.isRefreshing = false,
    this.loadFailure,
    this.selectingOptionId,
    this.isValidating = false,
    this.failure,
    this.failureMessage,
    this.hasLoaded = false,
    this.isOffline = false,
  });

  final PickupPlan plan;

  /// The last answer to "could this be paid for". Null until asked — a screen
  /// that has not asked says nothing rather than implying a yes.
  final PreCheckoutResult? preCheckout;

  final bool isLoading;

  /// A pull-to-refresh over content already on screen.
  final bool isRefreshing;

  final PickupFailure? loadFailure;

  /// The option with a selection in flight. Its own chip shows the wait; the
  /// rest of the screen stays usable.
  final String? selectingOptionId;

  final bool isValidating;

  /// A failure from a *choice*, distinct from [loadFailure]. The times are
  /// still on screen; something the customer just tried did not take.
  final PickupFailure? failure;

  /// The server's own words, where they are safe to show. The client branches
  /// on the code and never on this.
  final String? failureMessage;

  /// True once a load has completed, successfully or not. Distinguishes "no
  /// times available" from "not asked yet" — they look identical on screen and
  /// mean opposite things.
  final bool hasLoaded;

  /// The last load failed for want of a network and there is something on
  /// screen. The times shown are from an earlier moment and the screen says so.
  final bool isOffline;

  List<PickupOption> get options => plan.options;

  PickupSelection get selection => plan.selection;

  /// Whether the customer may move on.
  ///
  /// **Read from the server's answer, never worked out here.** A screen that
  /// decided this for itself would be a second implementation of the rule, and
  /// the day the two disagree somebody reaches a payment for a kitchen that has
  /// shut. Null — not asked yet — is not a yes.
  bool get readyForCheckout => preCheckout?.readyForCheckout ?? false;

  /// The chosen option's id, where the choice is still one of the offered ones.
  String? get selectedOptionId {
    final DateTime? start = plan.selection.startAt;

    if (start == null || !plan.selection.status.isUsable) return null;

    for (final PickupOption option in plan.options) {
      if (option.startAt.isAtSameMomentAs(start)) return option.id;
    }

    return null;
  }

  PickupState copyWith({
    PickupPlan? plan,
    PreCheckoutResult? preCheckout,
    bool? isLoading,
    bool? isRefreshing,
    PickupFailure? loadFailure,
    String? selectingOptionId,
    bool? isValidating,
    PickupFailure? failure,
    String? failureMessage,
    bool? hasLoaded,
    bool? isOffline,
    bool clearLoadFailure = false,
    bool clearFailure = false,
    bool clearSelecting = false,
    bool clearPreCheckout = false,
  }) => PickupState(
    plan: plan ?? this.plan,
    preCheckout: clearPreCheckout ? null : (preCheckout ?? this.preCheckout),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    selectingOptionId: clearSelecting
        ? null
        : (selectingOptionId ?? this.selectingOptionId),
    isValidating: isValidating ?? this.isValidating,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isOffline: isOffline ?? this.isOffline,
  );
}

/// Fetching pickup times, choosing one, and asking whether the order holds.
///
/// **This class computes no time and decides no feasibility.** It fetches what
/// the server worked out, sends back an id, and renders the answer. There is no
/// arithmetic here on purpose: a client that could work out its own pickup
/// window would be a second answer to a question that must have exactly one.
///
/// The option ids are treated as opaque throughout — never parsed, never
/// compared for structure, never cached past a reload. They expire, and a
/// screen that kept them would offer a customer a time the server has already
/// forgotten.
class PickupController extends Notifier<PickupState> {
  final Random _random = Random();

  String? _tripId;
  bool _disposed = false;

  /// One key per attempt at a selection, kept across a retry.
  ///
  /// A retry after a lost response replays the *same* request rather than
  /// making a second one. Cleared once an attempt succeeds or is refused on its
  /// merits — a refusal is an answer, and the next try is a new request.
  final Map<String, String> _keys = <String, String>{};

  PickupRepository get _pickup => ref.read(pickupRepositoryProvider);

  @override
  PickupState build() {
    ref.onDispose(() => _disposed = true);

    return const PickupState();
  }

  /// Opens the pickup screen for a journey.
  Future<void> open({required String tripId}) async {
    _tripId = tripId;

    state = const PickupState(isLoading: true);

    await _load();
  }

  /// A pull-to-refresh. Keeps what is on screen while the request is in flight.
  ///
  /// Always re-fetches rather than reusing what is held: the ids on screen have
  /// a short life, and refreshing a screen whose chips no longer work is worse
  /// than not refreshing at all.
  Future<void> refresh() async {
    if (_tripId == null) return;

    state = state.copyWith(isRefreshing: true, clearFailure: true);

    await _load();
  }

  Future<void> retry() async {
    if (_tripId == null) return;

    state = state.copyWith(isLoading: true, clearLoadFailure: true);

    await _load();
  }

  Future<void> _load() async {
    final String? tripId = _tripId;

    if (tripId == null) return;

    try {
      final PickupView view = await _pickup.options(tripId: tripId);

      if (_disposed) return;

      state = state.copyWith(
        plan: view.plan,
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        isOffline: false,
        clearLoadFailure: true,
        // The answer on screen was about the previous plan. Keeping it beside a
        // fresh set of times would show a customer a verdict from one moment
        // and the times from another.
        clearPreCheckout: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        loadFailure: _failureFor(error),
        isOffline:
            error.code == ApiErrorCode.network && state.options.isNotEmpty,
      );
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        loadFailure: PickupFailure.unknown,
      );
    }
  }

  /// Agrees to one of the offered times.
  ///
  /// [optionId] came from the server and goes back untouched. Nothing else is
  /// sent — there is no time in this request, and no field one could be put in.
  Future<void> choose(String optionId) async {
    final String? tripId = _tripId;

    if (tripId == null || state.selectingOptionId != null) return;

    state = state.copyWith(selectingOptionId: optionId, clearFailure: true);

    final String key = _keys.putIfAbsent(optionId, _newKey);

    try {
      final PickupView view = await _pickup.selectOption(
        tripId: tripId,
        optionId: optionId,
        idempotencyKey: key,
      );

      if (_disposed) return;

      _keys.remove(optionId);

      state = state.copyWith(
        plan: view.plan,
        clearSelecting: true,
        clearFailure: true,
        // The choice changed what pre-checkout would say. The old answer is
        // dropped rather than left to look current.
        clearPreCheckout: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      if (error.code != ApiErrorCode.network) _keys.remove(optionId);

      final PickupFailure failure = _failureFor(error);

      state = state.copyWith(
        clearSelecting: true,
        failure: failure,
        failureMessage: error.message,
      );

      // An id that no longer resolves, or a plan whose facts have moved, means
      // every chip on screen is suspect — not just the one that was tapped.
      // Reloading is the only honest response: leaving stale times up invites
      // the customer to tap another and be refused again.
      if (failure == PickupFailure.optionExpired ||
          failure == PickupFailure.optionStale) {
        await _load();
      }
    } catch (_) {
      if (_disposed) return;

      _keys.remove(optionId);

      state = state.copyWith(
        clearSelecting: true,
        failure: PickupFailure.unknown,
      );
    }
  }

  /// Asks the server whether the order could be paid for.
  ///
  /// The answer is stored and rendered. It is not interpreted, not cached past
  /// the next change, and never reconstructed from the issues it lists.
  Future<void> validate() async {
    final String? tripId = _tripId;

    if (tripId == null || state.isValidating) return;

    state = state.copyWith(isValidating: true, clearFailure: true);

    try {
      final PreCheckoutResult result = await _pickup.preCheckout(
        tripId: tripId,
      );

      if (_disposed) return;

      state = state.copyWith(
        preCheckout: result,
        plan: result.plan,
        isValidating: false,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      state = state.copyWith(
        isValidating: false,
        failure: _failureFor(error),
        failureMessage: error.message,
      );
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isValidating: false,
        failure: PickupFailure.unknown,
      );
    }
  }

  PickupFailure _failureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => PickupFailure.network,
    ApiErrorCode.tripNotFound ||
    ApiErrorCode.notFound => PickupFailure.tripGone,
    ApiErrorCode.cartNotFound => PickupFailure.cartGone,
    ApiErrorCode.cartEmpty => PickupFailure.cartEmpty,
    ApiErrorCode.pickupOptionExpired ||
    // Forbidden reaches the client as a 404 and means the id belongs
    // elsewhere. To the customer it is the same event as an expiry: these
    // times are no good, here are fresh ones.
    ApiErrorCode.pickupOptionForbidden => PickupFailure.optionExpired,
    ApiErrorCode.pickupOptionStale => PickupFailure.optionStale,
    ApiErrorCode.pickupTimeInvalid ||
    ApiErrorCode.pickupOutsideHours ||
    ApiErrorCode.pickupBeforeReady ||
    ApiErrorCode.noFeasiblePickupWindow ||
    ApiErrorCode.pickupOptionsUnavailable => PickupFailure.timeUnavailable,
    ApiErrorCode.routeStale ||
    ApiErrorCode.routeNotReady => PickupFailure.routeStale,
    ApiErrorCode.restaurantNotAcceptingOrders =>
      PickupFailure.notAcceptingOrders,
    ApiErrorCode.restaurantUnavailable ||
    ApiErrorCode.restaurantOutsideRoute => PickupFailure.restaurantUnavailable,
    ApiErrorCode.unauthenticated => PickupFailure.unauthorized,
    ApiErrorCode.rateLimited => PickupFailure.rateLimited,
    ApiErrorCode.serverError => PickupFailure.serverError,
    _ => PickupFailure.unknown,
  };

  String _newKey() {
    final int high = _random.nextInt(1 << 32);
    final int low = _random.nextInt(1 << 32);

    return 'pickup-'
        '${high.toRadixString(16).padLeft(8, '0')}'
        '${low.toRadixString(16).padLeft(8, '0')}';
  }
}

final pickupControllerProvider =
    NotifierProvider<PickupController, PickupState>(PickupController.new);
