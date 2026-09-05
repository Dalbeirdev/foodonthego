import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/restaurant_detail.dart' show RestaurantOrderingState;
import '../../domain/models/restaurant_menu.dart';
import '../../shared/state/menu_controller.dart';
import 'widgets/menu_category_selector.dart';
import 'widgets/menu_item_card.dart';

/// A restaurant's menu, on this customer's route.
///
/// The screen is one scroll view with a pinned section selector, which is what
/// makes a twenty-section menu navigable: the customer either taps a section
/// and is taken there, or scrolls and watches the selector follow.
///
/// It shows what the restaurant published and nothing more. No dish is given a
/// description it does not have, a photograph it does not have, a diet nobody
/// declared or a spice level nobody set. The two empty states are told apart —
/// a restaurant with no menu is a different problem from a search that found
/// nothing — because the customer's next move differs.
///
/// Nothing here can be ordered. Module 10 ends at browsing, and the item sheet
/// says so in words rather than showing a dead button.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({
    required this.tripId,
    required this.restaurantId,
    this.restaurantName,
    super.key,
  });

  final String tripId;
  final String restaurantId;

  /// What the previous screen already knew, so the app bar has a title during
  /// the first request rather than a blank space.
  final String? restaurantName;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final ScrollController _scroll = ScrollController();

  /// One key per section heading, so a tap can measure where to scroll to and
  /// a scroll can work out which heading is at the top.
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};

  /// True while a tap-driven scroll is animating. The scroll listener is
  /// ignored during it, or the sections it passes through would each steal the
  /// highlight on the way to the one the customer asked for.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();

    _scroll.addListener(_syncSelectorToScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(menuControllerProvider.notifier)
          .open(tripId: widget.tripId, restaurantId: widget.restaurantId);
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_syncSelectorToScroll)
      ..dispose();
    super.dispose();
  }

  /// Which section heading is currently at (or just above) the top of the list.
  void _syncSelectorToScroll() {
    if (_jumping || !mounted) return;

    final List<MenuCategory> categories = ref
        .read(menuControllerProvider)
        .categories;

    if (categories.isEmpty) return;

    String? topmost;

    for (final MenuCategory category in categories) {
      final BuildContext? context = _sectionKeys[category.id]?.currentContext;

      if (context == null) continue;

      final RenderObject? box = context.findRenderObject();

      if (box is! RenderBox || !box.attached) continue;

      final double y = box.localToGlobal(Offset.zero).dy;

      // A heading counts as "the one we are in" until the next has reached the
      // top of the viewport. The 140 is the app bar and the selector row above
      // the list.
      if (y <= 140) {
        topmost = category.id;
      } else {
        break;
      }
    }

    // Before the first heading has scrolled past, the customer is in the first
    // section — not in none of them.
    ref
        .read(menuControllerProvider.notifier)
        .categorySelected(topmost ?? categories.first.id);
  }

  /// Takes the customer to a section they tapped.
  ///
  /// The list is a `ListView.builder`, so a heading twelve sections down has
  /// never been built and has no context to scroll to — which is why this
  /// cannot simply call `ensureVisible`. It steps towards the target a screen
  /// at a time until the builder has made the heading, then lands on it
  /// exactly.
  Future<void> _jumpTo(String categoryId) async {
    final List<MenuCategory> categories = ref
        .read(menuControllerProvider)
        .categories;

    final int target = categories.indexWhere(
      (MenuCategory c) => c.id == categoryId,
    );

    if (target < 0) return;

    final int from = categories.indexWhere(
      (MenuCategory c) => c.id == ref.read(menuControllerProvider).selectedCategoryId,
    );

    ref.read(menuControllerProvider.notifier).categorySelected(categoryId);

    // Read before the first await: a jump across a long menu is exactly the
    // large transition the OS "reduce motion" setting exists for, and asking
    // for it afterwards would be reading a BuildContext across an async gap.
    final Duration duration = FotgMotion.respectingReducedMotion(
      context,
      FotgMotion.normal,
    );

    _jumping = true;

    try {
      final bool forward = from < 0 || target > from;

      // Bounded so a bug here cannot spin: sixty screens is far longer than
      // any menu, and running out simply leaves the customer where they are.
      for (int step = 0; step < 60; step++) {
        if (!mounted || !_scroll.hasClients) return;

        if (_sectionKeys[categoryId]?.currentContext != null) break;

        final ScrollPosition position = _scroll.position;

        final double next =
            (position.pixels +
                    (forward ? 1 : -1) * position.viewportDimension * 0.9)
                .clamp(position.minScrollExtent, position.maxScrollExtent);

        // Already at the end in that direction, and the heading still is not
        // built. Nothing more to do.
        if (next == position.pixels) break;

        _scroll.jumpTo(next);

        await WidgetsBinding.instance.endOfFrame;
      }

      final BuildContext? heading = _sectionKeys[categoryId]?.currentContext;

      // The heading's own element, not this State's: the row may have been
      // recycled out of the list while the loop above was stepping.
      if (heading == null || !heading.mounted) return;

      await Scrollable.ensureVisible(
        heading,
        duration: duration,
        curve: FotgMotion.decelerate,
        // Flush with the top of the viewport, so the heading is not left
        // behind the selector that scrolled to it.
        alignment: 0,
      );
    } finally {
      _jumping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final MenuState state = ref.watch(menuControllerProvider);

    final String title =
        state.menu?.restaurant.name ?? widget.restaurantName ?? strings.menuTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        // The AppBar's automatic back button pops the Navigator without telling
        // go_router, which leaves the router with an empty match list and a
        // blank screen. This one goes through the router.
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: switch (state) {
          MenuState(isLoading: true) => const _Loading(),
          MenuState(failure: final MenuFailure failure) when !state.hasMenu =>
            _Failure(failure: failure),
          _ => _Loaded(
            state: state,
            scroll: _scroll,
            sectionKeys: _sectionKeys,
            onJumpTo: _jumpTo,
            tripId: widget.tripId,
            restaurantId: widget.restaurantId,
          ),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.state,
    required this.scroll,
    required this.sectionKeys,
    required this.onJumpTo,
    required this.tripId,
    required this.restaurantId,
  });

  final MenuState state;
  final ScrollController scroll;
  final Map<String, GlobalKey> sectionKeys;
  final ValueChanged<String> onJumpTo;

  /// Carried only so a tapped dish can be opened at the right URL.
  final String tripId;
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final MenuScreenController controller = ref.read(
      menuControllerProvider.notifier,
    );

    return Column(
      children: <Widget>[
        if (state.isOffline) _OfflineBanner(generatedAt: state.menu?.generatedAt),

        if (_orderingNotice(strings) case final String notice)
          _OrderingBanner(text: notice),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x4,
            FotgSpacing.x3,
            FotgSpacing.x4,
            FotgSpacing.x2,
          ),
          child: _MenuSearchField(
            text: state.searchTerm,
            onChanged: controller.searchChanged,
            onCleared: controller.clearSearch,
          ),
        ),

        if (state.isSearching)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),

        // The selector is absent, not empty, when there is nothing to select.
        if (state.categories.length > 1)
          MenuCategorySelector(
            categories: state.categories,
            selectedId: state.selectedCategoryId,
            onSelected: onJumpTo,
          ),

        Expanded(
          child: switch (state) {
            MenuState(isMenuEmpty: true) => _EmptyMenu(
              restaurant: state.menu?.restaurant.name ?? '',
            ),
            MenuState(isSearchEmpty: true) => _EmptySearch(
              term: state.menu?.appliedSearch ?? state.searchTerm,
              onClear: controller.clearSearch,
            ),
            _ => RefreshIndicator(
              onRefresh: controller.refresh,
              child: _MenuList(
                state: state,
                scroll: scroll,
                sectionKeys: sectionKeys,
                tripId: tripId,
                restaurantId: restaurantId,
              ),
            ),
          },
        ),
      ],
    );
  }

  /// What to say above the menu when an order could not be placed.
  ///
  /// Said before the customer has chosen a meal rather than after. Browsing
  /// stays open in every case except a permanent closure, because a customer
  /// planning tomorrow's drive has a good reason to read tonight's menu.
  String? _orderingNotice(AppStrings strings) =>
      switch (state.menu?.restaurant.ordering) {
        RestaurantOrderingState.openAccepting || null => null,
        RestaurantOrderingState.openPaused => strings.menuBrowseOnlyPaused,
        RestaurantOrderingState.closed => strings.menuBrowseOnlyClosed,
        RestaurantOrderingState.closedPermanently =>
          strings.menuBrowseOnlyPermanently,
        RestaurantOrderingState.unavailable => strings.menuUnavailableNow,
      };
}

