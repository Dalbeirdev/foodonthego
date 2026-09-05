import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/restaurant_menu.dart';
import 'menu_item_badges.dart';

/// One dish in the list.
///
/// A sold-out dish is still shown, dimmed and labelled. Removing it would be
/// tidier and worse: a customer who came for one thing deserves to learn the
/// kitchen has run out, rather than to conclude they misremembered the menu.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({required this.item, required this.onTap, super.key});

  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    // Dimmed rather than removed, and dimmed by opacity rather than by a
    // greyed palette, so the badge colours stay legible.
    final double opacity = item.isSoldOut ? 0.55 : 1;

    return Semantics(
      button: true,
      // Named in full, so a screen reader hears the dish, its price and
      // whether it can be had — rather than "button" three hundred times.
      label: _semanticsLabel(strings),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: FotgRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FotgSpacing.x4,
            vertical: FotgSpacing.x3,
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: FotgSpacing.x1),
                      Text(
                        item.price.format(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: FotgColors.neutral800,
                        ),
                      ),
                      // Absent when the restaurant wrote none. Never generated
                      // and never replaced with a generic line about the dish.
                      if (item.hasDescription) ...<Widget>[
                        const SizedBox(height: FotgSpacing.x2),
                        Text(
                          item.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: FotgColors.neutral600,
                          ),
                        ),
                      ],
                      const SizedBox(height: FotgSpacing.x2),
                      MenuItemBadges(item: item, compact: true),
                    ],
                  ),
                ),
                const SizedBox(width: FotgSpacing.x3),
                _Thumbnail(item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel(AppStrings strings) {
    final StringBuffer buffer = StringBuffer(item.name)
      ..write('. ')
      ..write(item.price.spokenLabel());

    if (item.isSoldOut) buffer.write('. ${strings.menuSoldOut}');

    return buffer.toString();
  }
}

/// The dish's own photograph, or nothing.
///
/// There is no stock-image fallback anywhere in this app. A generic curry
/// standing in for an unphotographed dish is a claim about what arrives in the
/// box, and it is one the restaurant never made.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item});

  final MenuItem item;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final String? url = item.listImageUrl;

    final Widget child = url == null
        ? const _NoPhotograph()
        : Image.network(
            url,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            // A dish's own photograph carries no information a sighted user
            // gets and a blind one does not: the name and price are already
            // announced. Excluded rather than described with a caption nobody
            // wrote.
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const _NoPhotograph(),
            frameBuilder: (_, Widget child, int? frame, bool wasSync) {
              if (wasSync || frame != null) return child;

              // The box is reserved at its final size, so a menu of thirty
              // dishes does not reflow as each photograph lands.
              return const _NoPhotograph();
            },
          );

    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: FotgRadius.control,
          child: SizedBox(width: _size, height: _size, child: child),
        ),
        if (item.isSoldOut)
          Positioned.fill(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: FotgColors.neutral950.withValues(alpha: 0.45),
                  borderRadius: FotgRadius.control,
                ),
                child: Center(
                  child: Text(
                    AppStrings.of(context).menuSoldOut,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: FotgColors.neutral0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoPhotograph extends StatelessWidget {
  const _NoPhotograph();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: _Thumbnail._size,
      height: _Thumbnail._size,
      color: FotgColors.neutral100,
      child: const Icon(
        Icons.restaurant_outlined,
        size: 22,
        color: FotgColors.neutral400,
      ),
    ),
  );
}
