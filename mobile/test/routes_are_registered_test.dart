// Every path this app can build is a path the router knows.
//
// WHY THIS FILE EXISTS. `Routes` declared `/profile/edit`, `/profile/addresses`
// and `/profile/addresses/form` for sixteen modules. None of them was ever
// registered with the router — those screens are pushed over the Profile branch
// with a plain Navigator push — but the constants read exactly like routes that
// exist, and twice they were used as if they did. Once in shipped code: the trip
// planner's "Manage saved addresses" link put the customer on Page Not Found.
// Once in a device test, which is how the shipped one was finally noticed.
//
// Nothing in the suite could have caught either, because nothing ever asked the
// router whether it knew a path before something navigated to it. This asks.
//
// IT TESTS MATCHING, NOT SCREENS. No widget is built and no repository is
// called, so a path stays covered here whether or not its screen can be pumped
// in a test harness — which is the difference between a guard that is kept up
// to date and one that is quietly deleted the first time it is inconvenient.
//
// WHAT IT DOES NOT COVER, STATED SO THE TITLE IS NOT READ AS MORE THAN IT IS.
// One navigation in the app composes its path at run time rather than from a
// constant: discovery_screen.dart pushes '${state.uri.path}/${restaurant.id}',
// relative to wherever discovery is mounted. That is deliberate — the detail
// route is nested under discovery, and building it from the live location is
// what keeps it nested — but it cannot be checked here, because the path does
// not exist until a customer is standing on the list. Every path built from
// `Routes` is covered; that one is not.
//
// TWO CHECKS, BECAUSE ONE OF THEM ROTS. The named list below is readable and
// says which member produced which path, but it only covers what somebody
// remembered to add. So a second check reads `routes.dart` itself and asserts
// that every absolute path literal in it is matched. Dart has no run-time
// reflection over static members, and a guard that quietly covers nothing is
// worse than no guard — reading the source is the only way a constant added
// next year is checked without anyone choosing to check it.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/routing/app_router.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/shared/state/providers.dart';
import 'package:go_router/go_router.dart';