/// The list itself: one heading and its dishes, repeated.
class _MenuList extends ConsumerWidget {
  const _MenuList({
    required this.state,
    required this.scroll,
    required this.sectionKeys,
    required this.tripId,
    required this.restaurantId,
  });

  final MenuState state;
  final ScrollController scroll;
  final Map<String, GlobalKey> sectionKeys;
  final String tripId;
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<_Row> rows = _flatten(state.categories, sectionKeys);

    return ListView.builder(
      controller: scroll,
      // Always scrollable, so pull-to-refresh works on a menu shorter than the
      // screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: FotgSpacing.x10),
      itemCount: rows.length,
      // Built lazily. A five-hundred-item menu builds the dozen rows on screen,
      // not five hundred cards nobody has scrolled to.
      itemBuilder: (BuildContext context, int index) => switch (rows[index]) {
        final _HeadingRow row => _SectionHeading(
          key: row.key,
          category: row.category,
        ),
        final _ItemRow row => MenuItemCard(
          item: row.item,
          // Module 11 replaced the read-only sheet with the real thing: a
          // customer taps a dish and configures it. The name travels so the
          // next screen's app bar is not blank while it loads.
          onTap: () => context.push(
            Routes.menuItemPath(tripId, restaurantId, row.item.id),
            extra: row.item.name,
          ),
        ),
      },
    );
  }

  /// Sections and their dishes as one flat list.
  ///
  /// A nested `ListView` per category would build every card in every category
  /// the moment it was laid out, which is exactly the cost this avoids.
  static List<_Row> _flatten(
    List<MenuCategory> categories,
    Map<String, GlobalKey> keys,
  ) => <_Row>[
    for (final MenuCategory category in categories) ...<_Row>[
      _HeadingRow(
        category: category,
        key: keys.putIfAbsent(category.id, GlobalKey.new),
      ),
      for (final MenuItem item in category.items) _ItemRow(item: item),
    ],
  ];
}

