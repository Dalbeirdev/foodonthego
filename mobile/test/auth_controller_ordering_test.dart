import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/shared/state/auth_controller.dart';
import 'package:foodonthego/shared/state/auth_state.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Whether a signed-out customer can be signed back in by an answer in flight.
///
/// `restore()` reads the stored session, shows the stored profile immediately,
/// and then asks the server to correct it. The optimistic step is deliberate
/// and right — a customer should not stare at a splash screen because the
/// network is slow — but it means **the app is signed in and usable for the
/// whole of that request**. The router has let them through; the profile
/// screen, and its Sign out button, are in front of them.
///
/// If they use it, `restore()` must not put the session back when its answer
/// arrives. Of everything the ordering audit turned up, this is the one where
/// being wrong is not a display fault: a customer who signed out would be
/// signed in again, on a device they may have handed to somebody else.
void main() {
  late FakeAuthRepository auth;
  late InMemorySessionStore store;
  late ProviderContainer container;

  setUp(() async {
    auth = FakeAuthRepository();
    store = InMemorySessionStore();

    await store.write(
      AuthSession(
        accessToken: 'stored-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        customer: FakeAuthRepository.sampleCustomer,
      ),
    );

    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sessionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  AuthState read() => container.read(authControllerProvider);
  AuthController notifier() => container.read(authControllerProvider.notifier);

  /// Lets pending microtasks run.
  ///
  /// The restore under test is the one `build()` starts for itself, so there is
  /// nothing to await: it is scheduled, not returned.
  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('signing out during a restore is not undone by it', () async {
    // Armed before the provider is touched, because touching it starts the
    // restore. An earlier draft called `restore()` itself as well, which made
    // TWO restores race each other rather than a restore race a sign-out; it
    // failed before the fix and passed after it, for reasons that had nothing
    // to do with either. The control below is what caught that.
    final Completer<void> slowAnswer = Completer<void>();
    auth.holdCurrentCustomer = slowAnswer;

    // Reading the provider builds the controller, which starts the restore.
    expect(read(), isA<AuthRestoring>());

    await settle();

    // The optimistic step has run: the app is signed in and the customer can
    // reach the Sign out button, while the confirming request is still in
    // flight. This is the ordinary cold start, not a contrived state.
    expect(read(), isA<AuthAuthenticated>());
    expect(auth.currentCustomerCount, 1);

    await notifier().logout();

    expect(read(), isA<AuthSignedOut>());

    // The correction the restore was waiting for finally arrives.
    slowAnswer.complete();
    await settle();

    expect(
      read(),
      isA<AuthSignedOut>(),
      reason:
          'a restore in flight signed the customer back in after they had '
          'signed out',
    );
    expect(
      await store.read(),
      isNull,
      reason: 'the restore rewrote the session the sign-out had cleared',
    );
  });

  // ------------------------------------------------------------- the control
  //
  // The test above would pass on a controller that never applied a restore at
  // all, which would sign everybody out on every cold start. The correction
  // must still land when nothing has overtaken it.

  test(
    'a restore with nothing racing it still applies the correction',
    () async {
      // The server knows this customer by a name the stored session predates.
      auth.customer = const Customer(
        id: 'c0ffee00-0000-4000-8000-000000000001',
        firstName: 'Ravi',
        lastName: 'Verma',
        phone: '+919876543210',
        phoneVerified: true,
      );

      expect(read(), isA<AuthRestoring>());

      await settle();

      final AuthState finished = read();

      expect(finished, isA<AuthAuthenticated>());
      expect(
        (finished as AuthAuthenticated).customer.lastName,
        'Verma',
        reason: 'the correction was discarded, which is the opposite failure',
      );
      expect(
        (await store.read())?.customer.lastName,
        'Verma',
        reason: 'the corrected profile never reached storage',
      );
    },
  );
}
