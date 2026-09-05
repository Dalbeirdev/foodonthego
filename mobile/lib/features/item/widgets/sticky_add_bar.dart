import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/money.dart';
import '../../../shared/state/item_customization_controller.dart';

/// The button, pinned above the safe area.
///
/// It carries the running total, because a price a customer has to scroll to
/// find is a price they check once and then trust. The label says what tapping
/// will do — "Add to cart · ₹778" when it will work, "Choose required options"
/// when it will not.
///
/// It stays **enabled** when a required choice is missing. A disabled button
/// with no explanation is a customer wondering what they did wrong; this one
/// takes the tap and scrolls them to the question they have not answered.
class StickyAddBar extends StatelessWidget {
  const StickyAddBar({required this.state, required this.onAdd, super.key});

  final CustomizationState state;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final (String label, bool enabled) = _label(strings);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(FotgSpacing.x4),
          child: SizedBox(
            height: FotgSizing.controlHeightLg,
            child: Semantics(
              button: true,
              enabled: enabled,
              label: label,
              excludeSemantics: true,
              onTap: enabled ? onAdd : null,
              child: FilledButton(
                onPressed: enabled ? onAdd : null,
                child: state.isSubmitting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: FotgSpacing.x3),
                          Text(strings.itemAdding),
                        ],
                      )
                    : Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the button says, and whether tapping does anything.
  (String, bool) _label(AppStrings strings) {
    if (state.isSubmitting) return (strings.itemAdding, false);

    if (!state.hasLoaded) return (strings.itemAdding, false);

    // The dish itself cannot be ordered. Nothing the customer can do on this
    // screen changes that, so the button is genuinely inert and says why.
    if (state.item?.isSoldOut ?? false) return (strings.itemSoldOut, false);

    final bool canOrder = state.preview?.restaurant.canOrder ?? false;

    if (!canOrder) return (strings.itemRestaurantPaused, false);

    if (!state.isComplete) {
      // Enabled on purpose: the tap is what scrolls them to the question.
      return (strings.itemAddChooseOptions, true);
    }

    final Money? total = state.previewLineTotal;

    if (total == null) return (strings.itemAdding, false);

    return (strings.itemAddToCart(total.format()), true);
  }
}
