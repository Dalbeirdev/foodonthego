import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/menu_customization.dart';

/// Choosing a size.
///
/// Radios, because sizes are mutually exclusive and a radio says so before the
/// customer taps. A sold-out size stays on the list, disabled and labelled —
/// hiding it would leave somebody who came for the family portion wondering
/// whether they misremembered the menu.
class VariantSelector extends StatelessWidget {
  const VariantSelector({
    required this.variants,
    required this.selectedId,
    required this.onSelected,
    required this.required,
    super.key,
  });

  final List<MenuItemVariant> variants;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// True when nothing is chosen yet and something must be.
  final bool required;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _GroupHeading(
          name: strings.itemChooseSize,
          rule: required ? strings.itemSizeRequired : null,
          isRequired: required,
        ),
        const SizedBox(height: FotgSpacing.x2),
        ...variants.map((MenuItemVariant variant) {
          final bool selected = variant.id == selectedId;

          return Semantics(
            container: true,
            inMutuallyExclusiveGroup: true,
            checked: selected,
            enabled: variant.isAvailable,
            label: _label(strings, variant, selected),
            excludeSemantics: true,
            onTap: variant.isAvailable ? () => onSelected(variant.id) : null,
            child: _OptionRow(
              // A radio drawn by hand rather than a RadioListTile, so the
              // whole row's semantics are one node the driver and a screen
              // reader both read as one thing.
              icon: selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              title: variant.name,
              trailing: variant.isAvailable
                  ? variant.price.format()
                  : strings.itemUnavailableOption,
              subtitle: variant.preparationMinutes == null
                  ? null
                  : strings.menuPreparationTime(variant.preparationMinutes!),
              enabled: variant.isAvailable,
              selected: selected,
              onTap: variant.isAvailable ? () => onSelected(variant.id) : null,
            ),
          );
        }),
      ],
    );
  }

  String _label(AppStrings strings, MenuItemVariant variant, bool selected) {
    final StringBuffer buffer = StringBuffer(variant.name)
      ..write('. ')
      ..write(variant.price.spokenLabel());

    if (!variant.isAvailable) {
      buffer.write('. ${strings.itemUnavailableOption}');
    } else {
      buffer.write('. ${selected ? 'Selected' : 'Not selected'}');
    }

    return buffer.toString();
  }
}

/// A section heading with its rule spelled out underneath.
///
/// The rule is here rather than in an error message, because a customer should
/// not have to be refused to learn what was being asked of them.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.name,
    required this.rule,
    required this.isRequired,
    this.description,
    this.isUnsatisfied = false,
  });

  final String name;
  final String? rule;
  final String? description;
  final bool isRequired;

  /// Marked only after the customer has tried to add. A screen that opens
  /// covered in red is telling somebody off for not having started.
  final bool isUnsatisfied;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Wrap rather than Row: a group name and a rule like
        // "Required · Choose 1 to 3" do not fit on one line at 320 dp, and a
        // rule that has been clipped is a rule nobody can follow.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: FotgSpacing.x2,
          runSpacing: FotgSpacing.x1,
          children: <Widget>[
            Text(
              name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isUnsatisfied ? FotgColors.error : null,
              ),
            ),
            if (rule case final String text)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FotgSpacing.x2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  // Required is a word and a colour, never a colour alone, and
                  // never a bare asterisk.
                  color: isRequired
                      ? FotgColors.primary50
                      : FotgColors.neutral100,
                  borderRadius: FotgRadius.pill,
                ),
                child: Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isRequired
                        ? FotgColors.primary700
                        : FotgColors.neutral600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        if (description case final String text) ...<Widget>[
          const SizedBox(height: FotgSpacing.x1),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: FotgColors.neutral600,
            ),
          ),
        ],
      ],
    );
  }
}

/// The shared heading, exported for the modifier sections.
class GroupHeading extends StatelessWidget {
  const GroupHeading({
    required this.name,
    required this.rule,
    required this.isRequired,
    super.key,
    this.description,
    this.isUnsatisfied = false,
  });

  final String name;
  final String? rule;
  final String? description;
  final bool isRequired;
  final bool isUnsatisfied;

  @override
  Widget build(BuildContext context) => _GroupHeading(
    name: name,
    rule: rule,
    isRequired: isRequired,
    description: description,
    isUnsatisfied: isUnsatisfied,
  );
}


/// One tappable choice: a mark, a name, a price.
///
/// Hand-drawn rather than a `RadioListTile` or `CheckboxListTile` so the row is
/// a single semantics node with a sentence of its own — a list tile's built-in
/// semantics announce the control and the label as separate stops, which on a
/// screen with twenty options is forty things to swipe past.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.enabled,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final String? subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Color foreground = enabled ? FotgColors.neutral900 : FotgColors.neutral400;

    return InkWell(
      onTap: onTap,
      borderRadius: FotgRadius.control,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: FotgSpacing.x2,
          horizontal: FotgSpacing.x1,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 22,
              color: !enabled
                  ? FotgColors.neutral300
                  : selected
                  ? theme.colorScheme.primary
                  : FotgColors.neutral400,
            ),
            const SizedBox(width: FotgSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
                  ),
                  if (subtitle case final String text) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: FotgColors.neutral500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: FotgSpacing.x2),
            Text(
              trailing,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: enabled ? FotgColors.neutral800 : FotgColors.neutral400,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same row, for the modifier sections.
class OptionRow extends StatelessWidget {
  const OptionRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.enabled,
    required this.selected,
    required this.onTap,
    super.key,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final String? subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _OptionRow(
    icon: icon,
    title: title,
    trailing: trailing,
    subtitle: subtitle,
    enabled: enabled,
    selected: selected,
    onTap: onTap,
  );
}
