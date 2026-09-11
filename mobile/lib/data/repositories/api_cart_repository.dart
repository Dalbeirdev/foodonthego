import '../../core/network/api_client.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/cart_revalidation.dart';
import '../../domain/repositories/cart_repository.dart';

/// The real implementation, against `/api/v1/customer/trips/{trip}/cart`.
///
/// Thin, like its siblings. Which lines exist, what they cost, what tax and
/// fees apply, whether a quantity is allowed and whether the kitchen is still
/// taking orders — all of it lives on the server, where a modified client
/// cannot skip it.
///
/// Every method sends selections and counts. **None of them sends a price**,
/// because there is no field to put one in and nothing that would read it.
class ApiCartRepository implements CartRepository {
  const ApiCartRepository(this._client);

  final ApiClient _client;

  @override
  Future<CartView> cart({required String tripId}) async =>
      CartView.fromJson(await _client.get(_base(tripId), authenticated: true));

  @override
  Future<RevalidatedCart> revalidate({required String tripId}) async =>
      RevalidatedCart.fromJson(
        await _client.get('${_base(tripId)}/revalidate', authenticated: true),
      );

  @override
  Future<CartView> setQuantity({
    required String tripId,
    required String lineId,
    required int quantity,
    String? idempotencyKey,
  }) async => CartView.fromJson(
    await _client.patch(
      '${_base(tripId)}/items/${Uri.encodeComponent(lineId)}',
      body: <String, dynamic>{'quantity': quantity},
      authenticated: true,
      headers: <String, String>{'Idempotency-Key': ?idempotencyKey},
    ),
  );

  @override
  Future<CartView> removeLine({
    required String tripId,
    required String lineId,
    String? idempotencyKey,
  }) async => CartView.fromJson(
    await _client.delete(
      '${_base(tripId)}/items/${Uri.encodeComponent(lineId)}',
      authenticated: true,
      headers: <String, String>{'Idempotency-Key': ?idempotencyKey},
    ),
  );

  @override
  Future<CartView> empty({
    required String tripId,
    String? idempotencyKey,
  }) async => CartView.fromJson(
    await _client.delete(
      _base(tripId),
      authenticated: true,
      headers: <String, String>{'Idempotency-Key': ?idempotencyKey},
    ),
  );

  String _base(String tripId) =>
      '/customer/trips/${Uri.encodeComponent(tripId)}/cart';
}
