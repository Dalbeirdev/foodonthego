import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// One offered pickup window, as a tappable chip.
///
/// The times shown are formatted from the instants the server sent, in the
/// restaurant's own zone. **The chip carries the option's opaque id and hands
/// exactly that back on tap** — it never sends the times it is displaying, and
/// there is no path by which a rendered string could become a request.
class PickupTimeChip extends StatelessWidget {
  const PickupTimeChip({
    required this.label,
    required this.isSelected,
    required this.isRecommended,
    required this.isBusy,
    required this.onPressed,
    this.recommendedLabel,
    super.key,
  });

  final String label;
  final bool isSelected;
  final bool isRecommended;

  /// This chip's own selection is in flight. Only this one waits; the rest of
  /// the screen stays usable, because freezing every time to choose one makes a
  /// fast connection feel slow and a slow one feel broken.
  final bool isBusy;

  final String? recommendedLabel;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    final Color border = isSelected
        ? FotgColors.primary600
        : (dark ? FotgColors.neutral600 : FotgColors.neutral300);

    final Color surface = isSelected
        ? (dark ? FotgColors.primary700 : FotgColors.primary50)
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: isSelected,
      // The recommendation is spoken as well as drawn. A customer using a
      // screen reader gets the same steer as one looking at a highlighted chip.
      label: isRecommended && recommendedLabel != null
          ? '$label, $recommendedLabel'
          : label,
      child: Material(
        color: surface,
        borderRadius: FotgRadius.pill,
        child: InkWell(
          onTap: isBusy ? null : onPressed,
          borderRadius: FotgRadius.pill,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FotgSpacing.x4,
              vertical: FotgSpacing.x3,
            ),
            decoration: BoxDecoration(
              borderRadius: FotgRadius.pill,
              border: Border.all(color: border, width: isSelected ? 2 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isBusy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isSelected)
                  // Never colour alone. A tick survives a monochrome screen and
                  // a customer who cannot tell orange from grey.
                  const Icon(Icons.check, size: 16),
                if (isBusy || isSelected) const SizedBox(width: FotgSpacing.x2),
                // Flexible, and it earns its place: at double text size
                // "1:40 pm – 1:50 pm" is wider than the line the Wrap gives
                // this chip, and without this the label runs off the right of
                // the pill. A customer who has turned text up is exactly the
                // customer who cannot read the half that is left.
                //
                // The Wrap supplies the width; this lets the label use it and
                // take a second line rather than overflow. Deliberately not a
                // MediaQuery lookup — a widget that sizes itself from one
                // breaks wherever MediaQuery is not what it expects.
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
