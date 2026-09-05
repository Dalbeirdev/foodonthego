import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/restaurant_menu.dart';

/// The small badges under a dish: diet, spice, cooking time.
///
/// Every one of them is drawn only when the restaurant published the field
/// behind it. There is no "unspecified" chip and no greyed-out placeholder,
/// because a customer who cannot eat egg needs the absence of a badge to mean
/// "nobody said", not "we checked".
class MenuItemBadges extends StatelessWidget {
  const MenuItemBadges({
    required this.item,
    super.key,
    this.compact = false,
  });

  final MenuItem item;

  /// The list card variant — smaller, and without the cooking time, which
  /// belongs on the item's own screen where there is room to qualify it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final List<Widget> badges = <Widget>[
      if (_dietaryLabel(strings) case final String label)
        _Badge(
          label: label,
          semanticsLabel: strings.menuDietarySemantics(label),
          foreground: _dietaryColour,
          background: _dietarySurface,
          leading: _DietaryMark(colour: _dietaryColour),
          compact: compact,
        ),
      if (_spiceLabel(strings) case final String label)
        _Badge(
          label: label,
          semanticsLabel: strings.menuSpiceSemantics(label),
          foreground: FotgColors.warning,
          background: FotgColors.warningSurface,
          compact: compact,
        ),
      if (compact ? null : item.preparationMinutes case final int minutes)
        _Badge(
          label: strings.menuPreparationTime(minutes),
          // Spelled out for a screen reader, including the disclaimer. A blind
          // customer hearing "15 min" on a food app will otherwise reasonably
          // assume it is when their order will be ready.
          semanticsLabel: strings.menuPreparationSemantics(minutes),
          foreground: FotgColors.neutral600,
          background: FotgColors.neutral100,
          compact: compact,
        ),
    ];

    if (badges.isEmpty) {
      // Nothing published. The row is absent rather than empty, so it takes no
      // vertical space and no screen-reader stop.
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: FotgSpacing.x2,
      runSpacing: FotgSpacing.x1,
      children: badges,
    );
  }

  String? _dietaryLabel(AppStrings strings) => switch (item.dietaryType) {
    MenuItemDietaryType.vegetarian => strings.menuVeg,
    MenuItemDietaryType.nonVegetarian => strings.menuNonVeg,
    MenuItemDietaryType.vegan => strings.menuVegan,
    MenuItemDietaryType.egg => strings.menuEgg,
    MenuItemDietaryType.unknown => null,
  };

  Color get _dietaryColour => switch (item.dietaryType) {
    MenuItemDietaryType.nonVegetarian => FotgColors.error,
    _ => FotgColors.success,
  };

  Color get _dietarySurface => switch (item.dietaryType) {
    MenuItemDietaryType.nonVegetarian => FotgColors.errorSurface,
    _ => FotgColors.successSurface,
  };

  String? _spiceLabel(AppStrings strings) => switch (item.spiceLevel) {
    1 => strings.menuSpiceMild,
    2 => strings.menuSpiceMedium,
    3 => strings.menuSpiceHot,
    // 0 means the restaurant said "not spicy", which is a fact worth nothing
    // on a badge; null means they said nothing at all. Neither is drawn.
    _ => null,
  };
}

/// The square-in-a-square mark Indian menus use for veg and non-veg.
///
/// Decorative here: the badge beside it already carries the word, and the
/// semantics label carries it again. Excluded from the tree so a screen reader
/// does not announce an anonymous image between two words.
class _DietaryMark extends StatelessWidget {
  const _DietaryMark({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        border: Border.all(color: colour, width: 1.4),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.semanticsLabel,
    required this.foreground,
    required this.background,
    required this.compact,
    this.leading,
  });

  final String label;
  final String semanticsLabel;
  final Color foreground;
  final Color background;
  final Widget? leading;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    excludeSemantics: true,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? FotgSpacing.x2 : FotgSpacing.x3,
        vertical: compact ? 2 : FotgSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: FotgRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (leading case final Widget mark) ...<Widget>[
            mark,
            const SizedBox(width: FotgSpacing.x1),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
