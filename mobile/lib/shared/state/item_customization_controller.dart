import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/menu_customization.dart';
import '../../domain/models/money.dart';
import '../../domain/models/restaurant_menu.dart';
import '../../domain/repositories/menu_repository.dart';
import 'providers.dart';

/// Why a configuration cannot be added.
///
/// Each names a part of the screen, because "invalid request" tells a customer
/// nothing and a screen that cannot say *which* group is unanswered cannot
/// scroll to it.
enum AddToCartFailure {
  network,
  offline,

  /// A required group has too few answers. [CustomizationState.invalidGroupId]
  /// says which.
  selectionIncomplete,

  /// The dish, a size, or an option went away between load and add.
  soldOut,

  /// The kitchen has stopped taking orders.
  notAcceptingOrders,

  /// The cart holds another restaurant's food, or belongs to another journey.
  cartConflict,

  /// The dish costs more than the customer was shown.
  priceChanged,

  quantityRefused,
  noteRefused,
  notFound,
  unauthorized,
  serverError,
  unknown,
}

/// What the customer has chosen so far, and what it would cost.
class CustomizationState {
  const CustomizationState({
    this.preview,
    this.isLoading = false,
    this.loadFailure,
    this.selectedVariantId,
    this.selectedOptionIds = const <String>{},
    this.quantity = 1,
    this.specialInstructions = '',
    this.isSubmitting = false,
    this.failure,
    this.failureMessage,
    this.invalidGroupId,
    this.addition,
    this.cart = const CartSummary.empty(),
    this.priceChangedTo,
    this.showValidation = false,
  });

  final MenuItemPreview? preview;

  final bool isLoading;
  final AddToCartFailure? loadFailure;

  final String? selectedVariantId;

  /// The chosen options, as a set: order is not part of a configuration.
  final Set<String> selectedOptionIds;

  final int quantity;
  final String specialInstructions;

  final bool isSubmitting;

  final AddToCartFailure? failure;

  /// The server's own words, where they are safe to show. The client branches
  /// on the code and never on this.
  final String? failureMessage;

  /// Which group the screen should scroll to and mark.
  final String? invalidGroupId;

  /// The server's answer to the last successful add.
  final CartAddition? addition;

  final CartSummary cart;

  /// The new price, when the dish went up between load and add. The customer
  /// looks at it before agreeing.
  final Money? priceChangedTo;

  /// Whether unanswered required groups should be marked.
  ///
  /// False until the customer tries to add: a screen that opens covered in red
  /// is telling somebody off for not having done anything yet.
  final bool showValidation;

  MenuItem? get item => preview?.item;

  MenuItemCustomization get customization =>
      preview?.customization ?? const MenuItemCustomization();

  MenuItemVariant? get selectedVariant =>
      customization.variantById(selectedVariantId);

  bool get hasLoaded => preview != null;

  /// The dish itself is unorderable — sold out, or the restaurant is not
  /// taking orders. Distinct from an unanswered question, which the customer
  /// can fix.
  bool get isOrderable {
    final MenuItemPreview? loaded = preview;

    if (loaded == null) return false;

    return loaded.item.isOrderable && loaded.restaurant.canOrder;
  }

  /// Every required group that has too few answers, in screen order.
  List<MenuModifierGroup> get unsatisfiedGroups => <MenuModifierGroup>[
    for (final MenuModifierGroup group in customization.modifierGroups)
      if (_chosenIn(group) < group.minSelect) group,
  ];

  /// True when a size must be chosen and has not been.
  bool get needsVariant =>
      customization.requiresVariant && selectedVariant == null;

  bool get isComplete => !needsVariant && unsatisfiedGroups.isEmpty;

  int _chosenIn(MenuModifierGroup group) {
    int count = 0;

    for (final MenuModifierOption option in group.options) {
      if (selectedOptionIds.contains(option.id)) count++;
    }

    return count;
  }

  int chosenIn(MenuModifierGroup group) => _chosenIn(group);

