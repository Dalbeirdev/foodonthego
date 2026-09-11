import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/restaurant_menu.dart';

/// The sticky row of section chips above a menu.
///
/// Two-way: tapping a chip scrolls the list to that section, and scrolling the
/// list moves the highlight. The second half is the one that matters — a
/// selector that only leads is a set of shortcuts, while one that also follows
/// tells a customer halfway down a long menu where they are.
class MenuCategorySelector extends StatefulWidget {
  const MenuCategorySelector({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<MenuCategory> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<MenuCategorySelector> createState() => _MenuCategorySelectorState();
}

class _MenuCategorySelectorState extends State<MenuCategorySelector> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _chipKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(MenuCategorySelector old) {
    super.didUpdateWidget(old);

    if (old.selectedId != widget.selectedId) {
      // The highlight moved because the customer scrolled the menu. Bringing
      // the chip into view is what keeps a twenty-section selector usable:
      // otherwise the active section is off-screen for most of the menu.
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _revealSelected() {
    final String? id = widget.selectedId;

    if (id == null || !mounted) return;

    final BuildContext? chip = _chipKeys[id]?.currentContext;

    if (chip == null) return;

    Scrollable.ensureVisible(
      chip,
      duration: FotgMotion.respectingReducedMotion(context, FotgMotion.fast),
      alignment: 0.5,
      curve: FotgMotion.decelerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Semantics(
      container: true,
      // Without this a screen reader reads a row of bare words with no idea
      // what they are for.
      label: strings.menuCategorySelector,
      explicitChildNodes: true,
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: FotgSpacing.x4),
          itemCount: widget.categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: FotgSpacing.x2),
          itemBuilder: (BuildContext context, int index) {
            final MenuCategory category = widget.categories[index];
            final bool selected = category.id == widget.selectedId;

            final GlobalKey key = _chipKeys.putIfAbsent(
              category.id,
              GlobalKey.new,
            );

            return Center(
              key: key,
              child: Semantics(
                button: true,
                selected: selected,
                label: strings.menuJumpToCategory(category.name),
                excludeSemantics: true,
                onTap: () => widget.onSelected(category.id),
                child: ChoiceChip(
                  label: Text(category.name),
                  selected: selected,
                  onSelected: (_) => widget.onSelected(category.id),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
