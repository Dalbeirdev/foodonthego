import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/pickup.dart';
import '../../domain/models/pre_checkout.dart';
import '../../shared/state/pickup_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/fotg_card.dart';
import '../cart/widgets/cart_notice.dart';
import 'widgets/pickup_explanation_card.dart';
import 'widgets/pickup_time_chip.dart';

/// Choosing when to collect.
///
/// **Not one time on this screen was worked out here.** The windows, the
/// recommendation, the arrival estimate, the preparation minutes, whether a
/// chosen time still stands and whether the order could be paid for all arrived
/// from the server. This screen formats instants and renders judgements; it
/// makes none.
///
/// That is not fastidiousness. A client that could decide a pickup window would
/// be a second answer to a question that must have exactly one, and the day the
/// two disagree a customer is sent to a counter with nothing on it.
///
/// The clock is the server's too. `plan.serverNow` comes with every response
/// precisely so nothing here has to consult the device, whose owner may have
/// set it to anything.
class PickupTimeScreen extends ConsumerStatefulWidget {
  const PickupTimeScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<PickupTimeScreen> createState() => _PickupTimeScreenState();
}

class _PickupTimeScreenState extends ConsumerState<PickupTimeScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pickupControllerProvider.notifier).open(tripId: widget.tripId);
    });
  }

  /// A moment on the counter's clock.
  ///
  /// Takes the *local* fields the models keep beside each instant, never the
  /// instant itself. `DateTime.parse` discards the offset the server sent, so a
  /// formatted instant is either UTC or the phone's zone — and a Delhi pickup
  /// read on a phone set to London says 8:10 am when the door says 1:40 pm.
  ///
  /// So there is no `toLocal` here and no timezone arithmetic of any kind. The
  /// server decided the offset, daylight saving included; this renders what it
  /// decided.
  String _time(DateTime moment) {
    final int hour = moment.hour;
    final String minute = moment.minute.toString().padLeft(2, '0');

    final String period = hour < 12 ? 'am' : 'pm';
    final int twelve = hour % 12 == 0 ? 12 : hour % 12;

    return '$twelve:$minute $period';
  }

  String _window(AppStrings strings, PickupOption option) => strings
      .pickupWindow(_time(option.localStartAt), _time(option.localEndAt));

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final PickupState state = ref.watch(pickupControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.pickupTitle)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(pickupControllerProvider.notifier).refresh(),
          child: _body(strings, state),
        ),
      ),
    );
  }

  Widget _body(AppStrings strings, PickupState state) {
    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.loadFailure case final PickupFailure failure) {
      return _failureView(strings, failure);
    }

    return ListView(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      children: <Widget>[
        if (state.isOffline)
          _notice(
            strings.pickupOfflineTitle,
            strings.pickupOfflineBody,
            CartNoticeTone.advisory,
          ),
        ..._selectionNotices(strings, state),
        if (state.failure case final PickupFailure failure)
          _editNotice(strings, failure, state.failureMessage),
        if (state.plan.requiresRouteRefresh && state.options.isNotEmpty)
          _notice(
            strings.pickupRouteStaleTitle,
            strings.pickupRouteStaleBody,
            CartNoticeTone.blocking,
          ),
        if (state.selection.status.isUsable && state.selection.hasWindow)
          _selectedCard(strings, state),
        if (state.options.isNotEmpty) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          Text(
            strings.pickupChoose,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FotgSpacing.x3),
          _chips(strings, state),
          const SizedBox(height: FotgSpacing.x5),
          PickupExplanationCard(plan: state.plan, formatTime: _time),
          const SizedBox(height: FotgSpacing.x5),
          _checkButton(strings, state),
        ] else if (state.hasLoaded)
          _noWindowsView(strings, state),
        if (state.preCheckout case final PreCheckoutResult result) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          _preCheckoutCard(strings, result),
          if (result.readyForCheckout) ...<Widget>[
            const SizedBox(height: FotgSpacing.x4),
            _continueToCheckout(strings),
          ],
        ],
      ],
    );
  }

  Widget _chips(AppStrings strings, PickupState state) {
    final String? selected = state.selectedOptionId;

    return Wrap(
      spacing: FotgSpacing.x2,
      runSpacing: FotgSpacing.x2,
      children: <Widget>[
        for (final PickupOption option in state.options)
          PickupTimeChip(
            key: ValueKey<String>('pickup-option-${option.id}'),
            label: _window(strings, option),
            isSelected: option.id == selected,
            isRecommended: option.isRecommended,
            recommendedLabel: strings.pickupRecommended,
            isBusy: state.selectingOptionId == option.id,
            // The id, and only the id. The label above is what a customer
            // reads; this is what the server is told, and the two never swap.
            onPressed: state.selectingOptionId == null
                ? () => ref
                      .read(pickupControllerProvider.notifier)
                      .choose(option.id)
                : null,
          ),
      ],
    );
  }

  Widget _selectedCard(AppStrings strings, PickupState state) {
    final DateTime start = state.selection.localStartAt!;
    final DateTime end = state.selection.localEndAt!;

    return Padding(
      padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
      child: FotgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.pickupSelectedTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              strings.pickupSelectedFor(
                strings.pickupWindow(_time(start), _time(end)),
              ),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  /// What the server says has become of the customer's choice.
  ///
  /// Read from `selection.status`, which the backend derives on every response.
  /// The screen does not compare a stored time against the clock to decide
  /// whether a choice has expired — that comparison belongs to the side that
  /// knows the restaurant's hours and the route's age.
  List<Widget> _selectionNotices(AppStrings strings, PickupState state) =>
      switch (state.selection.status) {
        PickupSelectionStatus.stale => <Widget>[
          _notice(
            strings.pickupStaleTitle,
            strings.pickupStaleBody,
            CartNoticeTone.advisory,
          ),
        ],
        PickupSelectionStatus.invalid => <Widget>[
          _notice(
            strings.pickupInvalidTitle,
            strings.pickupInvalidBody,
            CartNoticeTone.advisory,
          ),
        ],
        PickupSelectionStatus.none ||
        PickupSelectionStatus.selected => const <Widget>[],
      };

  Widget _editNotice(
    AppStrings strings,
    PickupFailure failure,
    String? message,
  ) {
    final (String title, String body, CartNoticeTone tone) = switch (failure) {
      PickupFailure.optionExpired => (
        strings.pickupExpired,
        strings.pickupChoose,
        CartNoticeTone.advisory,
      ),
      PickupFailure.optionStale => (
        strings.pickupStaleTitle,
        strings.pickupStaleBody,
        CartNoticeTone.advisory,
      ),
      PickupFailure.notAcceptingOrders => (
        strings.pickupKitchenClosedTitle,
        strings.pickupKitchenClosedBody,
        CartNoticeTone.blocking,
      ),
      PickupFailure.restaurantUnavailable => (
        strings.pickupOffRouteTitle,
        strings.pickupOffRouteBody,
        CartNoticeTone.blocking,
      ),
      PickupFailure.routeStale => (
        strings.pickupRouteStaleTitle,
        strings.pickupRouteStaleBody,
        CartNoticeTone.blocking,
      ),
      _ => (
        strings.pickupChoiceFailed,
        // The server's own words where it gave any, and never a code. A
        // customer reading PICKUP_OPTION_STALE has learnt nothing.
        message ?? strings.pickupLoadFailedBody,
        CartNoticeTone.blocking,
      ),
    };

    return _notice(title, body, tone);
  }

  Widget _notice(String title, String body, CartNoticeTone tone) => Padding(
    padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
    child: CartNotice(title: title, body: body, tone: tone),
  );

  Widget _checkButton(AppStrings strings, PickupState state) => PrimaryButton(
    key: const ValueKey<String>('pickup-check-order'),
    label: state.isValidating
        ? strings.pickupCheckingOrder
        : strings.pickupCheckOrder,
    onPressed: state.isValidating || state.selectedOptionId == null
        ? null
        : () => ref.read(pickupControllerProvider.notifier).validate(),
  );

  /// Module 14's entry point.
  ///
  /// Shown only once the **server** has said this order may be checked out, and
  /// only after the customer has asked it — the button appears beneath the
  /// verdict rather than beside the chips, so nothing offers to price a basket
  /// the backend has not agreed to price. The checkout screen asks again on
  /// arrival regardless: this screen's answer is a moment old by the time the
  /// next one loads, and a stale yes is exactly the kind that costs money.
  Widget _continueToCheckout(AppStrings strings) => PrimaryButton(
    key: const ValueKey<String>('pickup-continue-checkout'),
    label: strings.checkoutOpen,
    onPressed: () => context.push(Routes.tripCheckoutPath(widget.tripId)),
  );

  /// The server's verdict, rendered.
  ///
  /// `readyForCheckout` is read from the response. It is deliberately **not**
  /// derived from whether the issue list happens to be empty: a build that
  /// worked it out that way would say yes to an issue it had never heard of,
  /// which is exactly the case where saying yes is worst.
  Widget _preCheckoutCard(AppStrings strings, PreCheckoutResult result) =>
      FotgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  result.readyForCheckout
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: result.readyForCheckout
                      ? FotgColors.success
                      : FotgColors.warning,
                ),
                const SizedBox(width: FotgSpacing.x3),
                Expanded(
                  child: Text(
                    result.readyForCheckout
                        ? strings.pickupReadyTitle
                        : strings.pickupNotReadyTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FotgSpacing.x3),
            if (result.readyForCheckout && result.issues.isEmpty)
              Text(
                strings.pickupReadyBody,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            // Blockers first, then the rest. A price that has fallen is worth
            // telling somebody about and is not in their way.
            for (final PreCheckoutIssue issue in <PreCheckoutIssue>[
              ...result.blockers,
              ...result.notices,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: FotgSpacing.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      issue.blocking
                          ? Icons.remove_circle_outline
                          : Icons.info_outline,
                      size: 18,
                      color: issue.blocking
                          ? FotgColors.error
                          : FotgColors.neutral500,
                    ),
                    const SizedBox(width: FotgSpacing.x3),
                    Expanded(
                      // The server's wording. An unknown code still reaches the
                      // customer as a sentence, because the message came with
                      // it rather than being looked up from the code.
                      child: Text(
                        issue.message,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _noWindowsView(AppStrings strings, PickupState state) {
    final (String title, String body) = switch (state.plan.reason) {
      'ROUTE_STALE' || 'ROUTE_NOT_READY' => (
        strings.pickupRouteStaleTitle,
        strings.pickupRouteStaleBody,
      ),
      'RESTAURANT_NOT_ACCEPTING_ORDERS' => (
        strings.pickupKitchenClosedTitle,
        strings.pickupKitchenClosedBody,
      ),
      'RESTAURANT_OUTSIDE_ROUTE' || 'RESTAURANT_UNAVAILABLE' => (
        strings.pickupOffRouteTitle,
        strings.pickupOffRouteBody,
      ),
      _ => (strings.pickupNoneTitle, strings.pickupNoneBody),
    };

    return EmptyStateView(
      icon: Icons.schedule_outlined,
      title: title,
      body: body,
    );
  }

  Widget _failureView(AppStrings strings, PickupFailure failure) {
    final (String title, String body) = switch (failure) {
      PickupFailure.tripGone => (
        strings.cartTripGoneTitle,
        strings.cartTripGoneBody,
      ),
      PickupFailure.cartGone || PickupFailure.cartEmpty => (
        strings.cartEmptyTitle,
        strings.cartEmptyBody,
      ),
      PickupFailure.routeStale => (
        strings.pickupRouteStaleTitle,
        strings.pickupRouteStaleBody,
      ),
      _ => (strings.pickupLoadFailedTitle, strings.pickupLoadFailedBody),
    };

    return EmptyStateView(
      icon: Icons.schedule_outlined,
      title: title,
      body: body,
      action: SecondaryButton(
        label: strings.pickupRetry,
        onPressed: () => ref.read(pickupControllerProvider.notifier).retry(),
      ),
    );
  }
}