  /// True when the customer has used up a group's allowance.
  bool isFull(MenuModifierGroup group) =>
      !group.isSingleSelect && _chosenIn(group) >= group.maxSelect;

  /// The unit price the screen shows.
  ///
  /// **A preview, not an authority.** It exists so the total moves the instant
  /// a customer taps something; what they are charged is what the server
  /// calculates when they add. The two agree unless the menu changed underneath
  /// them, which is the case the price-change refusal exists for.
  Money? get previewUnitPrice {
    final MenuItemPreview? loaded = preview;

    if (loaded == null) return null;

    final Money base = selectedVariant?.price ?? loaded.item.price;
    int minor = base.amountMinor;

    for (final String id in selectedOptionIds) {
      final MenuModifierOption? option = customization.optionById(id);

      if (option == null) continue;
      if (option.priceDelta.currency != base.currency) continue;

      minor += option.priceDelta.amountMinor;
    }

    return Money(amountMinor: minor, currency: base.currency);
  }

  Money? get previewLineTotal {
    final Money? unit = previewUnitPrice;

    if (unit == null) return null;

    return Money(
      amountMinor: unit.amountMinor * quantity,
      currency: unit.currency,
    );
  }

  bool get canDecrease => quantity > 1;

  bool get canIncrease => quantity < customization.limits.maxQuantity;

  int get noteRemaining =>
      customization.limits.maxSpecialInstructions - specialInstructions.length;

  CustomizationState copyWith({
    MenuItemPreview? preview,
    bool? isLoading,
    AddToCartFailure? loadFailure,
    bool clearLoadFailure = false,
    String? selectedVariantId,
    Set<String>? selectedOptionIds,
    int? quantity,
    String? specialInstructions,
    bool? isSubmitting,
    AddToCartFailure? failure,
    bool clearFailure = false,
    String? failureMessage,
    String? invalidGroupId,
    CartAddition? addition,
    bool clearAddition = false,
    CartSummary? cart,
    Money? priceChangedTo,
    bool? showValidation,
  }) => CustomizationState(
    preview: preview ?? this.preview,
    isLoading: isLoading ?? this.isLoading,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    selectedVariantId: selectedVariantId ?? this.selectedVariantId,
    selectedOptionIds: selectedOptionIds ?? this.selectedOptionIds,
    quantity: quantity ?? this.quantity,
    specialInstructions: specialInstructions ?? this.specialInstructions,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
    invalidGroupId: clearFailure
        ? null
        : (invalidGroupId ?? this.invalidGroupId),
    addition: clearAddition ? null : (addition ?? this.addition),
    cart: cart ?? this.cart,
    priceChangedTo: clearFailure
        ? null
        : (priceChangedTo ?? this.priceChangedTo),
    showValidation: showValidation ?? this.showValidation,
  );
}

/// The item detail screen's state.
///
/// Three things this class exists to get right:
///
/// 1. **The newest request wins.** A customer who backs out of one dish and
///    opens another generates two requests that can return in any order.
/// 2. **A retry does not add twice.** One idempotency key is minted per
///    configuration and reused until the add succeeds, so a lost response
///    followed by a retry is one cart line, not two.
/// 3. **The preview is never authoritative.** It moves instantly for the sake
///    of a responsive screen; the server's answer replaces it.
class ItemCustomizationController extends Notifier<CustomizationState> {
  String? _tripId;
  String? _restaurantId;
  String? _itemId;

  bool _disposed = false;

  /// Which load the state belongs to. Only the newest may write.
  int _generation = 0;

  /// Minted per attempt and kept across retries of that attempt, so a lost
  /// response and a retry are one logical add. Cleared once an add succeeds or
  /// the configuration changes, because a *different* configuration is a
  /// different request and must not be deduplicated against the last one.
  String? _idempotencyKey;

  static final Random _random = Random();

  late final MenuRepository _menus;

  @override
  CustomizationState build() {
    _menus = ref.read(menuRepositoryProvider);
    ref.onDispose(() => _disposed = true);

    return const CustomizationState();
  }

