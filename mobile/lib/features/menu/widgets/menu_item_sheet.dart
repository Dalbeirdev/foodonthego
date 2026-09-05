import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/restaurant_menu.dart';
import '../../../shared/state/menu_controller.dart';
import 'menu_item_badges.dart';

/// One dish, read-only.
///
/// Module 10 ends at browsing, and this sheet is where that boundary is
/// visible. There is no quantity stepper, no variant list, no add-on picker and
/// no "Add to cart" — not even a disabled one, because a greyed-out button
/// promises a cart that does not exist and invites a customer to keep tapping
/// it. A plain sentence says ordering is not open yet.
class MenuItemSheet extends ConsumerWidget {
  const MenuItemSheet({super.key});

  /// Opens the sheet for [item] and keeps it open until dismissed.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    MenuItem item,
  ) async {
    // Fired before the sheet is shown so the request is already in flight
    // while the animation runs.
    unawaited(ref.read(menuControllerProvider.notifier).openItem(item));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const MenuItemSheet(),
    );

    ref.read(menuControllerProvider.notifier).closeItem();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final MenuItemPreviewState state = ref.watch(
      menuControllerProvider.select((MenuState s) => s.preview),
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x4,
            0,
            FotgSpacing.x4,
            FotgSpacing.x6,
          ),
          child: switch (state) {
            MenuItemPreviewState(failure: final MenuItemFailure failure)
                when state.item == null =>
              _Failure(failure: failure),
            MenuItemPreviewState(item: final MenuItem item) => _Body(
              item: item,
              state: state,
              strings: strings,
            ),
            _ => const Padding(
              padding: EdgeInsets.all(FotgSpacing.x8),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item, required this.state, required this.strings});

  final MenuItem item;
  final MenuItemPreviewState state;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (item.imageUrl case final String url) ...<Widget>[
          ClipRRect(
            borderRadius: FotgRadius.card,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => Container(
                  color: FotgColors.neutral100,
                  child: const Icon(
                    Icons.restaurant_outlined,
                    color: FotgColors.neutral400,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: FotgSpacing.x4),
        ],

        Text(
          item.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: FotgSpacing.x2),

        Semantics(
          container: true,
          label: item.price.spokenLabel(),
          excludeSemantics: true,
          child: Text(
            item.price.format(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        if (item.isSoldOut) ...<Widget>[
          const SizedBox(height: FotgSpacing.x3),
          _Notice(
            icon: Icons.remove_shopping_cart_outlined,
            text: strings.menuSoldOut,
            foreground: FotgColors.error,
            background: FotgColors.errorSurface,
          ),
        ],

        // The operator's own words, or nothing at all. This is the one place a
        // long description is shown in full rather than clipped to two lines.
        if (item.hasDescription) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          Text(
            item.description!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: FotgColors.neutral600,
            ),
          ),
        ],

        const SizedBox(height: FotgSpacing.x4),
        MenuItemBadges(item: item),

        const SizedBox(height: FotgSpacing.x5),

        // Where Module 10 stops. Said in a sentence rather than shown as a
        // disabled button.
        _Notice(
          icon: Icons.schedule_outlined,
          text: strings.menuItemBrowseOnly,
          body: strings.menuItemBrowseOnlyBody,
          foreground: FotgColors.info,
          background: FotgColors.infoSurface,
        ),

        if (state.isLoading) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          // The card's copy is on screen while the fresh one loads. A thin bar
          // rather than a spinner over the content, because the content is
          // usable and almost certainly correct.
          const LinearProgressIndicator(minHeight: 2),
        ],

        if (state.failure != null && state.item != null) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          _Notice(
            icon: Icons.wifi_off_outlined,
            text: strings.menuItemErrorTitle,
            body: strings.menuErrorBody,
            foreground: FotgColors.warning,
            background: FotgColors.warningSurface,
          ),
          if (state.isRetryable) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            TextButton(
              onPressed: () =>
                  ref.read(menuControllerProvider.notifier).retryItem(),
              child: Text(strings.menuTryAgain),
            ),
          ],
        ],
      ],
    );
  }
}

class _Failure extends ConsumerWidget {
  const _Failure({required this.failure});

  final MenuItemFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final bool gone =
        failure == MenuItemFailure.notFound ||
        failure == MenuItemFailure.unavailable;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            gone ? strings.menuItemGoneTitle : strings.menuItemErrorTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FotgSpacing.x2),
          Text(
            gone ? strings.menuItemGoneBody : strings.menuErrorBody,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: FotgColors.neutral600),
          ),
          const SizedBox(height: FotgSpacing.x4),
          Row(
            children: <Widget>[
              // No retry on a withdrawn item: it will not come back because
              // the customer pressed a button.
              if (!gone)
                FilledButton(
                  onPressed: () =>
                      ref.read(menuControllerProvider.notifier).retryItem(),
                  child: Text(strings.menuTryAgain),
                ),
              if (!gone) const SizedBox(width: FotgSpacing.x2),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.menuItemClose),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.foreground,
    required this.background,
    this.body,
  });

  final IconData icon;
  final String text;
  final String? body;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FotgSpacing.x3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: FotgRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(child: Icon(icon, size: 18, color: foreground)),
          const SizedBox(width: FotgSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (body case final String detail) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x1),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: FotgColors.neutral600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
