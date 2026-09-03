import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/placeholder/coming_soon_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/trips/trips_screen.dart';
import '../../shared/widgets/customer_shell.dart';
import 'routes.dart';

/// The customer app's router.
///
/// `StatefulShellRoute.indexedStack` is the specific choice that makes the tabs
/// behave natively: each branch keeps its own `Navigator` and its own state, so
/// scrolling Orders halfway, visiting Profile and coming back returns to where
/// you were rather than to the top of a rebuilt list. A plain `IndexedStack` of
/// screens would preserve widget state but give every tab one shared navigation
/// history, which breaks Android's back button.
///
/// Nested routes for later modules attach beneath the branch they belong to —
/// `/orders/:reference` under the Orders branch — and inherit its back stack for
/// free.
GoRouter createRouter({
  String initialLocation = Routes.home,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    navigatorKey: navigatorKey,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) => CustomerShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.home,
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.trips,
                builder: (BuildContext context, GoRouterState state) =>
                    const TripsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.orders,
                builder: (BuildContext context, GoRouterState state) =>
                    const OrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.notifications,
                builder: (BuildContext context, GoRouterState state) =>
                    const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.profile,
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // Pushed over the shell rather than inside a branch, so it covers the
      // bottom bar — it is a destination, not a tab.
      GoRoute(
        path: Routes.comingSoon,
        builder: (BuildContext context, GoRouterState state) =>
            ComingSoonScreen(
              feature: state.uri.queryParameters['feature'] ?? 'This feature',
              module: state.uri.queryParameters['module'] ?? 'a later module',
            ),
      ),
    ],
  );
}
