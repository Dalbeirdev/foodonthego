import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';

/// How many.
///
/// Minus, a number, plus. The floor is one — a customer who wants none simply
/// does not add the dish, and a stepper that reached zero would be offering a
/// "remove" that has nothing to remove from.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.quantity,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
    required this.maxQuantity,
    super.key,
  });

  final int quantity;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final int maxQuantity;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                strings.itemQuantity,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: FotgSpacing.x1),
              Text(
                strings.itemQuantityMax(maxQuantity),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: FotgColors.neutral600,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: FotgColors.neutral300),
            borderRadius: FotgRadius.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _StepButton(
                icon: Icons.remove_rounded,
                label: strings.itemQuantityDecrease,
                onPressed: canDecrease ? onDecrease : null,
              ),
              // The number is its own node, announced as "Quantity, 2" — a
              // bare "2" between two buttons tells a screen-reader user
              // nothing about what it counts.
              Semantics(
                container: true,
                liveRegion: true,
                label: strings.itemQuantitySemantics(quantity),
                excludeSemantics: true,
                child: SizedBox(
                  width: 44,
                  child: Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                label: strings.itemQuantityIncrease,
                onPressed: canIncrease ? onIncrease : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    // Named explicitly rather than left to the tooltip. A tooltip becomes an
    // accessible name only on an *enabled* control, so at quantity one the
    // minus button would otherwise be an anonymous disabled thing — and "you
    // cannot go below one" is exactly the moment a screen-reader user needs to
    // know what the control is.
    label: label,
    excludeSemantics: true,
    onTap: onPressed,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: label,
      // 48 dp: above the floor in both the Apple HIG and WCAG 2.2, and this is
      // tapped one-handed by somebody about to drive.
      constraints: const BoxConstraints(
        minWidth: FotgSizing.touchTargetMin,
        minHeight: FotgSizing.touchTargetMin,
      ),
      padding: EdgeInsets.zero,
    ),
  );
}
