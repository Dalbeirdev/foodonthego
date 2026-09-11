import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/restaurant_detail.dart';

/// The photographs at the top of a restaurant's page.
///
/// Three jobs, and the third is the one that is easy to skip: show the images,
/// let the customer move between them, and behave when there are none.
///
/// A restaurant with no photographs gets a branded placeholder, never a broken
/// image icon and never a stock photograph of somebody else's dining room. A
/// picture shown under a business's name is a claim about premises nobody has
/// seen.
class RestaurantHeroGallery extends StatefulWidget {
  const RestaurantHeroGallery({
    required this.name,
    required this.images,
    required this.onIndexChanged,
    this.height = 240,
    super.key,
  });

  final String name;
  final List<RestaurantImage> images;
  final ValueChanged<int> onIndexChanged;
  final double height;

  @override
  State<RestaurantHeroGallery> createState() => _RestaurantHeroGalleryState();
}

class _RestaurantHeroGalleryState extends State<RestaurantHeroGallery> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _moved(int index) {
    if (_index == index) return;

    setState(() => _index = index);
    widget.onIndexChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    if (widget.images.isEmpty) {
      return _RestaurantImageFallback(height: widget.height, name: widget.name);
    }

    // One image is not a gallery. A page indicator reading "1 / 1" and a swipe
    // that goes nowhere both promise something that is not there.
    if (widget.images.length == 1) {
      return _RestaurantPhoto(
        image: widget.images.single,
        name: widget.name,
        height: widget.height,
        semanticsLabel: widget.images.single.altText,
      );
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pages,
            onPageChanged: _moved,
            itemCount: widget.images.length,
            itemBuilder: (BuildContext context, int index) => _RestaurantPhoto(
              image: widget.images[index],
              name: widget.name,
              height: widget.height,
              // The operator's caption where there is one; otherwise a
              // position, which at least tells a screen-reader user where they
              // are in the set. Never an invented description of the picture.
              semanticsLabel:
                  widget.images[index].altText ??
                  strings.restaurantGallerySemantics(
                    widget.name,
                    index + 1,
                    widget.images.length,
                  ),
            ),
          ),

          Positioned(
            right: FotgSpacing.x3,
            bottom: FotgSpacing.x3,
            child: _GalleryCounter(
              label: strings.restaurantGalleryPosition(
                _index + 1,
                widget.images.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One photograph, with its loading and failure states.
class _RestaurantPhoto extends StatelessWidget {
  const _RestaurantPhoto({
    required this.image,
    required this.name,
    required this.height,
    this.semanticsLabel,
  });

  final RestaurantImage image;
  final String name;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticsLabel,
    child: Image.network(
      image.url,
      height: height,
      width: double.infinity,
      // Fills the box without distorting: a portrait photograph stretched to a
      // landscape frame makes a restaurant look like nowhere anybody has been.
      fit: BoxFit.cover,
      // A grey box of the right size while the bytes arrive, so the page does
      // not jump when they do.
      loadingBuilder: (
        BuildContext context,
        Widget child,
        ImageChunkEvent? progress,
      ) => progress == null ? child : _RestaurantImageSkeleton(height: height),
      // A photograph that will not load is a missing photograph, not a broken
      // page. The same branded fallback a restaurant with none gets.
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          _RestaurantImageFallback(height: height, name: name),
    ),
  );
}

/// The branded stand-in for a restaurant with no usable photograph.
class _RestaurantImageFallback extends StatelessWidget {
  const _RestaurantImageFallback({required this.height, required this.name});

  final double height;
  final String name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Semantics(
      label: strings.restaurantNoImages,
      child: Container(
        height: height,
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.storefront_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              strings.restaurantNoImages,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantImageSkeleton extends StatelessWidget {
  const _RestaurantImageSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
  );
}

/// "2 / 5", over whatever the photograph happens to be.
class _GalleryCounter extends StatelessWidget {
  const _GalleryCounter({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: FotgSpacing.x3,
      vertical: FotgSpacing.x1,
    ),
    decoration: BoxDecoration(
      // Its own dark ground rather than a theme colour: it sits on a
      // photograph, and a photograph can be any colour at all.
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: const BorderRadius.all(Radius.circular(FotgRadius.full)),
    ),
    child: Text(
      label,
      // Excluded from semantics: the gallery already announces "photograph 2
      // of 5" on the image itself, and a screen reader should not hear the
      // same fact twice in two different forms.
      semanticsLabel: '',
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: Colors.white),
    ),
  );
}
