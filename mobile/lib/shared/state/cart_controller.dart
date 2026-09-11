import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/cart_revalidation.dart';
import '../../domain/models/money.dart';
import '../../domain/repositories/cart_repository.dart';
import 'providers.dart';

/// Why the cart screen has nothing to show, or why an edit did not take.
///
/// Separate cases because the customer's next move differs for each. "Something
/// went wrong" is not a move.
enum CartFailure {
  /// The request never left the device.
  network,

  offline,

  /// The trip is gone, or was never this customer's.
  tripGone,

  /// The line is not in this cart — removed on another device, or already gone.
  lineGone,

  /// The dish costs more than the customer was shown. The new figure comes with
  /// it, so they agree before it is charged.
  priceChanged,

  /// The quantity was refused: below one, or above the ceiling.
  quantityRefused,

  /// The dish, a size or an option went away.
  unavailable,

  /// The kitchen has stopped taking orders.
  notAcceptingOrders,

  unauthorized,

  rateLimited,

  serverError,

  unknown,
}

/// What the cart screen is showing.
class CartState {
  const CartState({
    this.view = const CartView.empty(),
    this.revalidation,
    this.isLoading = false,
    this.isRefreshing = false,
    this.loadFailure,
    this.busyLineId,
    this.isEmptying = false,
    this.failure,
    this.failureMessage,
    this.failedLineId,
    this.priceChangedTo,
    this.hasLoaded = false,
    this.isOffline = false,
  });

  final CartView view;

  /// The last answer to "does this cart still hold". Null until asked — and a
  /// screen that has not asked says nothing rather than implying all is well.
  final CartRevalidation? revalidation;

  final bool isLoading;

  /// A pull-to-refresh over content already on screen.
  final bool isRefreshing;

  final CartFailure? loadFailure;

  /// The line with an edit in flight. One at a time: its own stepper is
  /// disabled and the rest of the screen stays usable, because blocking the
  /// whole cart to change one quantity makes a fast connection feel slow and a
  /// slow one feel broken.
  final String? busyLineId;

  final bool isEmptying;

  /// A failure from an *edit*, distinct from [loadFailure]. The cart is still
  /// on screen and still correct; something the customer just tried did not
  /// take.
  final CartFailure? failure;

  /// The server's own words, where they are safe to show. The client branches
  /// on the code and never on this.
  final String? failureMessage;

  /// Which line the failure belongs to, so the message appears against it.
  final String? failedLineId;

  /// The new price, when a dish went up between the screen loading and an edit.
  final Money? priceChangedTo;

  /// True once a load has completed, successfully or not. Distinguishes "empty
  /// cart" from "not asked yet" — they look identical and mean opposite things.
  final bool hasLoaded;

  /// The last load failed for want of a network and there is something on
  /// screen. The screen says so rather than implying these prices are live.
  final bool isOffline;

  Cart? get cart => view.cart;

  List<CartLine> get lines => view.cart?.lines ?? const <CartLine>[];

  bool get isEmpty => view.isEmpty;

  CartTotals? get totals => view.cart?.totals;

  int get itemCount => view.itemCount;

  String? get restaurantName => view.cart?.restaurantName;

  /// Whether any edit is in flight.
  bool get isBusy => busyLineId != null || isEmptying;

  /// The verdict on one line, if the cart has been revalidated.
  CartLineVerdict? verdictFor(String lineId) =>
      revalidation?.verdictFor(lineId);

  /// True when the customer must fix something before they could order.
  ///
  /// Read from the server's own per-line flag rather than derived from the
  /// finding, so a finding this build has never heard of still blocks.
  bool get hasBlockingProblem => revalidation?.hasBlockingProblem ?? false;

  CartState copyWith({
    CartView? view,
    CartRevalidation? revalidation,
    bool? isLoading,
    bool? isRefreshing,
    CartFailure? loadFailure,
    String? busyLineId,
    bool? isEmptying,
    CartFailure? failure,
    String? failureMessage,
    String? failedLineId,
    Money? priceChangedTo,
    bool? hasLoaded,
    bool? isOffline,
    bool clearLoadFailure = false,
    bool clearFailure = false,
    bool clearBusyLine = false,
    bool clearRevalidation = false,
  }) => CartState(
    view: view ?? this.view,
    revalidation: clearRevalidation
        ? null
        : (revalidation ?? this.revalidation),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    busyLineId: clearBusyLine ? null : (busyLineId ?? this.busyLineId),
    isEmptying: isEmptying ?? this.isEmptying,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
    failedLineId: clearFailure ? null : (failedLineId ?? this.failedLineId),
    priceChangedTo: clearFailure
        ? null
        : (priceChangedTo ?? this.priceChangedTo),
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isOffline: isOffline ?? this.isOffline,
  );
}

/// The cart screen's state.
///
/// **Nothing here computes money.** Every figure the customer sees came from
/// the server in the response to the request that changed it, and an edit
/// replaces the whole view rather than patching a total. A client that adjusted
/// its own subtotal after a quantity change would be right most days and wrong
/// on the day the price moved underneath it — and the customer would see one
/// number and be charged another.
///
/// Edits are not optimistic, deliberately. A stepper that moves before the
/// server has agreed shows a quantity the cart may not have, and this is the
/// screen where the customer is deciding what to spend. The line's own controls
/// disable while its request is in flight; the rest of the cart stays usable.
class CartController extends Notifier<CartState> {
  final Random _random = Random();

