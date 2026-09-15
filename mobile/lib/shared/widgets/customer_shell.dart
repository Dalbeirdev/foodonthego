import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../state/connectivity.dart';
import '../state/providers.dart';
import 'offline_banner.dart';

/// One destination in the bottom bar.
class CustomerDestination {
  const CustomerDestination({
    required this.icon,
    required this.selectedIcon,
    required this.labelOf,
    required this.analyticsEvent,
  });

  final IconData icon;

  /// A filled variant for the selected state: the shape changes as well as the
  /// colour, so the current tab is identifiable without relying on hue.
  final IconData selectedIcon;
  final String Function(AppStrings) labelOf;
  final String? analyticsEvent;
}

const List<CustomerDestination> customerDestinations = <CustomerDestination>[
  CustomerDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    labelOf: _homeLabel,
    analyticsEvent: null,
  ),
  CustomerDestination(
    icon: Icons.route_outlined,
    selectedIcon: Icons.route_rounded,
    labelOf: _tripsLabel,
    analyticsEvent: AnalyticsEvents.tripsTabOpened,
  ),
  CustomerDestination(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    labelOf: _ordersLabel,
    analyticsEvent: AnalyticsEvents.ordersTabOpened,
  ),
  CustomerDestination(
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications_rounded,
    labelOf: _notificationsLabel,
    analyticsEvent: AnalyticsEvents.notificationsTabOpened,
  ),
  CustomerDestination(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    labelOf: _profileLabel,
    analyticsEvent: AnalyticsEvents.profileTabOpened,
  ),
];

String _homeLabel(AppStrings s) => s.navHome;
String _tripsLabel(AppStrings s) => s.navTrips;
String _ordersLabel(AppStrings s) => s.navOrders;
String _notificationsLabel(AppStrings s) => s.navNotifications;
String _profileLabel(AppStrings s) => s.navProfile;

/// The customer app's chrome: an offline banner over the active branch, with the
/// bottom navigation beneath.
class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final Analytics analytics = ref.watch(analyticsProvider);

    final ConnectivityStatus status = ref
        .watch(connectivityStatusProvider)
        .maybeWhen(
          data: (ConnectivityStatus value) => value,
          orElse: () => ref.read(connectivityServiceProvider).status,
        );

    return PopScope(
      // Android's back button on a non-home tab should return to Home, the way a
      // native app does — not exit the application from the third tab.
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && shell.currentIndex != 0) shell.goBranch(0);
      },
      child: Scaffold(
        body: Column(
          children: <Widget>[
            // Inside a SafeArea for the top inset only: the banner must clear the
            // notch, while the branch below manages its own insets.
            SafeArea(bottom: false, child: OfflineBanner(status: status)),
            Expanded(child: shell),
          ],
        ),
        bottomNavigationBar: _BottomNavigation(
          shell: shell,
          strings: strings,
          onSelected: (int index) {
            final CustomerDestination destination = customerDestinations[index];
            if (destination.analyticsEvent != null &&
                index != shell.currentIndex) {
              analytics.log(destination.analyticsEvent!);
            }
            // `initialLocation: true` when re-tapping the current tab pops that
            // branch back to its root — the standard "tap the tab you are on to
            // go home" gesture. Repeated taps are therefore idempotent, which is
            // also what makes double-tapping harmless.
            shell.goBranch(index, initialLocation: index == shell.currentIndex);
          },
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.shell,
    required this.strings,
    required this.onSelected,
  });

  final StatefulNavigationShell shell;
  final AppStrings strings;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: SafeArea(
        // Bottom inset only, so the bar clears the home indicator on iOS and the
        // gesture pill on Android without adding space at the top.
        top: false,
        left: false,
        right: false,
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: onSelected,
          animationDuration: FotgMotion.respectingReducedMotion(
            context,
            FotgMotion.normal,
          ),
          destinations: <Widget>[
            for (final CustomerDestination destination in customerDestinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.labelOf(strings),
                tooltip: destination.labelOf(strings),
              ),
          ],
        ),
      ),
    );
  }
}
