import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/repositories/customer_repository.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'providers.dart';

/// The customer's saved addresses.
///
/// `AsyncNotifier` gives loading, data and error for free, so the screen has
/// three branches and no manual flags. Mutations are deliberately **not**
/// optimistic: the server owns the one-default rule and the address limit, so a
/// list updated before it answers can show a default that was rejected or an
/// address that was never saved. Every write re-reads the server's result.
///
/// The list is invalidated when the session changes. That is the whole of the
/// cache-isolation story: signing out drops the state, so the next customer
/// cannot see a frame of the previous one's addresses.
class AddressesController extends AsyncNotifier<List<SavedAddress>> {
  @override
  Future<List<SavedAddress>> build() async {
    final AuthState auth = ref.watch(authControllerProvider);

    // Watched, not read. When the session ends this rebuilds and returns an
    // empty list; when a different customer signs in it rebuilds and fetches
    // theirs. Neither path can leave the previous customer's addresses on
    // screen, because there is no state to leave.
    if (!auth.isAuthenticated) return const <SavedAddress>[];

    return ref.read(customerRepositoryProvider).addresses();
  }

  CustomerRepository get _repository => ref.read(customerRepositoryProvider);

  /// Re-fetches. Used by pull-to-refresh and after an error.
  Future<void> reload() async {
    state = const AsyncValue<List<SavedAddress>>.loading();
    state = await AsyncValue.guard(() => _repository.addresses());
  }

  /// Saves a new address and returns it.
  ///
  /// Throws on failure rather than folding the error into [state]: the form that
  /// called this needs to keep its own contents and show the message against the
  /// right field, which it cannot do if the error has become the whole screen's.
  Future<SavedAddress> add(AddressDraft draft) async {
    final SavedAddress created = await _repository.createAddress(draft);

    // Re-read rather than appending. Creating an address can change another one
    // — the first address becomes the default, and a new default clears the old
    // — so the server's list is the only trustworthy answer.
    await _refreshQuietly();

    return created;
  }

  Future<SavedAddress> edit(String id, AddressDraft draft) async {
    final SavedAddress updated = await _repository.updateAddress(id, draft);
    await _refreshQuietly();

    return updated;
  }

  Future<void> remove(String id) async {
    await _repository.deleteAddress(id);

    // Deleting the default promotes another one, server-side. Appending or
    // filtering locally would show no default until the next full load.
    await _refreshQuietly();
  }

  Future<void> makeDefault(String id) async {
    await _repository.makeDefault(id);
    await _refreshQuietly();
  }

  /// Re-reads without flipping the screen back to a skeleton.
  ///
  /// A list that blanks out after every successful edit reads as a failure. The
  /// row-level control shows its own progress instead.
  Future<void> _refreshQuietly() async {
    try {
      state = AsyncValue<List<SavedAddress>>.data(
        await _repository.addresses(),
      );
    } on ApiException {
      // The write succeeded; only the re-read failed. Leaving the previous list
      // in place is better than replacing a correct screen with an error about
      // something that already worked — the next reload corrects it.
    }
  }
}

final addressesControllerProvider =
    AsyncNotifierProvider<AddressesController, List<SavedAddress>>(
      AddressesController.new,
      // Riverpod 3 retries a failed provider on its own. Wrong here for the same
      // reason as on the home screen: a customer in a signal dead zone would
      // have the app quietly re-requesting while the "Try again" button in front
      // of them does nothing.
      retry: (int retryCount, Object error) => null,
    );

/// The customer's default address, or null.
///
/// Derived rather than stored, so it cannot drift from the list.
final defaultAddressProvider = Provider<SavedAddress?>((Ref ref) {
  final List<SavedAddress>? addresses = ref
      .watch(addressesControllerProvider)
      .value;

  if (addresses == null) return null;

  for (final SavedAddress address in addresses) {
    if (address.isDefault) return address;
  }
  return null;
});
