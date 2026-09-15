import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/cart.dart';
import '../../../domain/models/cart_revalidation.dart';
import '../../../domain/models/money.dart';

/// One line of the cart: what was chosen, how many, and what it costs.
///
/// The configuration is shown in full — the size, every option, the note —
/// because a cart is where a customer checks that the thing they configured
/// three screens ago is the thing they are about to buy. A line that says only
/// "Paneer Tikka ×2" cannot be checked.
///
/// The controls are disabled while this line's own request is in flight, and
/// only this line's: blocking the whole cart to change one quantity makes a
/// fast connection feel slow and a slow one feel broken.
class CartLineTile extends StatelessWidget {
  const CartLineTile({
    required this.line,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
    this.verdict,
    this.isBusy = false,
    this.isEnabled = true,
    this.failureMessage,
    super.key,
  });

  final CartLine line;

  /// What revalidation said about this line, if it has been asked.
  final CartLineVerdict? verdict;

  /// This line has a request in flight.
  final bool isBusy;

  /// Some other line does. The controls are dimmed rather than removed, so the
  /// layout does not jump while a neighbour is saving.
  final bool isEnabled;

  /// A refusal that belongs to this line, shown against it rather than in a
  /// snackbar somewhere else on the screen.
  final String? failureMessage;

  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  bool get _blocked => verdict?.blocksOrdering ?? false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    final String configuration = line.configurationSummary;

    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        line.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          // Struck through when the line cannot be ordered, so
                          // the state is legible without relying on colour.
                          decoration: _blocked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (configuration.isNotEmpty) ...<Widget>[
                        const SizedBox(height: FotgSpacing.x1),
                        Text(
                          configuration,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: FotgColors.neutral600,
                          ),
                        ),
                      ],
                      if (line.hasNote) ...<Widget>[
                        const SizedBox(height: FotgSpacing.x1),
                        Text(
                          strings.cartNote(line.specialInstructions!.trim()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: FotgColors.neutral600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: FotgSpacing.x3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      line.lineTotal.format(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const <FontFeature>[
                          // Tabular figures, so a column of prices lines up at
                          // the decimal point and can be scanned.
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    if (line.quantity > 1) ...<Widget>[
                      const SizedBox(height: FotgSpacing.x1),
                      Text(
                        '${line.unitPrice.format()} ${strings.cartEachPrice}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: FotgColors.neutral500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            if (verdict case final CartLineVerdict v when !v.isSettled) ...[
              const SizedBox(height: FotgSpacing.x3),
              _LineFinding(verdict: v),
            ],

            if (failureMessage case final String message) ...<Widget>[
              const SizedBox(height: FotgSpacing.x3),
              _LineMessage(
                message: message,
                icon: Icons.error_outline_rounded,
                colour: FotgColors.error,
                surface: FotgColors.errorSurface,
              ),
            ],

            const SizedBox(height: FotgSpacing.x3),
            Row(
              children: <Widget>[
                _Stepper(
                  line: line,
                  isBusy: isBusy,
                  isEnabled: isEnabled,
                  onDecrease: onDecrease,
                  onIncrease: onIncrease,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: isEnabled && !isBusy ? onRemove : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(strings.cartRemove),
                  style: TextButton.styleFrom(
                    foregroundColor: FotgColors.neutral600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Minus, a number, plus.
///
/// The minus is disabled at one rather than turning into a delete. Overloading
/// the last decrement as removal is how a mis-tap loses a customer's selection,
/// and it leaves the app unable to tell a mistake from an intention — the
/// remove control beside it says what it does.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.line,
    required this.isBusy,
    required this.isEnabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  final CartLine line;
  final bool isBusy;
  final bool isEnabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    final bool live = isEnabled && !isBusy;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: FotgColors.neutral300),
        borderRadius: FotgRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: live && line.quantity > 1 ? onDecrease : null,
            icon: const Icon(Icons.remove_rounded),
            iconSize: 18,
            // 44 is the smallest target Apple and Google both call reachable,
            // and this control is tapped repeatedly by somebody in a moving car.
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: strings.cartDecreaseFor(line.name),
          ),
          SizedBox(
            width: 32,
            child: isBusy
                ? const Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(
                    '${line.quantity}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          IconButton(
            onPressed: live ? onIncrease : null,
            icon: const Icon(Icons.add_rounded),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: strings.cartIncreaseFor(line.name),
          ),
        ],
      ),
    );
  }
}

/// What revalidation said about this line.
class _LineFinding extends StatelessWidget {
  const _LineFinding({required this.verdict});

  final CartLineVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final bool blocking = verdict.blocksOrdering;

    // A price change is a thing to look at; a missing dish is a thing to fix.
    // The two are coloured and worded differently because the customer's next
    // move differs.
    final Color colour = blocking ? FotgColors.error : FotgColors.warning;
    final Color surface = blocking
        ? FotgColors.errorSurface
        : FotgColors.warningSurface;

    final String text = switch (verdict) {
      CartLineVerdict(
        finding: final CartFinding f,
        priceWhenAdded: final Money was,
        priceNow: final Money now,
      )
          when f.isPriceChange =>
        '${strings.cartPriceWas} ${was.format()} · '
            '${strings.cartPriceNow} ${now.format()}',
      _ => verdict.message ?? strings.cartUnavailableHere,
    };

    return _LineMessage(
      message: text,
      icon: blocking
          ? Icons.remove_shopping_cart_outlined
          : Icons.info_outline_rounded,
      colour: colour,
      surface: surface,
    );
  }
}

class _LineMessage extends StatelessWidget {
  const _LineMessage({
    required this.message,
    required this.icon,
    required this.colour,
    required this.surface,
  });

  final String message;
  final IconData icon;
  final Color colour;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x3,
        vertical: FotgSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: FotgRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: FotgSpacing.x2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}
