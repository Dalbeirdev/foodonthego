import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';

import 'support/harness.dart';

const HomeDashboard _dashboard = HomeDashboard(
  customer: CustomerSummary(fullName: 'Ravi Kumar'),
);

/// What happens between launches: restoring a session, ending one, and being
/// told by the server that one is over.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeAuthRepository auth,
    required SessionStore store,
    bool signedIn = false,
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: auth,
        sessionStore: store,
        signedIn: signedIn,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('restoring a session on launch', () {
    testWidgets('a stored session goes straight to the app', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      final InMemorySessionStore store = InMemorySessionStore();

      await pump(tester, auth: auth, store: store, signedIn: true);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Eat well on the road'), findsNothing);
    });

    testWidgets('the stored session is confirmed against the server', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();

      await pump(
        tester,
        auth: auth,
        store: InMemorySessionStore(),
        signedIn: true,
      );

      // Trusting storage alone would show a signed-in shell to somebody whose
      // token was revoked while the app was closed.
      expect(auth.currentCustomerCount, 1);
    });

    testWidgets('a token the server rejects ends the session', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository()
        ..nextCurrentCustomerError = const ApiException(
          code: ApiErrorCode.unauthenticated,
          message: 'Authentication is required.',
          status: 401,
        );
      final InMemorySessionStore store = InMemorySessionStore();

      await pump(tester, auth: auth, store: store, signedIn: true);

      expect(find.text('Eat well on the road'), findsOneWidget);
      expect(
        find.text('You were signed out. Please sign in again.'),
        findsOneWidget,
      );
      expect(await store.read(), isNull);
    });

    testWidgets('a backend outage does not sign everybody out', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository()
        ..nextCurrentCustomerError = const ApiException.network();
      final InMemorySessionStore store = InMemorySessionStore();

      await pump(tester, auth: auth, store: store, signedIn: true);

      // A traveller in a tunnel keeps their session; only the server saying
      // "no" ends it.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(await store.read(), isNotNull);
    });

    testWidgets('an already-expired token is discarded without asking', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      final InMemorySessionStore store = InMemorySessionStore();
      await store.write(
        AuthSession(
          accessToken: 'stale',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
          customer: FakeAuthRepository.sampleCustomer,
        ),
      );

      await pump(tester, auth: auth, store: store);

      expect(find.text('Eat well on the road'), findsOneWidget);
      // The server told us when it would stop working, so there is no request.
      expect(auth.currentCustomerCount, 0);
      expect(await store.read(), isNull);
    });

    testWidgets('an empty store lands on welcome, not on a spinner', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        auth: FakeAuthRepository(),
        store: InMemorySessionStore(),
      );

      expect(find.text('Eat well on the road'), findsOneWidget);
    });
  });

  group('the profile shows the signed-in account', () {
    testWidgets('name and masked number come from the session', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        auth: FakeAuthRepository(),
        store: InMemorySessionStore(),
        signedIn: true,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ravi Kumar'), findsWidgets);
      // The same mask the server produces, so the number reads identically on
      // the OTP screen and here.
      expect(find.text('+91 ••••••3210'), findsOneWidget);
      // Never the full number, even on the account's own screen.
      expect(find.text('+919876543210'), findsNothing);
    });

    testWidgets('a customer with one name gets one initial, not a crash', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        auth: FakeAuthRepository(
          customer: const Customer(
            id: 'u1',
            firstName: 'Ravi',
            phone: '+919876543210',
          ),
        ),
        store: InMemorySessionStore(),
        signedIn: true,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('R'), findsOneWidget);
    });
  });

  group('signing out', () {
    Future<void> openProfile(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();

      // Sign out sits below the settings list, so it has to be scrolled to on a
      // phone-sized surface before it can be tapped.
      await tester.dragUntilVisible(
        find.widgetWithText(OutlinedButton, 'Sign out'),
        find.byType(ListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('asks before ending the session', (WidgetTester tester) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      await pump(
        tester,
        auth: auth,
        store: InMemorySessionStore(),
        signedIn: true,
      );
      await openProfile(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Cancelled means nothing happened at all.
      expect(auth.logoutCount, 0);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('confirming clears the session and returns to welcome', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      final InMemorySessionStore store = InMemorySessionStore();
      await pump(tester, auth: auth, store: store, signedIn: true);
      await openProfile(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Eat well on the road'), findsOneWidget);
      expect(await store.read(), isNull);
      expect(auth.logoutCount, 1);
    });

    testWidgets('signing out still works when the server cannot be reached', (
      WidgetTester tester,
    ) async {
      final _FailingLogoutRepository auth = _FailingLogoutRepository();
      final InMemorySessionStore store = InMemorySessionStore();

      usePhoneSurface(tester);
      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(_dashboard),
          auth: auth,
          sessionStore: store,
          signedIn: true,
        ),
      );
      await tester.pumpAndSettle();
      await openProfile(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      // The moment somebody hands their phone over is the moment a sign-out
      // button must not depend on the network.
      expect(find.text('Eat well on the road'), findsOneWidget);
      expect(await store.read(), isNull);
    });

    testWidgets(
      'the welcome screen after a deliberate sign-out is not alarming',
      (WidgetTester tester) async {
        await pump(
          tester,
          auth: FakeAuthRepository(),
          store: InMemorySessionStore(),
          signedIn: true,
        );
        await openProfile(tester);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
        await tester.pumpAndSettle();

        // "You were signed out" is for an unexpected sign-out. Showing it after
        // somebody pressed the button reads like a fault.
        expect(
          find.text('You were signed out. Please sign in again.'),
          findsNothing,
        );
      },
    );
  });
}

/// Logout that always fails, for the network-down case.
class _FailingLogoutRepository extends FakeAuthRepository {
  @override
  Future<void> logout() async => throw const ApiException.network();
}
