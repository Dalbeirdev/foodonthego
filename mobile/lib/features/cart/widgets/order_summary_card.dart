import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/cart.dart';
import '../../../domain/models/money.dart';

/// What the customer owes, and where it came from.
///
/// **Every figure here is the server's.** Nothing on this card is added up on
/// the device: a client that computed its own total would be right most days
/// and wrong on the day a rate changed, and the customer would see one number
/// and be charged another.
///
/// The breakdown is shown rather than a single total, because "why is this more
/// than the menu said" is the question that turns into a support call. A charge
/// of nothing gets no row — "Service fee ₹0.00" is a line somebody has to read
/// to discover it is nothing — but the total is always shown, zero or not.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({required this.totals, super.key});

  final CartTotals totals;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    String labelFor(String kind) => switch (kind) {
      'tax' => strings.cartTax,
      'packaging' => strings.cartPackagingFee,
      'platform' => strings.cartPlatformFee,
      // Unreachable through [CartTotals.charges], and here so that a charge
      // added later shows up as an unlabelled row rather than vanishing from a
      // bill the customer is asked to pay.
      _ => kind,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.cartSummaryTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: FotgSpacing.x3),
        _SummaryRow(
          label: strings.cartSubtotal,
          amount: totals.subtotal.format(),
        ),
        for (final ({String kind, Money amount}) charge in totals.charges) ...[
          const SizedBox(height: FotgSpacing.x2),
          _SummaryRow(
            label: labelFor(charge.kind),
            amount: charge.amount.format(),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: FotgSpacing.x3),
          child: Divider(height: 1),
        ),
        _SummaryRow(
          label: strings.cartTotal,
          amount: totals.total.format(),
          emphasised: true,
        ),
        const SizedBox(height: FotgSpacing.x3),
        Text(
          strings.cartTotalsNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: FotgColors.neutral500,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.emphasised = false,
  });

  final String label;
  final String amount;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final TextStyle? style = emphasised
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium?.copyWith(color: FotgColors.neutral600);

    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: style)),
        Text(
          amount,
          style: style?.copyWith(
            // Tabular figures so the column lines up at the decimal point and
            // a customer can add it up with their eye.
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
