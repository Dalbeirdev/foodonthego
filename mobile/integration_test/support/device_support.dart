// Shared machinery for the on-device runs.
//
// These are not widget tests. A widget test proves the code is right against a
// repository we wrote; this proves the *app* is right — the real widget tree,
// on a real handset, over real HTTP, against a real Laravel server and a real
// MySQL database. Nothing here is stubbed.
//
// What lives in this file is the part that is awkward on a device rather than
// the part being tested: obtaining a session, and putting the app in front of
// the screen under test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/app.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/app_router.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/data/repositories/api_customer_repository.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/shared/state/providers.dart';
import 'package:go_router/go_router.dart';

/// The token the run was handed.
///
/// A device cannot complete the sign-in flow on its own: the development OTP
/// provider writes the code to a log file on the *server*, which is the correct
/// design — it is what stops that provider ever being usable in production —
/// and there is deliberately no endpoint that hands a code back over HTTP.
///
/// So the operator signs a persona in on the host first, with
/// `dart run tool/issue_token.dart`, and passes the result here. Authentication
/// itself is Module 03's verification and has its own; what this run is for is
/// what happens *after* a customer is signed in.
const String sessionToken = String.fromEnvironment('FOTG_TEST_TOKEN');

/// Fails the run with an explanation rather than an assertion nobody can read.
void requireToken() {
  if (sessionToken.isEmpty) {
    fail(
      'No session token. Run `dart run --define=FOTG_API_BASE_URL=<url> '
      'tool/issue_token.dart` on the machine running the backend, then pass '
      'the token it prints as --dart-define=FOTG_TEST_TOKEN=...',
    );
  }
}

/// An HTTP client authenticated as that customer, for the parts of a run that
/// set the world up or read it back afterwards.
///
/// Deliberately separate from the app's own client: what the app does with its
/// client is what is being tested, and a run that shared one could not tell the
/// difference between the app writing a cart row and this file writing it.
ApiClient apiAs() => ApiClient(tokenReader: () async => sessionToken);

/// Who the token belongs to, asked of the server rather than assumed.
Future<Customer> whoAmI(ApiClient client) =>
    ApiCustomerRepository(client).profile();

/// Launches the real app, already signed in, at [location].
///
/// Two overrides, and no more:
///
///  * the session store, because there is no way to write a Keychain entry from
///    a test process, and every other route to a signed-in app would mean
///    driving the OTP screens the device cannot complete;
///  * the router's initial location, because the journey up to this screen is
///    verified by the modules that own it, and re-driving it here would make a
///    Module 11 failure indistinguishable from a Module 07 one.
///
/// Everything below — the repositories, the HTTP client, the controllers, the
/// widgets — is exactly what ships.
Future<void> launchSignedIn(
  WidgetTester tester, {
  required Customer customer,
  required String location,
}) async {
  final SessionStore store = InMemorySessionStore();
  await store.write(AuthSession(accessToken: sessionToken, customer: customer));

  await tester.pumpWidget(
    ProviderScope(
      // The list type is inferred, as in the widget harness: `Override` is not
      // exported from flutter_riverpod.
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        routerProvider.overrideWith((Ref ref) {
          final GoRouter router = createRouter(
            ref: ref,
            initialLocation: location,
          );
          ref.onDispose(router.dispose);
          return router;
        }),
      ],
      child: const FoodOnTheGoApp(),
    ),
  );

  await settle(tester);
}

/// `pumpAndSettle` cannot be used while the app is talking to a server: it
/// pumps until no frame is scheduled, and a request in flight schedules none,
/// so it returns before the answer arrives — or times out on a progress
/// indicator that is legitimately still spinning.
///
/// This pumps in real time instead, which is what a device actually does.
Future<void> settle(
  WidgetTester tester, {
  Duration duration = const Duration(seconds: 6),
}) async {
  final DateTime deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Pumps until [finder] matches, or gives up with a legible message.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? describe,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 150));
  }

  fail('Timed out waiting for ${describe ?? finder.toString()}');
}

/// The item screen is a `ListView`; anything below the fold is never built, so
/// a finder for it matches nothing until it has been scrolled to.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;

  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls to a control and taps it, the way a thumb would.
Future<void> tapAt(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
}