sealed class _Row {
  const _Row();
}

class _HeadingRow extends _Row {
  const _HeadingRow({required this.category, required this.key});

  final MenuCategory category;
  final GlobalKey key;
}

class _ItemRow extends _Row {
  const _ItemRow({required this.item});

  final MenuItem item;
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.category, super.key});

  final MenuCategory category;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      container: true,
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FotgSpacing.x4,
          FotgSpacing.x5,
          FotgSpacing.x4,
          FotgSpacing.x2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              category.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            // The operator's own words about the section, when they wrote any.
            if (category.description case final String description) ...<Widget>[
              const SizedBox(height: FotgSpacing.x1),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: FotgColors.neutral600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuSearchField extends StatefulWidget {
  const _MenuSearchField({
    required this.text,
    required this.onChanged,
    required this.onCleared,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final VoidCallback onCleared;

  @override
  State<_MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends State<_MenuSearchField> {
  late final TextEditingController _field = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(_MenuSearchField old) {
    super.didUpdateWidget(old);

    // Only when the state and the field have genuinely diverged — a clear
    // button, or a restored screen — never on every rebuild, which would move
    // the caret to the end of the line mid-word.
    if (widget.text != _field.text) {
      _field.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return TextField(
      controller: _field,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      // The server refuses anything longer; stopping at the same number means
      // a customer cannot type their way into an error.
      maxLength: 100,
      buildCounter:
          (
            _, {
            required int currentLength,
            required bool isFocused,
            required int? maxLength,
          }) => null,
      decoration: InputDecoration(
        isDense: true,
        hintText: strings.menuSearchHint,
        labelText: strings.menuSearchLabel,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: widget.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: strings.menuSearchClear,
                onPressed: () {
                  _field.clear();
                  widget.onCleared();
                },
              ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(FotgRadius.lg)),
        ),
      ),
    );
  }
}

/// The restaurant has published nothing. Not an error — a fact about them.
class _EmptyMenu extends StatelessWidget {
  const _EmptyMenu({required this.restaurant});

  final String restaurant;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return _Placeholder(
      icon: Icons.menu_book_outlined,
      title: strings.menuEmptyTitle,
      body: strings.menuEmptyBody(restaurant),
    );
  }
}

/// There is a menu; this search found none of it. A different problem with a
/// different answer, which is why it is a different screen.
class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.term, required this.onClear});

  final String term;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return _Placeholder(
      icon: Icons.search_off_rounded,
      title: strings.menuSearchEmptyTitle,
      body: strings.menuSearchEmptyBody(term),
      action: TextButton(
        onPressed: onClear,
        child: Text(strings.menuSearchEmptyAction),
      ),
    );
  }
}

