import '../../core/network/api_client.dart';
import '../../domain/models/checkout.dart';
import '../../domain/repositories/checkout_repository.dart';

/// The real implementation, against `/api/v1/customer/trips/{trip}/checkout`.
///
/// Both calls send **no body at all**. There is no field for a price, and
/// nothing on the server would read one if there were.
class ApiCheckoutRepository implements CheckoutRepository {
  const ApiCheckoutRepository(this._client);

  final ApiClient _client;

  @override
  Future<Checkout> prepare({required String tripId}) async => _parse(
    await _client.post('${_base(tripId)}/prepare', authenticated: true),
  );

  @override
  Future<Checkout> validate({
    required String tripId,
    required String checkoutId,
  }) async => _parse(
    await _client.post(
      '${_base(tripId)}/${Uri.encodeComponent(checkoutId)}/validate',
      authenticated: true,
    ),
  );

  /// A response this build cannot make sense of is not a checkout.
  ///
  /// Throwing rather than returning a half-built object with a zero total: a
  /// screen that rendered one would show a customer a price nobody quoted.
  Checkout _parse(Map<String, dynamic> data) {
    final Checkout? checkout = Checkout.fromJson(data);

    if (checkout == null) {
      throw const FormatException(
        'The checkout response was not the documented shape.',
      );
    }

    return checkout;
  }

  String _base(String tripId) =>
      '/customer/trips/${Uri.encodeComponent(tripId)}/checkout';
}
