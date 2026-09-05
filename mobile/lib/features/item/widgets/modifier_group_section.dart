import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/menu_customization.dart';
import 'variant_selector.dart';

/// One question and its answers.
///
/// The rule is stated under the heading — "Required · Choose 1", "Optional ·
/// Choose up to 2" — rather than discovered by being refused. A customer should
/// never have to guess what is being asked of them, and a validation message is
/// a poor place to explain it for the first time.
class ModifierGroupSection extends StatelessWidget {
  const ModifierGroupSection({
    required this.group,
    required this.selectedIds,
    required this.onToggle,
    super.key,
    this.isUnsatisfied = false,
  });

  final MenuModifierGroup group;
  final Set<String> selectedIds;
  final void Function(MenuModifierGroup, MenuModifierOption) onToggle;

  /// Marked only once the customer has tried to add.
  final bool isUnsatisfied;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final int chosen = group.options
        .where((MenuModifierOption o) => selectedIds.contains(o.id))
        .length;

    final bool full = !group.isSingleSelect && chosen >= group.maxSelect;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: strings.itemGroupSemantics(group.name, _rule(strings)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GroupHeading(
            name: group.name,
            rule: _rule(strings),
            description: group.description,
            isRequired: group.isRequired,
            isUnsatisfied: isUnsatisfied,
          ),

          if (isUnsatisfied) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Text(
              strings.itemChooseToContinue(group.minSelect),
              style: theme.textTheme.bodySmall?.copyWith(
                color: FotgColors.error,
              ),
            ),
          ],

          const SizedBox(height: FotgSpacing.x1),

          ...group.options.map((MenuModifierOption option) {
            final bool selected = selectedIds.contains(option.id);

            // At the ceiling, an unchosen option is disabled rather than
            // silently swapping one of the customer's earlier choices out.
            final bool enabled =
                option.isAvailable && (selected || !full);

            return Semantics(
              container: true,
              checked: selected,
              enabled: enabled,
              inMutuallyExclusiveGroup: group.isSingleSelect,
              label: _optionLabel(strings, option, selected),
              excludeSemantics: true,
              onTap: enabled ? () => onToggle(group, option) : null,
              child: OptionRow(
                icon: group.isSingleSelect
                    ? (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked)
                    : (selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded),
                title: option.name,
                subtitle: option.description,
                trailing: _trailing(strings, option),
                enabled: enabled,
                selected: selected,
                onTap: enabled ? () => onToggle(group, option) : null,
              ),
            );
          }),

          // Said once the ceiling is reached, so the disabled rows have an
          // explanation next to them rather than looking broken.
          if (full) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Text(
              strings.itemGroupFull(group.maxSelect),
              style: theme.textTheme.bodySmall?.copyWith(
                color: FotgColors.neutral600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The rule, in words.
  String _rule(AppStrings strings) {
    if (group.minSelect >= 1 && group.minSelect == group.maxSelect) {
      return '${strings.itemRequired} · ${strings.itemChooseExactly(group.minSelect)}';
    }

    if (group.minSelect >= 1) {
      return '${strings.itemRequired} · '
          '${strings.itemChooseBetween(group.minSelect, group.maxSelect)}';
    }

    return '${strings.itemOptional} · ${strings.itemChooseUpTo(group.maxSelect)}';
  }

  String _trailing(AppStrings strings, MenuModifierOption option) {
    if (!option.isAvailable) return strings.itemUnavailableOption;

    // A free option shows nothing rather than "₹0". The absence of a price is
    // the clearest way to say a choice costs nothing.
    return option.isFree ? '' : '+${option.priceDelta.format()}';
  }

  String _optionLabel(
    AppStrings strings,
    MenuModifierOption option,
    bool selected,
  ) {
    final StringBuffer buffer = StringBuffer(option.name)..write('. ');

    if (!option.isAvailable) {
      buffer.write(strings.itemUnavailableOption);

      return buffer.toString();
    }

    // Spelled out for a screen reader, which cannot see that the trailing
    // column is empty: "no extra charge" is information, a blank is not.
    buffer
      ..write(
        option.isFree
            ? strings.itemNoExtraCharge
            : strings.itemAddsPrice(option.priceDelta.spokenLabel()),
      )
      ..write('. ')
      ..write(selected ? 'Selected' : 'Not selected');

    return buffer.toString();
  }
}