class _Failure extends ConsumerWidget {
  const _Failure({required this.failure});

  final MenuFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final MenuState state = ref.watch(menuControllerProvider);

    final (String title, String body) = switch (failure) {
      MenuFailure.withdrawn => (
        strings.restaurantGoneTitle,
        strings.restaurantGoneBody,
      ),
      MenuFailure.notFound => (
        strings.restaurantGoneTitle,
        strings.restaurantGoneBody,
      ),
      MenuFailure.outsideRoute => (
        strings.restaurantOutsideRouteTitle,
        strings.restaurantOutsideRouteBody,
      ),
      MenuFailure.searchRejected => (
        strings.menuSearchEmptyTitle,
        strings.menuSearchTooLong,
      ),
      _ => (strings.menuErrorTitle, strings.menuErrorBody),
    };

    return _Placeholder(
      icon: Icons.error_outline_rounded,
      title: title,
      body: body,
      action: state.isRetryable
          ? FilledButton(
              onPressed: () => ref.read(menuControllerProvider.notifier).retry(),
              child: Text(strings.menuTryAgain),
            )
          : TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.menuBackToRestaurant),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(icon, size: 40, color: FotgColors.neutral400),
            ),
            const SizedBox(height: FotgSpacing.x4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: FotgColors.neutral600,
              ),
            ),
            if (action case final Widget button) ...<Widget>[
              const SizedBox(height: FotgSpacing.x5),
              button,
            ],
          ],
        ),
      ),
    );
  }
}

/// Stale prices, said out loud.
///
/// A menu read from a failed refresh is still worth showing — but it is never
/// shown silently, because a price from an hour ago presented as current is
/// the kind of thing a customer discovers at the counter.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.generatedAt});

  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Container(
      width: double.infinity,
      color: FotgColors.warningSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x4,
        vertical: FotgSpacing.x2,
      ),
      child: Text(
        strings.menuOfflineCached,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: FotgColors.warning),
      ),
    );
  }
}

class _OrderingBanner extends StatelessWidget {
  const _OrderingBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: FotgColors.neutral100,
    padding: const EdgeInsets.symmetric(
      horizontal: FotgSpacing.x4,
      vertical: FotgSpacing.x3,
    ),
    child: Row(
      children: <Widget>[
        const ExcludeSemantics(
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: FotgColors.neutral600,
          ),
        ),
        const SizedBox(width: FotgSpacing.x2),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: FotgColors.neutral800),
          ),
        ),
      ],
    ),
  );
}
