import 'package:flutter/material.dart';

import '../../features/home/home_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/trips/trips_screen.dart';
import '../theme/tokens.dart';

/// One destination in the bottom navigation.
class FotgDestination {
  const FotgDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    required this.builder,
  });

  final String label;
  final IconData icon;

  /// A filled variant for the selected state — the shape changes, not only the
  /// colour, so the current tab is distinguishable without relying on hue.
  final IconData selectedIcon;
  final String route;
  final WidgetBuilder builder;
}

/// The customer app's navigation architecture.
///
/// Five destinations is the practical ceiling for a bottom bar; beyond that the
/// targets get too narrow for a thumb. Later modules attach real screens to these
/// routes rather than adding new top-level tabs.
final List<FotgDestination> fotgDestinations = <FotgDestination>[
  FotgDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    route: '/',
    builder: (_) => const HomeScreen(),
  ),
  FotgDestination(
    label: 'Trips',
    icon: Icons.route_outlined,
    selectedIcon: Icons.route_rounded,
    route: '/trips',
    builder: (_) => const TripsScreen(),
  ),
  FotgDestination(
    label: 'Orders',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    route: '/orders',
    builder: (_) => const OrdersScreen(),
  ),
  FotgDestination(
    label: 'Alerts',
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications_rounded,
    route: '/notifications',
    builder: (_) => const NotificationsScreen(),
  ),
  FotgDestination(
    label: 'Profile',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    route: '/profile',
    builder: (_) => const ProfileScreen(),
  ),
];

/// The app shell: a bottom navigation bar over an IndexedStack.
///
/// IndexedStack rather than swapping the child, so each tab keeps its scroll
/// position and state when you come back to it — which is what a native app does
/// and what a traveller expects when they flick between the map and their order.
class FotgAppShell extends StatefulWidget {
  const FotgAppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<FotgAppShell> createState() => _FotgAppShellState();
}

class _FotgAppShellState extends State<FotgAppShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final Duration duration = FotgMotion.respectingReducedMotion(
      context,
      FotgMotion.fast,
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          for (final FotgDestination destination in fotgDestinations)
            Builder(builder: destination.builder),
        ],
      ),
      bottomNavigationBar: SafeArea(
        // Only the bottom inset: on a gesture-navigation phone the bar must clear
        // the home indicator, and on iOS it must clear the home bar.
        top: false,
        left: false,
        right: false,
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int next) => setState(() => _index = next),
          animationDuration: duration,
          destinations: <Widget>[
            for (final FotgDestination destination in fotgDestinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
                tooltip: destination.label,
              ),
          ],
        ),
      ),
    );
  }
}