  String? _tripId;
  bool _disposed = false;

  /// One key per attempt at an unsafe request, kept across a retry.
  ///
  /// A retry after a lost response replays the *same* request rather than
  /// making a second one, so a connection that dies after the server acted
  /// cannot remove two lines. Cleared once an attempt succeeds or is refused
  /// on its merits — a refusal is an answer, and the next try is a new request.
  final Map<String, String> _keys = <String, String>{};

  CartRepository get _carts => ref.read(cartRepositoryProvider);

  @override
  CartState build() {
    ref.onDispose(() => _disposed = true);

    return const CartState();
  }

  /// Opens the cart for a journey, and asks whether it still holds.
  ///
  /// One request rather than two. The screen needs the cart and the verdict the
  /// moment it opens, and fetching them separately would show a total from one
  /// instant beside a judgement from another.
  Future<void> open({required String tripId}) async {
    _tripId = tripId;

    state = const CartState(isLoading: true);

    await _load();
  }

  /// A pull-to-refresh. Keeps what is on screen while the request is in flight.
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
      final RevalidatedCart answer = await _carts.revalidate(tripId: tripId);

      if (_disposed) return;

      state = state.copyWith(
        view: answer.view,
        revalidation: answer.revalidation,
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        isOffline: false,
        clearLoadFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      // A journey with no cart is not a failure. The server has nothing to
      // revalidate and says so; to the customer this is the ordinary empty
      // screen they would see before adding anything.
      if (error.code == ApiErrorCode.cartNotFound) {
        state = state.copyWith(
          view: const CartView.empty(),
          isLoading: false,
          isRefreshing: false,
          hasLoaded: true,
          isOffline: false,
          clearLoadFailure: true,
          clearRevalidation: true,
        );

        return;
      }

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        loadFailure: _loadFailureFor(error),
        // Prices already on screen are stale and the screen must say so rather
        // than let them pass for live.
        isOffline: error.code == ApiErrorCode.network && !state.isEmpty,
      );
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        loadFailure: CartFailure.serverError,
      );
    }
  }

  /// Changes one line's quantity.
  ///
  /// Refuses to send a zero. The server refuses it too — this is not the
  /// enforcement, it is the client declining to ask a question whose only
  /// honest answer is no. A customer who wants none of something removes it,
  /// on a control that says so.
  Future<void> setQuantity({required String lineId, required int quantity}) {
    if (quantity < 1) return Future<void>.value();

    return _edit(
      lineId: lineId,
      request: (String tripId, String key) => _carts.setQuantity(
        tripId: tripId,
        lineId: lineId,
        quantity: quantity,
        idempotencyKey: key,
      ),
    );
  }

  Future<void> increment(CartLine line) =>
      setQuantity(lineId: line.id, quantity: line.quantity + 1);

  /// One fewer, unless there is one left.
  ///
  /// At a quantity of one the stepper's minus does nothing and the screen shows
  /// a remove control instead. Turning the last decrement into a deletion is
  /// how a mis-tap loses a customer's selection, and it leaves the app unable
  /// to tell a mistake from an intention.
  Future<void> decrement(CartLine line) {
    if (line.quantity <= 1) return Future<void>.value();

    return setQuantity(lineId: line.id, quantity: line.quantity - 1);
  }

  Future<void> removeLine(String lineId) => _edit(
    lineId: lineId,
    request: (String tripId, String key) =>
        _carts.removeLine(tripId: tripId, lineId: lineId, idempotencyKey: key),
  );

  /// Empties the cart. Called only from an explicit, confirmed action.
  Future<void> empty() async {
    final String? tripId = _tripId;

    if (tripId == null || state.isBusy) return;

    state = state.copyWith(isEmptying: true, clearFailure: true);

    try {
      final CartView view = await _carts.empty(
        tripId: tripId,
        idempotencyKey: _keyFor('empty'),
      );

      if (_disposed) return;

      _keys.remove('empty');

      state = state.copyWith(
        view: view,
        isEmptying: false,
        // The cart that was just emptied is closed, so there is nothing left to
        // have an opinion about. Keeping the old verdict would leave warnings
        // on screen about lines that no longer exist.
        clearRevalidation: true,
        clearFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      _applyFailure(error, null, isEmptying: false);
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isEmptying: false,
        failure: CartFailure.serverError,
      );
    }
  }

  void dismissFailure() => state = state.copyWith(clearFailure: true);

  Future<void> _edit({
    required String lineId,
    required Future<CartView> Function(String tripId, String key) request,
  }) async {
    final String? tripId = _tripId;

    if (tripId == null || state.isBusy) return;

    state = state.copyWith(busyLineId: lineId, clearFailure: true);

    try {
      final CartView view = await request(tripId, _keyFor(lineId));

      if (_disposed) return;

      _keys.remove(lineId);

      state = state.copyWith(
        view: view,
        clearBusyLine: true,
        clearFailure: true,
        // The verdict described the cart as it was a moment ago. Rather than
        // leave a stale judgement beside a fresh total, the screen asks again.
        clearRevalidation: true,
      );

      // Cheap, and it is what keeps a price change visible after an edit: the
      // response to a PATCH carries the cart, not an opinion about it.
      unawaited(_revalidateQuietly());
    } on ApiException catch (error) {
      if (_disposed) return;

      _applyFailure(error, lineId, clearBusyLine: true);
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        clearBusyLine: true,
        failure: CartFailure.serverError,
        failedLineId: lineId,
      );
    }
  }

  /// Re-asks for the verdict without disturbing the screen.
  ///
  /// A failure here is silence: the cart on screen is correct and came from the
  /// edit's own response. Turning "we could not re-check the prices" into an
  /// error over a cart the customer just successfully changed would be noise.
  Future<void> _revalidateQuietly() async {
    final String? tripId = _tripId;

    if (tripId == null || state.isEmpty) return;

    try {
      final RevalidatedCart answer = await _carts.revalidate(tripId: tripId);

      if (_disposed) return;

      state = state.copyWith(
        view: answer.view,
        revalidation: answer.revalidation,
      );
    } catch (_) {
      // Deliberately nothing.
    }
  }

  /// The idempotency key for this attempt, minted once and kept for a retry.
  String _keyFor(String subject) => _keys.putIfAbsent(subject, () {
    final int a = _random.nextInt(0x7fffffff);
    final int b = _random.nextInt(0x7fffffff);

    return 'cart-$subject-${DateTime.now().microsecondsSinceEpoch}-$a-$b';
  });

  /// Records a refusal against the thing that was refused.
  ///
  /// A refusal on the merits clears the attempt's key: the customer's next move
  /// is a different request, and replaying the old one would replay the
  /// refusal. A network failure keeps the key, because the request may well
  /// have landed and a retry must not remove a second line.
  void _applyFailure(
    ApiException error,
    String? lineId, {
    bool clearBusyLine = false,
    bool? isEmptying,
  }) {
    if (error.code != ApiErrorCode.network) {
      _keys.remove(lineId ?? 'empty');
    }

    state = state.copyWith(
      clearBusyLine: clearBusyLine,
      isEmptying: isEmptying,
      failure: _editFailureFor(error),
      failureMessage: error.message,
      failedLineId: lineId,
      priceChangedTo: _newPriceFrom(error),
    );
  }

  /// The current price the server quoted when it refused a change.
  Money? _newPriceFrom(ApiException error) {
    if (error.code != ApiErrorCode.priceUpdated) return null;

    return Money.fromJson(error.details?['current_unit_price']);
  }

  CartFailure _loadFailureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => CartFailure.network,
    ApiErrorCode.tripNotFound || ApiErrorCode.notFound => CartFailure.tripGone,
    ApiErrorCode.unauthenticated => CartFailure.unauthorized,
    ApiErrorCode.rateLimited => CartFailure.rateLimited,
    ApiErrorCode.serverError => CartFailure.serverError,
    _ => CartFailure.unknown,
  };

  CartFailure _editFailureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => CartFailure.network,
    ApiErrorCode.priceUpdated => CartFailure.priceChanged,
    ApiErrorCode.quantityInvalid ||
    ApiErrorCode.quantityLimitExceeded => CartFailure.quantityRefused,
    ApiErrorCode.itemNotFound ||
    ApiErrorCode.cartNotFound => CartFailure.lineGone,
    ApiErrorCode.itemSoldOut ||
    ApiErrorCode.itemUnavailable ||
    ApiErrorCode.variantUnavailable ||
    ApiErrorCode.modifierUnavailable ||
    ApiErrorCode.restaurantUnavailable => CartFailure.unavailable,
    ApiErrorCode.restaurantNotAcceptingOrders => CartFailure.notAcceptingOrders,
    ApiErrorCode.unauthenticated => CartFailure.unauthorized,
    ApiErrorCode.rateLimited => CartFailure.rateLimited,
    ApiErrorCode.serverError => CartFailure.serverError,
    _ => CartFailure.unknown,
  };
}

final cartControllerProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

/// How many things are in the cart on this journey, for a badge.
///
/// A family keyed by the journey, because a customer with two journeys planned
/// has two carts and a badge that showed the wrong one would be worse than no
/// badge at all.
///
/// Deliberately separate from [cartControllerProvider]: this is a number in the
/// corner of a screen, and making the cart screen's whole state a dependency of
/// the menu's app bar would tie an editing controller's lifetime to a widget
/// that never edits anything.
///
/// Automatic retry is off, as everywhere else in this app. A badge that could
/// not be read is a badge that is simply absent, and a traveller in a dead zone
/// should not have their battery spent on re-requesting one.
final cartBadgeProvider = FutureProvider.autoDispose.family<CartView, String>(
  (Ref ref, String tripId) =>
      ref.watch(cartRepositoryProvider).cart(tripId: tripId),
  retry: (int count, Object error) => null,
);
