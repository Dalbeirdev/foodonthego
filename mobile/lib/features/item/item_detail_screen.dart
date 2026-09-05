import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/menu_customization.dart';
import '../../domain/models/money.dart';
import '../../domain/models/restaurant_menu.dart';
import '../../shared/state/item_customization_controller.dart';
import '../menu/widgets/menu_item_badges.dart';
import 'widgets/modifier_group_section.dart';
import 'widgets/quantity_stepper.dart';
import 'widgets/special_instructions_field.dart';
import 'widgets/sticky_add_bar.dart';
import 'widgets/variant_selector.dart';

/// Configuring one dish.
///
/// The customer says what they want; the server decides what it costs. The
/// price on the button moves the instant anything is tapped, and it is a
/// **preview** — what they are charged is what the server calculates when they
/// add, and the two disagree only if the menu changed underneath them, which is
/// the case the price-change confirmation exists for.
///
/// Nothing on this screen invents anything. A dish with no sizes gets no size
/// selector, not a fabricated "Regular". A question with no answers is not
/// drawn. A rule is stated above the options rather than discovered by being
/// refused.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({
    required this.tripId,
    required this.restaurantId,
    required this.itemId,
    super.key,
    this.itemName,
  });

  final String tripId;
  final String restaurantId;
  final String itemId;

  /// What the menu card already knew, so the app bar has a title during the
  /// first request rather than a blank space.
  final String? itemName;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final ScrollController _scroll = ScrollController();

  /// One key per group heading, so an unanswered question can be scrolled to
  /// rather than merely complained about.
  final Map<String, GlobalKey> _groupKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(itemCustomizationControllerProvider.notifier)
          .open(
            tripId: widget.tripId,
            restaurantId: widget.restaurantId,
            itemId: widget.itemId,
          );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ItemCustomizationController controller = ref.read(
      itemCustomizationControllerProvider.notifier,
    );

    await controller.addToCart();

    if (!mounted) return;

    final CustomizationState state = ref.read(
      itemCustomizationControllerProvider,
    );

    // An unanswered question is scrolled to rather than described. "Choose 1
    // option to continue" halfway up a screen the customer cannot see is not
    // an explanation.
    if (state.invalidGroupId case final String groupId) {
      await _scrollToGroup(groupId);

      return;
    }

    if (state.addition != null) {
      _confirmAdded(state);
    }
  }

  Future<void> _scrollToGroup(String groupId) async {
    final BuildContext? target = _groupKeys[groupId]?.currentContext;

    if (target == null || !target.mounted) return;

    await Scrollable.ensureVisible(
      target,
      duration: FotgMotion.respectingReducedMotion(context, FotgMotion.normal),
      curve: FotgMotion.decelerate,
      alignment: 0.1,
    );
  }

  /// Subtle, and not a celebration. The customer is mid-task.
  void _confirmAdded(CustomizationState state) {
    final AppStrings strings = AppStrings.of(context);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${strings.itemAddedToCart} · '
            '${strings.itemAddedToCartCount(state.cart.itemCount)}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: strings.itemViewCart,
            // Module 12 owns the cart screen. Saying so is honest; opening a
            // half-built one would not be.
            onPressed: () => ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(content: Text(strings.itemViewCartSoon))),
          ),
        ),
      );

    ref.read(itemCustomizationControllerProvider.notifier).dismissAddition();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final CustomizationState state = ref.watch(
      itemCustomizationControllerProvider,
    );

    final String title =
        state.item?.name ?? widget.itemName ?? strings.itemDetailTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        // The AppBar's automatic back button pops the Navigator without telling
        // go_router, which leaves the router with an empty match list.
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        bottom: false,
        child: switch (state) {
          // The failure first: a screen that has nothing *and* a reason should
          // show the reason.
          CustomizationState(loadFailure: final AddToCartFailure failure)
              when !state.hasLoaded =>
            _LoadFailure(failure: failure),

          // Nothing loaded and no reason — either the request is in flight or
          // it has not started, which is the first frame before the post-frame
          // callback runs. Both are a wait, and neither has a preview to draw.
          CustomizationState(preview: final MenuItemPreview loaded) => _Loaded(
            preview: loaded,
            state: state,
            scroll: _scroll,
            groupKeys: _groupKeys,
          ),
          _ => const _Loading(),
        },
      ),
      bottomNavigationBar: state.hasLoaded
          ? StickyAddBar(state: state, onAdd: _add)
          : null,
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    // A skeleton in the shape of the answer, not a spinner in the middle of
    // nothing: the screen the customer is waiting for has a picture, a name, a
    // price and some choices, and showing that shape makes the wait shorter.
    return ListView(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      children: <Widget>[
        const _SkeletonBox(height: 180),
        const SizedBox(height: FotgSpacing.x4),
        const _SkeletonBox(height: 24, width: 200),
        const SizedBox(height: FotgSpacing.x2),
        const _SkeletonBox(height: 18, width: 90),
        const SizedBox(height: FotgSpacing.x6),
        for (int i = 0; i < 3; i++) ...<Widget>[
          const _SkeletonBox(height: 16, width: 140),
          const SizedBox(height: FotgSpacing.x3),
          const _SkeletonBox(height: 44),
          const SizedBox(height: FotgSpacing.x2),
          const _SkeletonBox(height: 44),
          const SizedBox(height: FotgSpacing.x5),
        ],
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: FotgColors.neutral100,
        borderRadius: FotgRadius.control,
      ),
    ),
  );
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.preview,
    required this.state,
    required this.scroll,
    required this.groupKeys,
  });

  /// Passed in rather than read back off the state, so this widget has no `!`
  /// in it and cannot be built without something to draw.
  final MenuItemPreview preview;

  final CustomizationState state;
  final ScrollController scroll;
  final Map<String, GlobalKey> groupKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final ItemCustomizationController controller = ref.read(
      itemCustomizationControllerProvider.notifier,
    );

    final MenuItem item = preview.item;
    final MenuItemCustomization customization = state.customization;

    final Set<String> unsatisfied = state.showValidation
        ? <String>{
            for (final MenuModifierGroup g in state.unsatisfiedGroups) g.id,
          }
        : const <String>{};

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: FotgSpacing.x10),
      children: <Widget>[
        _Hero(item: item),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x4,
            FotgSpacing.x4,
            FotgSpacing.x4,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.name,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: FotgSpacing.x2),

              // The base price, before any choices. The running total lives on
              // the button, where the customer is looking when they commit.
              Semantics(
                container: true,
                label: item.price.spokenLabel(),
                excludeSemantics: true,
                child: Text(
                  item.price.format(),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),

              if (item.hasDescription) ...<Widget>[
                const SizedBox(height: FotgSpacing.x3),
                Text(
                  item.description!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: FotgColors.neutral600),
                ),
              ],

              const SizedBox(height: FotgSpacing.x4),
              MenuItemBadges(item: item),

              if (item.isSoldOut) ...<Widget>[
                const SizedBox(height: FotgSpacing.x4),
                _Notice(
                  icon: Icons.remove_shopping_cart_outlined,
                  title: strings.itemSoldOutTitle,
                  body: strings.itemSoldOutBody,
                  foreground: FotgColors.error,
                  background: FotgColors.errorSurface,
                ),
              ] else if (!preview.restaurant.canOrder) ...<Widget>[
                const SizedBox(height: FotgSpacing.x4),
                _Notice(
                  icon: Icons.schedule_outlined,
                  title: strings.itemNotAcceptingTitle,
                  body: strings.itemNotAcceptingBody,
                  foreground: FotgColors.warning,
                  background: FotgColors.warningSurface,
                ),
              ],

              // Sizes, only where the dish has them. No fabricated "Regular".
              if (customization.hasVariants) ...<Widget>[
                const SizedBox(height: FotgSpacing.x6),
                VariantSelector(
                  variants: customization.variants,
                  selectedId: state.selectedVariantId,
                  onSelected: controller.selectVariant,
                  required: state.showValidation && state.needsVariant,
                ),
              ],

              for (final MenuModifierGroup group
                  in customization.modifierGroups) ...<Widget>[
                const SizedBox(height: FotgSpacing.x6),
                KeyedSubtree(
                  key: groupKeys.putIfAbsent(group.id, GlobalKey.new),
                  child: ModifierGroupSection(
                    group: group,
                    selectedIds: state.selectedOptionIds,
                    onToggle: controller.toggleOption,
                    isUnsatisfied: unsatisfied.contains(group.id),
                  ),
                ),
              ],

              const SizedBox(height: FotgSpacing.x6),
              QuantityStepper(
                quantity: state.quantity,
                canDecrease: state.canDecrease,
                canIncrease: state.canIncrease,
                onDecrease: controller.decreaseQuantity,
                onIncrease: controller.increaseQuantity,
                maxQuantity: customization.limits.maxQuantity,
              ),

              const SizedBox(height: FotgSpacing.x6),
              SpecialInstructionsField(
                text: state.specialInstructions,
                onChanged: controller.noteChanged,
                maxLength: customization.limits.maxSpecialInstructions,
                remaining: state.noteRemaining,
              ),

              if (state.failure
                  case final AddToCartFailure failure) ...<Widget>[
                const SizedBox(height: FotgSpacing.x5),
                _FailureNotice(failure: failure, state: state),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The dish's own photograph, or nothing.
///
/// The same rule as the menu list: there is no stock-image fallback anywhere in
/// this app, because a generic curry standing in for an unphotographed dish is
/// a claim about what arrives in the box.
class _Hero extends StatelessWidget {
  const _Hero({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final String? url = item.imageUrl;

    if (url == null) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => Container(
          color: FotgColors.neutral100,
          child: const Icon(
            Icons.restaurant_outlined,
            color: FotgColors.neutral400,
          ),
        ),
      ),
    );
  }
}

