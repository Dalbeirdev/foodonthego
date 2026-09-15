import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/shared/state/addresses_controller.dart';
import 'package:foodonthego/shared/state/auth_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Whether a pull-to-refresh can undo a change made during it.
///
/// The saved-addresses screen guards its own row controls with a busy id, so
/// two edits cannot overlap. Its `RefreshIndicator` is outside that guard: a
/// `reload()` can be in flight while the customer makes an address their
/// default, and if the older read is allowed to land the default flips back
/// over a server that has already moved it.
void main() {
  late FakeCustomerRepository customers;
  late ProviderContainer container;

  setUp(() async {
    customers = FakeCustomerRepository(
      addresses: <SavedAddress>[
        sampleAddress(id: 'addr-1', label: 'Home', isDefault: true),
        sampleAddress(id: 'addr-2', label: 'Office'),
      ],
    );

    final InMemorySessionStore store = InMemorySessionStore();
    await store.write(
      AuthSession(
        accessToken: 'stored-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        customer: FakeAuthRepository.sampleCustomer,
      ),
    );

    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile. The session is
      // real-shaped because this controller's `build()` watches it — signed
      // out, it returns an empty list and none of this is reachable.
      overrides: [
        customerRepositoryProvider.overrideWithValue(customers),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        sessionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> signedInWithAddresses() async {
    container.read(authControllerProvider);
    await settle();
    await container.read(addressesControllerProvider.future);
    await settle();
  }

  String? defaultId() => container
      .read(addressesControllerProvider)
      .value!
      .where((SavedAddress address) => address.isDefault)
      .map((SavedAddress address) => address.id)
      .firstOrNull;

  AddressesController notifier() =>
      container.read(addressesControllerProvider.notifier);

  test('a refresh that answers after a change does not undo it', () async {
    await signedInWithAddresses();

    expect(defaultId(), 'addr-1');

    // Pull to refresh, and the server is slow about it.
    final Completer<void> slowAnswer = Completer<void>();
    customers.holdAddresses = slowAnswer;

    final Future<void> refreshing = notifier().reload();

    // The customer makes the other address their default while it is in flight.
    await notifier().makeDefault('addr-2');

    expect(
      defaultId(),
      'addr-2',
      reason: 'the change did not take even before the race',
    );

    slowAnswer.complete();
    await refreshing;
    await settle();

    expect(
      defaultId(),
      'addr-2',
      reason:
          'a read issued before the change put the old default back over a '
          'server that has already moved it',
    );
  });

  // ------------------------------------------------------------- the control
  //
  // This would pass on a controller that discarded every answer after the
  // first, which is a worse fault wearing the fix's clothes.

  test('a refresh with nothing newer behind it is still applied', () async {
    await signedInWithAddresses();

    // Changed elsewhere — another device, or the server itself.
    await customers.makeDefault('addr-2');

    await notifier().reload();

    expect(
      defaultId(),
      'addr-2',
      reason: 'a later answer was discarded, which is the opposite failure',
    );
  });
}
