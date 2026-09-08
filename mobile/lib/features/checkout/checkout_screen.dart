import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/checkout.dart';
import '../../domain/models/pre_checkout.dart';
import '../../shared/state/checkout_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/fotg_card.dart';
import '../cart/widgets/cart_notice.dart';
import 'widgets/commercial_summary_card.dart';

/// The last screen before money, and the one that stops short of it.
///
/// **Not one figure here is worked out by this screen.** The subtotal, every
/// charge, the payable total and whether the order may be paid for all arrived
/// from the server. A client that could produce its own total would be a second
/// answer to a question that must have exactly one — and this is the screen
/// where a customer agrees to a number.
///
/// Payment itself is Module 15. The button is present and honest about that
/// rather than hidden: a customer who reaches the end of a checkout and finds
/// nothing assumes the app is broken, and an unusable control that looks usable
/// is worse still.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checkoutControllerProvider.notifier).open(tripId: widget.tripId);
    });
  }

  /// A moment on the counter's clock, formatted from what the server sent.
  String _time(DateTime moment) {
    final int hour = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
    final String minute = moment.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${moment.hour < 12 ? 'am' : 'pm'}';
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final CheckoutState state = ref.watch(checkoutControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.checkoutTitle)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(checkoutControllerProvider.notifier).refresh(),
          child: _body(strings, state),
        ),
      ),
    );
  }

  Widget _body(AppStrings strings, CheckoutState state) {
    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.loadFailure != null) {
      return EmptyStateView(
        icon: Icons.receipt_long_outlined,
        title: strings.checkoutLoadFailedTitle,
        body: strings.checkoutLoadFailedBody,
        action: SecondaryButton(
          label: strings.checkoutRetry,
          onPressed: () =>
              ref.read(checkoutControllerProvider.notifier).retry(),
        ),
      );
    }

    final Checkout? checkout = state.checkout;

    if (checkout == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        FotgSpacing.x4,
        FotgSpacing.x4,
        FotgSpacing.x8,
      ),
      children: <Widget>[
        // The quote's own state first. A customer looking at a price that has
        // expired needs to know before they read the rest of it.
        if (state.hasExpired)
          _notice(
            strings.checkoutExpiredTitle,
            strings.checkoutExpiredBody,
            CartNoticeTone.advisory,
            action: LinkAction(
              label: strings.checkoutRefresh,
              onPressed: () =>
                  ref.read(checkoutControllerProvider.notifier).refresh(),
            ),
          ),

        if (state.isStale)
          _notice(
            strings.checkoutStaleTitle,
            strings.checkoutStaleBody,
            CartNoticeTone.advisory,
            action: LinkAction(
              label: strings.checkoutRefresh,
              onPressed: () =>
                  ref.read(checkoutControllerProvider.notifier).refresh(),
            ),
          ),

        // Whatever stopped the server saying yes, in its own words.
        for (final PreCheckoutIssue issue
            in checkout.validation?.blockers ?? const <PreCheckoutIssue>[])
          _notice(issue.message, '', CartNoticeTone.blocking),

        if (checkout.restaurantName case final String name) ...<Widget>[
          Text(name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: FotgSpacing.x4),
        ],

        if (checkout.pickup.hasWindow) _pickupCard(strings, checkout),

        if (checkout.journey.isReadable) _journeyCard(strings, checkout),

        _itemsCard(strings, checkout),

        const SizedBox(height: FotgSpacing.x4),
        CommercialSummaryCard(summary: checkout.commercial),

        const SizedBox(height: FotgSpacing.x4),
        _editRow(strings),

        const SizedBox(height: FotgSpacing.x5),
        _proceed(strings, state, checkout),

        // The counter's clock, as the server wrote it — never `.toLocal()`,
        // which would put the phone's zone under a pickup window in the
        // restaurant's and read as an expiry hours in the customer's past.
        if (checkout.localExpiresAt case final DateTime expires) ...<Widget>[
          const SizedBox(height: FotgSpacing.x3),
          Center(
            child: Text(
              strings.checkoutExpiresAt(_time(expires)),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: FotgColors.neutral500),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pickupCard(AppStrings strings, Checkout checkout) => Padding(
    padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
    child: FotgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.checkoutPickupHeading,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: FotgSpacing.x2),
          Text(
            strings.pickupWindow(
              _time(checkout.pickup.localStartAt!),
              _time(checkout.pickup.localEndAt!),
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (checkout.pickup.timezone case final String zone) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Text(
              strings.pickupTimezoneNote(zone),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: FotgColors.neutral500),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _journeyCard(AppStrings strings, Checkout checkout) => Padding(
    padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
    child: FotgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.checkoutJourneyHeading,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: FotgSpacing.x2),
          Text(
            strings.checkoutJourney(
              checkout.journey.origin!,
              checkout.journey.destination!,
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    ),
  );

  Widget _itemsCard(AppStrings strings, Checkout checkout) => FotgCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.checkoutOrderHeading,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: FotgSpacing.x3),
        for (final CartLine line in checkout.items)
          Padding(
            padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The dish, and what was chosen with it. A checkout that
                      // said only "Paneer Tikka ×2" could not be checked
                      // against what the customer configured three screens ago.
                      Text('${line.name} ×${line.quantity}'),
                      if (line.configurationSummary.isNotEmpty)
                        Text(
                          line.configurationSummary,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: FotgColors.neutral500),
                        ),
                      if (line.specialInstructions case final String note)
                        Text(
                          strings.cartNote(note),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: FotgColors.neutral500),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: FotgSpacing.x4),
                Text(line.lineTotal.format()),
              ],
            ),
          ),
      ],
    ),
  );

  /// Back to Modules 12 and 13.
  ///
  /// Both invalidate the quote — not through a hook somebody has to remember to
  /// call, but through the fingerprint: the cart's version moves, or the pickup
  /// selection does, and the next read is stale.
  /// Stacked rather than side by side.
  ///
  /// Two of these in a row on a 393dp phone painted "Change pickup time" as
  /// "Change pick…" — a control whose name the customer cannot read, on the
  /// screen where they decide whether to change something before paying. Half a
  /// screen width is not enough for either label at any text size worth
  /// supporting, and it is much less than enough at 200%.
  Widget _editRow(AppStrings strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SecondaryButton(
        key: const ValueKey<String>('checkout-edit-cart'),
        label: strings.checkoutEditCart,
        expand: true,
        onPressed: () => context.push(Routes.tripCartPath(widget.tripId)),
      ),
      const SizedBox(height: FotgSpacing.x2),
      SecondaryButton(
        key: const ValueKey<String>('checkout-change-pickup'),
        label: strings.checkoutChangePickup,
        expand: true,
        onPressed: () => context.push(Routes.tripPickupPath(widget.tripId)),
      ),
    ],
  );

  /// The final call to action.
  ///
  /// Enabled only when the **server** says the order is ready. Tapping it asks
  /// the server again — the payment-readiness check — and then stops, because
  /// Module 15 owns the payment and does not exist yet.
  Widget _proceed(AppStrings strings, CheckoutState state, Checkout checkout) {
    final bool canProceed = state.readyForPayment && state.isUsable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrimaryButton(
          key: const ValueKey<String>('checkout-proceed'),
          label: state.isValidating
              ? strings.checkoutChecking
              : strings.checkoutProceed,
          onPressed: canProceed && !state.isValidating
              ? () => ref.read(checkoutControllerProvider.notifier).validate()
              : null,
        ),
        if (canProceed) ...<Widget>[
          const SizedBox(height: FotgSpacing.x3),
          // Said plainly rather than dressed up as a payment method list. A row
          // of UPI and card logos that cannot be tapped is a promise the build
          // does not keep.
          CartNotice(
            key: const ValueKey<String>('checkout-payment-coming'),
            title: strings.checkoutPaymentComingTitle,
            body: strings.checkoutPaymentComingBody,
            tone: CartNoticeTone.neutral,
          ),
        ],
      ],
    );
  }

  Widget _notice(
    String title,
    String body,
    CartNoticeTone tone, {
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
    child: CartNotice(title: title, body: body, tone: tone, action: action),
  );
}