/// What went wrong, and the move that fixes it.
class _FailureNotice extends ConsumerWidget {
  const _FailureNotice({required this.failure, required this.state});

  final AddToCartFailure failure;
  final CustomizationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final ItemCustomizationController controller = ref.read(
      itemCustomizationControllerProvider.notifier,
    );

    // The price-change refusal is its own thing: nothing is wrong, and the
    // customer needs both figures and a decision, not an apology.
    if (failure == AddToCartFailure.priceChanged) {
      final Money? now = state.priceChangedTo;
      final Money? was = state.previewUnitPrice;

      return _Notice(
        icon: Icons.price_change_outlined,
        title: strings.itemPriceChangedTitle,
        body: (was != null && now != null)
            ? strings.itemPriceChangedBody(was.format(), now.format())
            : strings.itemAddFailedBody,
        foreground: FotgColors.info,
        background: FotgColors.infoSurface,
        actions: <Widget>[
          if (now != null)
            FilledButton(
              onPressed: controller.acceptNewPrice,
              child: Text(strings.itemPriceChangedAccept(now.format())),
            ),
          TextButton(
            onPressed: controller.dismissFailure,
            child: Text(strings.itemPriceChangedCancel),
          ),
        ],
      );
    }

    final (String title, String body, bool retryable) = switch (failure) {
      AddToCartFailure.selectionIncomplete => (
        strings.itemAddFailedTitle,
        state.failureMessage ?? strings.itemAddFailedBody,
        false,
      ),
      AddToCartFailure.soldOut => (
        strings.itemSoldOutTitle,
        strings.itemSoldOutBody,
        false,
      ),
      AddToCartFailure.notAcceptingOrders => (
        strings.itemNotAcceptingTitle,
        strings.itemNotAcceptingBody,
        false,
      ),
      AddToCartFailure.cartConflict => (
        strings.itemCartConflictTitle,
        state.failureMessage ??
            strings.itemCartConflictBody(state.cart.restaurantName ?? ''),
        false,
      ),
      AddToCartFailure.network || AddToCartFailure.offline => (
        strings.itemOfflineTitle,
        strings.itemOfflineBody,
        true,
      ),
      AddToCartFailure.quantityRefused || AddToCartFailure.noteRefused => (
        strings.itemAddFailedTitle,
        state.failureMessage ?? strings.itemAddFailedBody,
        false,
      ),
      _ => (strings.itemAddFailedTitle, strings.itemAddFailedBody, true),
    };

