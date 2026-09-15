import '../../core/network/api_client.dart';
import '../../domain/models/pickup.dart';
import '../../domain/models/pre_checkout.dart';
import '../../domain/repositories/pickup_repository.dart';

/// The real implementation, against `/api/v1/customer/trips/{trip}/cart`.
///
/// Thin, like its siblings. Which windows exist, which one is recommended,
/// whether a chosen one still stands and whether the cart is ready for a
/// checkout all live on the server, where a modified client cannot skip them.
///
/// **Nothing here sends a time.** `selectOption` sends one opaque id and the
/// other two send no body at all.
class ApiPickupRepository implements PickupRepository {
  const ApiPickupRepository(this._client);

  final ApiClient _client;

  @override
  Future<PickupView> options({required String tripId}) async =>
      PickupView.fromJson(
        await _client.post(
          '${_base(tripId)}/pickup-options',
          authenticated: true,
        ),
      );

  @override
  Future<PickupView> selectOption({
    required String tripId,
    required String optionId,
    String? idempotencyKey,
  }) async => PickupView.fromJson(
    await _client.put(
      '${_base(tripId)}/pickup-selection',
      body: <String, dynamic>{'pickup_option_id': optionId},
      authenticated: true,
      headers: <String, String>{'Idempotency-Key': ?idempotencyKey},
    ),
  );

  @override
  Future<PreCheckoutResult> preCheckout({required String tripId}) async =>
      PreCheckoutResult.fromJson(
        await _client.post(
          '${_base(tripId)}/pre-checkout-validate',
          authenticated: true,
        ),
      );

  String _base(String tripId) =>
      '/customer/trips/${Uri.encodeComponent(tripId)}/cart';
}
