import '../models/customer.dart';
import '../models/saved_address.dart';

/// Everything the app can do with a customer's own profile and saved places.
///
/// One interface for both because they are one screen's worth of concerns from
/// the customer's point of view — "my account" — and because splitting them
/// would mean two seams to override in every test that touches either.
abstract interface class CustomerRepository {
  /// The signed-in customer, fresh from the server.
  Future<Customer> profile();

  /// Updates the fields a customer owns.
  ///
  /// There is no phone parameter, and that is the point: the verified number is
  /// identity, so there is nowhere in the client for a change to it to travel.
  /// Passing null for [lastName] or [email] clears them; omitting them leaves
  /// them alone.
  Future<Customer> updateProfile({
    required String firstName,
    String? lastName,
    String? email,
    bool clearLastName = false,
    bool clearEmail = false,
  });

  Future<List<SavedAddress>> addresses();

  Future<SavedAddress> createAddress(AddressDraft draft);

  Future<SavedAddress> updateAddress(String id, AddressDraft draft);

  Future<void> deleteAddress(String id);

  Future<SavedAddress> makeDefault(String id);
}