    return _Notice(
      icon: Icons.error_outline_rounded,
      title: title,
      body: body,
      foreground: FotgColors.error,
      background: FotgColors.errorSurface,
      actions: <Widget>[
        // Offered only where trying again could work. A sold-out dish will not
        // come back because somebody pressed a button.
        if (retryable)
          FilledButton(
            onPressed: controller.retryAdd,
            child: Text(strings.itemAddRetry),
          ),
      ],
    );
  }
}

class _LoadFailure extends ConsumerWidget {
  const _LoadFailure({required this.failure});

  final AddToCartFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final bool gone =
        failure == AddToCartFailure.notFound ||
        failure == AddToCartFailure.soldOut;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: FotgColors.neutral400,
              ),
            ),
            const SizedBox(height: FotgSpacing.x4),
            Text(
              gone ? strings.itemGoneTitle : strings.itemLoadFailedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              gone ? strings.menuItemGoneBody : strings.itemAddFailedBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: FotgColors.neutral600),
            ),
            const SizedBox(height: FotgSpacing.x5),
            if (gone)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.menuBackToRestaurant),
              )
            else
              FilledButton(
                onPressed: ref
                    .read(itemCustomizationControllerProvider.notifier)
                    .retryLoad,
                child: Text(strings.itemAddRetry),
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    required this.foreground,
    required this.background,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String body;
  final Color foreground;
  final Color background;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: FotgRadius.control,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(child: Icon(icon, size: 18, color: foreground)),
              const SizedBox(width: FotgSpacing.x2),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FotgSpacing.x2),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: FotgColors.neutral800,
            ),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: FotgSpacing.x3),
            Wrap(spacing: FotgSpacing.x2, children: actions),
          ],
        ],
      ),
    );
  }
}