void main() {
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    // The only override needed: the real session store reads platform secure
    // storage, which does not exist in a unit test. Nothing else is touched —
    // the router under test is the app's own, built by the app's own factory.
    container = ProviderContainer(
      // The list type is inferred: `Override` is not exported from
      // flutter_riverpod, same as in test/support/harness.dart.
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    router = container.read(
      Provider<GoRouter>((Ref ref) => createRouter(ref: ref)),
    );
  });

  tearDown(() => container.dispose());

  bool knows(String path) =>
      !router.configuration.findMatch(Uri.parse(path)).isError;

  // Ids are arbitrary: the router matches on shape, and a real id would only
  // make this read as though it needed one.
  const String tripId = 'trp_1';
  const String restaurantId = 'rst_1';
  const String itemId = 'itm_1';
  const String orderId = 'ord_1';
  const String checkoutId = 'chk_1';

  final Map<String, String> paths = <String, String>{
    'home': Routes.home,
    'welcome': Routes.welcome,
    'authPhone': Routes.authPhone,
    'authOtp': Routes.authOtp,
    'authRegister': Routes.authRegister,
    'trips': Routes.trips,
    'orders': Routes.orders,
    'notifications': Routes.notifications,
    'profile': Routes.profile,
    'comingSoon': Routes.comingSoon,
    'comingSoonFor': Routes.comingSoonFor(
      feature: 'Payment methods',
      module: 'Module 11 — Payments',
    ),
    'tripPlanPath': Routes.tripPlanPath,
    'tripDetailPath': Routes.tripDetailPath(tripId),
    'tripRoutePath': Routes.tripRoutePath(tripId),
    'tripRestaurantsPath': Routes.tripRestaurantsPath(tripId),
    'restaurantDetailPath': Routes.restaurantDetailPath(tripId, restaurantId),
    'restaurantMenuPath': Routes.restaurantMenuPath(tripId, restaurantId),
    'menuItemPath': Routes.menuItemPath(tripId, restaurantId, itemId),
    'tripCartPath': Routes.tripCartPath(tripId),
    'tripPickupPath': Routes.tripPickupPath(tripId),
    'tripCheckoutPath': Routes.tripCheckoutPath(tripId),
    'tripPaymentPath': Routes.tripPaymentPath(tripId, checkoutId),
    'orderConfirmationPath': Routes.orderConfirmationPath(orderId),
    'orderTrackingPath': Routes.orderTrackingPath(orderId),
  };

  group('every path Routes can build', () {
    paths.forEach((String name, String path) {
      test('$name — $path — is registered', () {
        expect(
          knows(path),
          isTrue,
          reason:
              'Routes.$name produces "$path", and the router does not match it. '
              'Anything navigating there lands on Page Not Found.',
        );
      });
    });

    test('every unauthenticated route is one of them', () {
      // This set gates the redirect. A path in it that the router cannot match
      // would let an unauthenticated visitor through to nothing.
      for (final String path in Routes.unauthenticated) {
        expect(
          knows(path),
          isTrue,
          reason: '$path is unauthenticated but unregistered',
        );
      }
    });
  });

  group('every absolute path literal in routes.dart', () {
    // Interpolations stand in for ids: the router matches on shape, so any
    // non-empty segment does.
    String concrete(String literal) =>
        literal.replaceAll(RegExp(r'\$\{?\w+\}?'), 'x');

    List<String> literalsIn(String source) {
      // Line comments first. This very file's header quotes paths that were
      // deleted precisely because they were never registered, and a scanner
      // that read its own explanation would fail on it.
      final String code = source
          .split('\n')
          .map((String line) => line.replaceFirst(RegExp(r'\s*//.*'), ''))
          .join('\n');

      return RegExp("'(/[^']*)'")
          .allMatches(code)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet()
          .toList(growable: false);
    }

    test('is registered', () {
      final String source = File('lib/core/routing/routes.dart')
          .readAsStringSync();
      final List<String> literals = literalsIn(source);

      // The scan finding nothing would make every assertion below vacuous, and
      // a renamed file or a changed working directory would do exactly that.
      expect(
        literals.length,
        greaterThanOrEqualTo(10),
        reason: 'the scan found $literals — it is not reading routes.dart',
      );

      final List<String> unknown = literals
          .map(concrete)
          .where((String path) => !knows(path))
          .toList(growable: false);

      expect(
        unknown,
        isEmpty,
        reason:
            'routes.dart declares these paths and the router matches none of '
            'them. Either register them or delete them; a constant naming a '
            'path nobody registered is what put a customer on Page Not Found.',
      );
    });
  });

  group('the check itself', () {
    // Without these, every assertion above would pass against a matcher that
    // says yes to everything, and the file would be decoration.
    test('an unregistered path is reported as unknown', () {
      expect(knows('/profile/addresses'), isFalse);
      expect(knows('/profile/edit'), isFalse);
      expect(knows('/nothing/here'), isFalse);
    });

    test('a path one segment too deep is reported as unknown', () {
      expect(knows('${Routes.tripPlanPath}/extra'), isFalse);
    });

    test('the source scan would have caught the deleted constants', () {
      // The exact three lines this file exists because of, fed to the scanner
      // as they were written. Without this, the scan could be matching nothing
      // and every run would still be green.
      final List<String> found = _scanFixture("""
  static const String profileEditPath = '/profile/edit';
  static const String savedAddressesPath = '/profile/addresses';
  static const String addressFormPath = '/profile/addresses/form';
""");

      expect(found, hasLength(3));
      expect(found.where(knows), isEmpty);
    });
  });
}

/// The scanner in *every absolute path literal in routes.dart*, over a given
/// string rather than the file, so the control above can feed it the three
/// constants this file exists because of.
List<String> _scanFixture(String source) {
  final String code = source
      .split('\n')
      .map((String line) => line.replaceFirst(RegExp(r'\s*//.*'), ''))
      .join('\n');

  return RegExp("'(/[^']*)'")
      .allMatches(code)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet()
      .toList(growable: false);
}
