import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/otp_verification_screen.dart';
import '../../features/auth/phone_entry_screen.dart';
import '../../features/auth/registration_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/placeholder/coming_soon_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../features/discovery/discovery_screen.dart';
import '../../features/restaurant/restaurant_detail_screen.dart';
import '../../features/routes/route_screen.dart';
import '../../features/trips/trip_detail_screen.dart';
import '../../features/trips/trip_planner_screen.dart';
import '../../features/trips/trips_screen.dart';
import '../../shared/state/auth_controller.dart';
import '../../shared/state/auth_state.dart';
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
  required Ref ref,
  String initialLocation = Routes.home,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    navigatorKey: navigatorKey,

    // Re-evaluates `redirect` whenever the session changes, so signing out —
    // from anywhere, including a 401 on a background request — moves the app to
    // the welcome screen without any screen having to navigate.
    refreshListenable: AuthChangeNotifier(ref),

    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authControllerProvider);
      final String location = state.matchedLocation;
      final bool onAuthRoute = Routes.unauthenticated.contains(location);

      // Still reading secure storage. Redirecting now would send a returning
      // customer to the welcome screen for a frame before bouncing them back —
      // the flash this module exists to avoid. Staying put is correct: the
      // splash-equivalent is rendered by the shell below.
      if (auth is AuthRestoring) return null;

      if (!auth.isAuthenticated) {
        return onAuthRoute ? null : Routes.welcome;
      }

      // Signed in and looking at a sign-in screen: nothing to do here.
      return onAuthRoute ? Routes.home : null;
    },

    routes: <RouteBase>[
      GoRoute(
        path: Routes.welcome,
        builder: (BuildContext context, GoRouterState state) =>
            const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.authPhone,
        builder: (BuildContext context, GoRouterState state) =>
            const PhoneEntryScreen(),
      ),
      GoRoute(
        path: Routes.authOtp,
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;

          // Reached without arguments — a deep link, or a hot restart mid-flow.
          // The screen cannot work without a number to verify, so the flow
          // restarts rather than rendering a form bound to nothing.
          if (extra is! OtpScreenArguments) return const PhoneEntryScreen();

          return OtpVerificationScreen(arguments: extra);
        },
      ),
      GoRoute(
        path: Routes.authRegister,
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          if (extra is! RegistrationArguments) return const PhoneEntryScreen();

          return RegistrationScreen(arguments: extra);
        },
      ),
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
                routes: <RouteBase>[
                  // Declared first. Otherwise "/trips/plan" matches `:tripId`
                  // and the planner becomes a detail screen for a journey
                  // called "plan".
                  GoRoute(
                    path: Routes.tripPlan,
                    builder: (BuildContext context, GoRouterState state) =>
                        const TripPlannerScreen(),
                  ),
                  GoRoute(
                    path: Routes.tripDetail,
                    builder: (BuildContext context, GoRouterState state) =>
                        TripDetailScreen(
                          tripId: state.pathParameters['tripId'] ?? '',
                        ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: Routes.tripRoute,
                        builder: (BuildContext context, GoRouterState state) =>
                            RouteScreen(
                              tripId: state.pathParameters['tripId'] ?? '',
                            ),
                        routes: <RouteBase>[
                          GoRoute(
                            path: Routes.tripRestaurants,
                            builder:
                                (BuildContext context, GoRouterState state) =>
                                    DiscoveryScreen(
                                      tripId:
                                          state.pathParameters['tripId'] ?? '',
                                    ),
                            routes: <RouteBase>[
                              GoRoute(
                                path: Routes.restaurantDetail,
                                builder:
                                    (
                                      BuildContext context,
                                      GoRouterState state,
                                    ) => RestaurantDetailScreen(
                                      tripId:
                                          state.pathParameters['tripId'] ?? '',
                                      restaurantId:
                                          state
                                              .pathParameters['restaurantId'] ??
                                          '',
                                      // What the card already knew, handed
                                      // over so the transition has a name and
                                      // a detour in it. Never authoritative:
                                      // the screen asks the server and
                                      // replaces it.
                                      preview:
                                          state.extra is DiscoveredRestaurant
                                          ? state.extra as DiscoveredRestaurant
                                          : null,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
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

/// Bridges Riverpod's auth state to go_router's [Listenable]-based refresh.
///
/// go_router re-runs `redirect` when this notifies. Without it the guard would
/// only be consulted on an explicit navigation, so a session that ended in the
/// background would leave the customer looking at a screen they are no longer
/// entitled to until they happened to tap something.
class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(this._ref) {
    _subscription = _ref.listen<AuthState>(authControllerProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      // Only structural changes matter. A refreshed profile with the same
      // sign-in status must not re-run the guard and rebuild the tree.
      if (previous?.isAuthenticated != next.isAuthenticated ||
          (previous is AuthRestoring) != (next is AuthRestoring)) {
        notifyListeners();
      }
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
