import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/cart_revalidation.dart';
import '../../shared/state/cart_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/fotg_card.dart';
import 'widgets/cart_line_tile.dart';
import 'widgets/cart_notice.dart';
import 'widgets/order_summary_card.dart';

/// What the customer has chosen, what it costs, and how to change it.
///
/// The screen Module 11 deliberately did not build. Three jobs, in the order a
/// customer does them: check that what is here is what they meant, correct it
/// if not, and understand what they will pay.
///
/// **No figure on this screen is calculated here.** Every price, every charge
/// and the total came from the server in the response to the request that
/// changed them. A client that adjusted its own subtotal after a quantity
/// change would be right most days and wrong on the day a price moved
/// underneath it — and this is the screen where the customer decides what to
/// spend.
///
/// Edits are not optimistic. A stepper that moves before the server has agreed
/// shows a quantity the cart may not have. The line being changed disables its
/// own controls; the rest of the cart stays usable.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartControllerProvider.notifier).open(tripId: widget.tripId);
    });
  }

  /// Emptying is destructive, so it is confirmed — and the confirmation says
  /// what will happen rather than asking "are you sure".
  Future<void> _confirmEmpty() async {
    final AppStrings strings = AppStrings.of(context);

    final bool? empty = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(strings.cartEmptyConfirmTitle),
        content: Text(strings.cartEmptyConfirmBody),
        actions: <Widget>[
          // "Keep it" first and unstyled; the destructive action is the one
          // that has to be reached for.
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cartKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: FotgColors.error),
            child: Text(strings.cartEmptyConfirmAction),
          ),
        ],
      ),
    );

    if (empty != true || !mounted) return;

    await ref.read(cartControllerProvider.notifier).empty();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final CartState state = ref.watch(cartControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.cartTitle),
        // The AppBar's automatic back button pops the Navigator without telling
        // go_router, which leaves the router with an empty match list.
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: <Widget>[
          if (!state.isEmpty)
            TextButton(
              onPressed: state.isBusy ? null : _confirmEmpty,
              child: Text(strings.cartEmptyCart),
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: switch (state) {
          // Nothing on screen and a reason: show the reason.
          CartState(loadFailure: final CartFailure failure)
              when state.isEmpty =>
            _LoadFailure(
              failure: failure,
              onRetry: () => ref.read(cartControllerProvider.notifier).retry(),
            ),

          // Loaded, and there is nothing in it. Not a failure: a customer who
          // has added nothing has a cart with nothing in it.
          CartState(hasLoaded: true) when state.isEmpty => _Empty(
            tripId: widget.tripId,
          ),

          CartState(cart: final Cart cart) => _Loaded(
            cart: cart,
            state: state,
            onRefresh: () =>
                ref.read(cartControllerProvider.notifier).refresh(),
          ),

          // Before the first frame's callback has run, and while the first
          // request is in flight. Both are a wait.
          _ => const _Loading(),
        },
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.cart,
    required this.state,
    required this.onRefresh,
  });

  final Cart cart;
  final CartState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final CartController controller = ref.read(cartControllerProvider.notifier);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          FotgSpacing.x4,
          FotgSpacing.x4,
          FotgSpacing.x4,
          FotgSpacing.x8,
        ),
        children: <Widget>[
          if (state.isOffline) ...<Widget>[
            CartNotice(
              title: strings.cartOfflineTitle,
              body: strings.cartOfflineBody,
              tone: CartNoticeTone.neutral,
              action: LinkAction(
                label: strings.cartRecheck,
                onPressed: controller.retry,
              ),
            ),
            const SizedBox(height: FotgSpacing.x4),
          ],

          if (_notice(strings, state) case final CartNotice notice) ...<Widget>[
            notice,
            const SizedBox(height: FotgSpacing.x4),
          ],

          if (cart.restaurantName case final String name) ...<Widget>[
            Text(
              strings.cartFrom(name),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: FotgSpacing.x1),
            Text(
              strings.cartItemCount(state.itemCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: FotgColors.neutral600,
              ),
            ),
            const SizedBox(height: FotgSpacing.x4),
          ],

          FotgCard(
            padding: const EdgeInsets.symmetric(horizontal: FotgSpacing.x5),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < cart.lines.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  CartLineTile(
                    line: cart.lines[i],
                    verdict: state.verdictFor(cart.lines[i].id),
                    isBusy: state.busyLineId == cart.lines[i].id,
                    isEnabled: !state.isBusy,
                    failureMessage: state.failedLineId == cart.lines[i].id
                        ? _editMessage(strings, state)
                        : null,
                    onDecrease: () => controller.decrement(cart.lines[i]),
                    onIncrease: () => controller.increment(cart.lines[i]),
                    onRemove: () => controller.removeLine(cart.lines[i].id),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: FotgSpacing.x4),

          FotgCard(child: OrderSummaryCard(totals: cart.totals)),
        ],
      ),
    );
  }

  /// The one banner worth showing, if any.
  ///
  /// A closed kitchen outranks a price change, which outranks nothing at all: a
  /// customer who cannot order here does not need to be told the paneer went up
  /// by ten rupees first.
  CartNotice? _notice(AppStrings strings, CartState state) {
    final CartRevalidation? verdict = state.revalidation;

    if (verdict == null) return null;

    if (!verdict.restaurantAcceptingOrders) {
      return CartNotice(
        title: strings.cartKitchenClosedTitle,
        body: strings.cartKitchenClosedBody,
        tone: CartNoticeTone.blocking,
      );
    }

    if (verdict.hasBlockingProblem) {
      return CartNotice(
        title: strings.cartNeedsAttentionTitle,
        body: strings.cartNeedsAttentionBody,
        tone: CartNoticeTone.blocking,
      );
    }

    if (verdict.problems.isNotEmpty) {
      return CartNotice(
        title: strings.cartPricesChangedTitle,
        body: strings.cartPricesChangedBody,
        tone: CartNoticeTone.advisory,
      );
    }

    return null;
  }

  /// What to say about an edit that did not take.
  ///
  /// The server's own wording is used for the codes the app recognises — they
  /// are written for customers — and the app's own for everything else, because
  /// a message written for a developer helps nobody in a car.
  String _editMessage(AppStrings strings, CartState state) =>
      switch (state.failure) {
        CartFailure.priceChanged =>
          state.failureMessage ?? strings.cartPriceChangedNow,
        CartFailure.quantityRefused =>
          state.failureMessage ?? strings.cartQuantityRefused,
        CartFailure.lineGone => strings.cartLineGone,
        CartFailure.unavailable =>
          state.failureMessage ?? strings.cartUnavailableHere,
        CartFailure.network || CartFailure.offline => strings.cartEditOffline,
        _ => strings.cartEditFailed,
      };
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return EmptyStateView(
      icon: Icons.shopping_basket_outlined,
      title: strings.cartEmptyTitle,
      body: strings.cartEmptyBody,
      action: PrimaryButton(
        label: strings.cartEmptyAction,
        expand: false,
        // Back to the restaurants on this journey's route, which is where
        // something to add actually comes from. "Browse" with nowhere to browse
        // is a dead end dressed as a suggestion.
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.failure, required this.onRetry});

  final CartFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final (IconData icon, String title, String body) = switch (failure) {
      CartFailure.network || CartFailure.offline => (
        Icons.wifi_off_rounded,
        strings.cartOfflineTitle,
        strings.cartOfflineBody,
      ),
      CartFailure.tripGone => (
        Icons.explore_off_outlined,
        strings.cartTripGoneTitle,
        strings.cartTripGoneBody,
      ),
      _ => (
        Icons.error_outline_rounded,
        strings.cartLoadFailedTitle,
        strings.cartLoadFailedBody,
      ),
    };

    return EmptyStateView(
      icon: icon,
      title: title,
      body: body,
      // A journey that is gone does not come back by asking again. Offering a
      // retry that cannot work is worse than offering none.
      action: failure == CartFailure.tripGone
          ? null
          : PrimaryButton(
              label: strings.cartRetry,
              expand: false,
              onPressed: onRetry,
            ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    // A skeleton in the shape of the answer rather than a spinner in the middle
    // of nothing: the screen being waited for is a list of lines and a summary,
    // and showing that shape makes the wait shorter.
    return ListView(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      children: <Widget>[
        const _SkeletonBox(height: 20, width: 180),
        const SizedBox(height: FotgSpacing.x2),
        const _SkeletonBox(height: 14, width: 90),
        const SizedBox(height: FotgSpacing.x5),
        for (int i = 0; i < 3; i++) ...<Widget>[
          const _SkeletonBox(height: 72),
          const SizedBox(height: FotgSpacing.x3),
        ],
        const SizedBox(height: FotgSpacing.x4),
        const _SkeletonBox(height: 140),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: FotgColors.neutral200,
        borderRadius: FotgRadius.control,
      ),
    );
  }
}
