import '../../core/network/api_client.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/repositories/customer_repository.dart';

/// The real implementation, against `/api/v1/customer`.
///
/// A thin translation layer on purpose. Every rule that matters — ownership, the
/// one-default invariant, what a customer may change about themselves — lives on
/// the server, where a modified client cannot skip it.
class ApiCustomerRepository implements CustomerRepository {
  const ApiCustomerRepository(this._client);

  final ApiClient _client;

  static const String _profilePath = '/customer/profile';
  static const String _addressesPath = '/customer/addresses';

  @override
  Future<Customer> profile() async {
    return Customer.fromJson(
      await _client.get(_profilePath, authenticated: true),
    );
  }

  @override
  Future<Customer> updateProfile({
    required String firstName,
    String? lastName,
    String? email,
    bool clearLastName = false,
    bool clearEmail = false,
  }) async {
    // A PATCH, so a key that is absent means "leave it" and an explicit null
    // means "clear it". The two flags are how a caller says which it meant,
    // because Dart cannot tell an omitted named argument from one passed null.
    final Map<String, dynamic> body = <String, dynamic>{
      'first_name': firstName.trim(),
      if (clearLastName || lastName != null)
        'last_name': _blankToNull(lastName),
      if (clearEmail || email != null) 'email': _blankToNull(email),
    };

    final Map<String, dynamic> data = await _client.patch(
      _profilePath,
      body: body,
      authenticated: true,
    );

    return Customer.fromJson(data);
  }

  @override
  Future<List<SavedAddress>> addresses() async {
    final List<dynamic> data = await _client.getList(
      _addressesPath,
      authenticated: true,
    );

    return data
        .whereType<Map<String, dynamic>>()
        .map(SavedAddress.fromJson)
        .toList(growable: false);
  }

  @override
  Future<SavedAddress> createAddress(AddressDraft draft) async {
    return SavedAddress.fromJson(
      await _client.post(
        _addressesPath,
        body: draft.toJson(),
        authenticated: true,
      ),
    );
  }

  @override
  Future<SavedAddress> updateAddress(String id, AddressDraft draft) async {
    return SavedAddress.fromJson(
      await _client.patch(
        '$_addressesPath/$id',
        body: draft.toJson(),
        authenticated: true,
      ),
    );
  }

  @override
  Future<void> deleteAddress(String id) async {
    await _client.delete('$_addressesPath/$id', authenticated: true);
  }

  @override
  Future<SavedAddress> makeDefault(String id) async {
    return SavedAddress.fromJson(
      await _client.post('$_addressesPath/$id/default', authenticated: true),
    );
  }

  static String? _blankToNull(String? value) {
    final String trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
