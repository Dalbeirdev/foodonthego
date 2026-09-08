import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/checkout.dart';
import '../../../shared/widgets/fotg_card.dart';

/// What the customer will pay, and what each part of it is for.
///
/// **Only the components the server sent are drawn.** There is no code here
/// that renders a zero row for a missing charge — an absent component means
/// nobody configured that rule, and "Tax  ₹0.00" would state a decision the
/// platform has not made.
///
/// When nothing is configured the card says so in words. An order summary
/// showing a subtotal and a total with nothing between them reads as a bug, and
/// a customer wondering what is missing is a customer who does not proceed.
class CommercialSummaryCard extends StatelessWidget {
  const CommercialSummaryCard({required this.summary, super.key});

  final CommercialSummary summary;

  /// A label for a charge code, or the code itself.
  ///
  /// A code this build has never met is shown rather than dropped. A customer
  /// paying a charge must be able to see it, and an old build meeting a new
  /// charge should be unhelpful rather than silent.
  String _label(AppStrings strings, String code) => switch (code) {
    'TAX' => strings.checkoutTax,
    'PACKAGING_FEE' => strings.checkoutPackagingFee,
    'PLATFORM_FEE' => strings.checkoutPlatformFee,
    'DISCOUNT' => strings.checkoutDiscount,
    _ => code,
  };

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return FotgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.checkoutSummaryHeading,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FotgSpacing.x4),

          _Row(
            label: strings.checkoutItemsSubtotal,
            value: summary.itemsSubtotal.format(),
          ),

          for (final CommercialLine line in summary.charges)
            _Row(
              label: _label(strings, line.code),
              value: line.amount.format(),
            ),

          for (final CommercialLine line in summary.discounts)
            _Row(
              label: _label(strings, line.code),
              value: '−${line.amount.format()}',
            ),

          if (!summary.hasConfiguredAdjustments) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            Text(
              // Deliberately about configuration. It does not say "no tax
              // applies" — that is a legal statement nobody here is entitled to
              // make.
              strings.checkoutNoAdjustments,
              style: theme.textTheme.bodySmall?.copyWith(
                color: FotgColors.neutral500,
              ),
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: FotgSpacing.x3),
            child: Divider(height: 1),
          ),

          _Row(
            label: strings.checkoutTotal,
            value: summary.payableTotal.format(),
            emphasised: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final TextStyle? style = emphasised
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: FotgSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: FotgSpacing.x4),
          Text(value, style: style),
        ],
      ),
    );
  }
}