  /// Opens the screen for one dish.
  Future<void> open({
    required String tripId,
    required String restaurantId,
    required String itemId,
  }) async {
    final bool same =
        _tripId == tripId && _restaurantId == restaurantId && _itemId == itemId;

    if (same && (state.hasLoaded || state.isLoading)) return;

    _tripId = tripId;
    _restaurantId = restaurantId;
    _itemId = itemId;

    // A different dish means everything on screen belongs to the previous one.
    state = const CustomizationState(isLoading: true);

    await _load();
  }

  Future<void> retryLoad() => _load();

  Future<void> _load() async {
    final String? tripId = _tripId;
    final String? restaurantId = _restaurantId;
    final String? itemId = _itemId;

    if (tripId == null || restaurantId == null || itemId == null) return;

    final int generation = ++_generation;

    state = state.copyWith(isLoading: !state.hasLoaded, clearLoadFailure: true);

    try {
      final MenuItemPreview preview = await _menus.item(
        tripId: tripId,
        restaurantId: restaurantId,
        itemId: itemId,
      );

      // A slower earlier request finishing after a later one. Its answer is
      // about a dish the customer has already navigated away from.
      if (_disposed || generation != _generation) return;

      state = _withDefaults(preview);
      unawaited(refreshCart());
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        isLoading: false,
        loadFailure: _loadFailureFor(error),
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        isLoading: false,
        loadFailure: AddToCartFailure.serverError,
      );
    }
  }

  /// The screen as it opens: configured defaults chosen, nothing else.
  CustomizationState _withDefaults(MenuItemPreview preview) {
    final MenuItemCustomization customization = preview.customization;

    final Set<String> defaults = <String>{
      for (final MenuModifierGroup group in customization.modifierGroups)
        ...group.defaultOptionIds,
    };

    return CustomizationState(
      preview: preview,
      // The operator's default, or nothing. Never the first row — that would
      // quote a price nobody chose to show.
      selectedVariantId: customization.defaultVariant?.id,
      selectedOptionIds: defaults,
      cart: state.cart,
    );
  }

  // --- choosing ------------------------------------------------------------

  void selectVariant(String variantId) {
    if (state.selectedVariantId == variantId) return;

    final MenuItemVariant? variant = state.customization.variantById(variantId);

    // A sold-out size is drawn disabled; this is the second lock, so a
    // programmatic caller cannot select one either.
    if (variant == null || !variant.isAvailable) return;

    // Options are not cleared. Every group on this dish applies to every size
    // of it — the schema has no variant-dependent groups — so a customer who
    // chose "Hot" and then "Large" keeps "Hot". If conditional groups are ever
    // added, this is the line that has to revalidate.
    _configurationChanged();

    state = state.copyWith(selectedVariantId: variantId, clearFailure: true);
  }

  /// Taps an option. Radios replace, checkboxes toggle.
  void toggleOption(MenuModifierGroup group, MenuModifierOption option) {
    if (!option.isAvailable) return;

    final Set<String> next = <String>{...state.selectedOptionIds};

    if (group.isSingleSelect) {
      // One answer to one question: choosing replaces rather than adds.
      for (final MenuModifierOption other in group.options) {
        next.remove(other.id);
      }

      next.add(option.id);
    } else if (next.contains(option.id)) {
      next.remove(option.id);
    } else {
      if (state.isFull(group)) {
        // At the ceiling. Refused rather than silently dropping an earlier
        // choice — a customer who tapped four things and sees three should be
        // told which three, not left to work it out.
        return;
      }

      next.add(option.id);
    }

    _configurationChanged();

    state = state.copyWith(selectedOptionIds: next, clearFailure: true);
  }

  void increaseQuantity() {
    if (!state.canIncrease) return;

    _newAttempt();

    state = state.copyWith(quantity: state.quantity + 1, clearFailure: true);
  }

  void decreaseQuantity() {
    if (!state.canDecrease) return;

    _newAttempt();

    state = state.copyWith(quantity: state.quantity - 1, clearFailure: true);
  }

  void noteChanged(String note) {
    final int max = state.customization.limits.maxSpecialInstructions;

    _configurationChanged();

    state = state.copyWith(
      // Clipped rather than refused: the field stops accepting characters, and
      // a customer who pastes a paragraph keeps the beginning of it.
      specialInstructions: note.length > max ? note.substring(0, max) : note,
      clearFailure: true,
    );
  }

  // --- adding --------------------------------------------------------------

  /// Adds the configured dish, or explains why it cannot.
  Future<void> addToCart() async {
    final String? tripId = _tripId;
    final String? restaurantId = _restaurantId;
    final MenuItemPreview? preview = state.preview;

    if (tripId == null || restaurantId == null || preview == null) return;
    if (state.isSubmitting) return;

    if (!state.isComplete) {
      // Answered here rather than by the server, because the customer has not
      // finished and there is nothing to ask about yet. The server checks the
      // same rules again — this is a courtesy, not the guard.
      state = state.copyWith(
        showValidation: true,
        failure: AddToCartFailure.selectionIncomplete,
        invalidGroupId: state.unsatisfiedGroups.firstOrNull?.id,
      );

      return;
    }

    // Reused across retries of this attempt. A lost response followed by a
    // retry is one logical add.
    final String key = _idempotencyKey ??= _mintKey();

    state = state.copyWith(isSubmitting: true, clearFailure: true);

    try {
      final CartAddition addition = await _menus.addToCart(
        tripId: tripId,
        restaurantId: restaurantId,
        itemId: preview.item.id,
        variantId: state.selectedVariantId,
        optionIds: state.selectedOptionIds.toList(),
        quantity: state.quantity,
        specialInstructions: state.specialInstructions,
        quotedUnitPriceMinor: state.previewUnitPrice?.amountMinor,
        idempotencyKey: key,
      );

      if (_disposed) return;

      // Succeeded, so the next add is a new request rather than a retry of
      // this one.
      _idempotencyKey = null;

      state = state.copyWith(
        isSubmitting: false,
        addition: addition,
        cart: addition.cart,
        clearFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      _applyFailure(error);
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isSubmitting: false,
        failure: AddToCartFailure.serverError,
      );
    }
  }

  void _applyFailure(ApiException error) {
    final AddToCartFailure failure = _addFailureFor(error);

    final Object? details = error.details;
    final Map<String, dynamic> map = details is Map<String, dynamic>
        ? details
        : const <String, dynamic>{};

    Money? newPrice;

    if (failure == AddToCartFailure.priceChanged) {
      newPrice = Money.fromJson(map['current_unit_price']);
    }

    state = state.copyWith(
      isSubmitting: false,
      failure: failure,
      failureMessage: error.message,
      invalidGroupId: map['group_id'] as String?,
      priceChangedTo: newPrice,
      showValidation: failure == AddToCartFailure.selectionIncomplete
          ? true
          : state.showValidation,
    );
  }

  /// The customer has seen the new price and wants to go ahead.
  ///
  /// The quote is dropped rather than raised to the new figure: the server
  /// prices it again from its own rows, and the second attempt simply does not
  /// claim to have been shown anything.
  Future<void> acceptNewPrice() async {
    if (state.priceChangedTo == null) return;

    state = state.copyWith(clearFailure: true);

    await _addAcceptingCurrentPrice();
  }

  Future<void> _addAcceptingCurrentPrice() async {
    final String? tripId = _tripId;
    final String? restaurantId = _restaurantId;
    final MenuItemPreview? preview = state.preview;

    if (tripId == null || restaurantId == null || preview == null) return;

    // A different request from the one that was refused, so it gets its own
    // key rather than replaying the refusal.
    final String key = _idempotencyKey = _mintKey();

    state = state.copyWith(isSubmitting: true, clearFailure: true);

    try {
      final CartAddition addition = await _menus.addToCart(
        tripId: tripId,
        restaurantId: restaurantId,
        itemId: preview.item.id,
        variantId: state.selectedVariantId,
        optionIds: state.selectedOptionIds.toList(),
        quantity: state.quantity,
        specialInstructions: state.specialInstructions,
        idempotencyKey: key,
      );

      if (_disposed) return;

      _idempotencyKey = null;

      state = state.copyWith(
        isSubmitting: false,
        addition: addition,
        cart: addition.cart,
        clearFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      _applyFailure(error);
    } catch (_) {
      if (_disposed) return;

      state = state.copyWith(
        isSubmitting: false,
        failure: AddToCartFailure.serverError,
      );
    }
  }

  /// A retry after a network failure. Keeps the key, and keeps the selections.
  Future<void> retryAdd() => addToCart();

  void dismissAddition() => state = state.copyWith(clearAddition: true);

  void dismissFailure() => state = state.copyWith(clearFailure: true);

  Future<void> refreshCart() async {
    final String? tripId = _tripId;

    if (tripId == null) return;

    try {
      final CartSummary cart = await _menus.cart(tripId: tripId);

      if (_disposed) return;

      state = state.copyWith(cart: cart);
    } catch (_) {
      // A badge that cannot be read is a badge that stays as it was. Nothing
      // on this screen depends on it.
    }
  }

  /// The configuration changed, so a pending retry no longer applies to it.
  void _configurationChanged() => _newAttempt();

  void _newAttempt() => _idempotencyKey = null;

  String _mintKey() {
    final int a = _random.nextInt(0x7fffffff);
    final int b = _random.nextInt(0x7fffffff);
    final int now = DateTime.now().microsecondsSinceEpoch;

    return 'cart-$now-$a-$b';
  }

  AddToCartFailure _loadFailureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => AddToCartFailure.network,
    ApiErrorCode.itemNotFound ||
    ApiErrorCode.restaurantNotFound ||
    ApiErrorCode.notFound => AddToCartFailure.notFound,
    ApiErrorCode.restaurantUnavailable ||
    ApiErrorCode.itemUnavailable => AddToCartFailure.soldOut,
    ApiErrorCode.unauthenticated => AddToCartFailure.unauthorized,
    ApiErrorCode.serverError => AddToCartFailure.serverError,
    _ => AddToCartFailure.unknown,
  };

  AddToCartFailure _addFailureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => AddToCartFailure.network,
    ApiErrorCode.itemSoldOut ||
    ApiErrorCode.variantUnavailable ||
    ApiErrorCode.modifierUnavailable ||
    ApiErrorCode.itemUnavailable => AddToCartFailure.soldOut,
    ApiErrorCode.variantRequired ||
    ApiErrorCode.variantInvalid ||
    ApiErrorCode.modifierRequired ||
    ApiErrorCode.modifierMinNotMet ||
    ApiErrorCode.modifierMaxExceeded ||
    ApiErrorCode.modifierInvalid => AddToCartFailure.selectionIncomplete,
    ApiErrorCode.quantityInvalid ||
    ApiErrorCode.quantityLimitExceeded => AddToCartFailure.quantityRefused,
    ApiErrorCode.specialInstructionsTooLong => AddToCartFailure.noteRefused,
    ApiErrorCode.restaurantNotAcceptingOrders =>
      AddToCartFailure.notAcceptingOrders,
    ApiErrorCode.cartRestaurantConflict ||
    ApiErrorCode.cartTripConflict => AddToCartFailure.cartConflict,
    ApiErrorCode.priceUpdated => AddToCartFailure.priceChanged,
    ApiErrorCode.itemNotFound ||
    ApiErrorCode.restaurantNotFound ||
    ApiErrorCode.notFound => AddToCartFailure.notFound,
    ApiErrorCode.unauthenticated => AddToCartFailure.unauthorized,
    ApiErrorCode.serverError => AddToCartFailure.serverError,
    _ => AddToCartFailure.unknown,
  };
}

/// Auto-disposed: one dish's configuration belongs to one visit to one screen.
final itemCustomizationControllerProvider =
    NotifierProvider.autoDispose<
      ItemCustomizationController,
      CustomizationState
    >(ItemCustomizationController.new);
