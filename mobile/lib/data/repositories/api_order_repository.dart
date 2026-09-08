import '../../core/network/api_client.dart';
import '../../domain/models/placed_order.dart';
import '../../domain/repositories/order_repository.dart';

/// The real implementation, against `/api/v1/customer`.
///
/// `place` and `createIntent` send **no body at all**. `verifyPayment` sends
/// exactly three provider identifiers and nothing else — there is no amount in
/// any request this class makes.
class ApiOrderRepository implements OrderRepository {
  const ApiOrderRepository(this._client);

  final ApiClient _client;

  @override
  Future<PlacedOrder> place({
    required String tripId,
    required String checkoutId,
  }) async => _order(
    await _client.post(
      '/customer/trips/${Uri.encodeComponent(tripId)}'
      '/checkout/${Uri.encodeComponent(checkoutId)}/order',
      authenticated: true,
    ),
  );

  @override
  Future<PaymentIntent> createIntent({required String orderId}) async {
    final Map<String, dynamic> data = await _client.post(
      '/customer/orders/${Uri.encodeComponent(orderId)}/payment-intent',
      authenticated: true,
    );

    final PaymentIntent? intent = PaymentIntent.fromJson(data);

    if (intent == null) {
      throw const FormatException(
        'The payment intent response was not the documented shape.',
      );
    }

    return intent;
  }

  @override
  Future<PlacedOrder> verifyPayment({
    required String orderId,
    required String providerOrderId,
    required String providerPaymentId,
    required String signature,
  }) async => _order(
    await _client.post(
      '/customer/orders/${Uri.encodeComponent(orderId)}/payment/verify',
      authenticated: true,
      body: <String, dynamic>{
        'provider_order_id': providerOrderId,
        'provider_payment_id': providerPaymentId,
        'signature': signature,
      },
    ),
  );

  @override
  Future<PlacedOrder> byId(String orderId) async => _order(
    await _client.get(
      '/customer/orders/${Uri.encodeComponent(orderId)}',
      authenticated: true,
    ),
  );

  @override
  Future<List<PlacedOrder>> mine() async {
    final Map<String, dynamic> data = await _client.get(
      '/customer/orders',
      authenticated: true,
    );

    return <PlacedOrder>[
      for (final Object? entry
          in (data['orders'] as List<Object?>? ?? const <Object?>[]))
        if (PlacedOrder.fromJson(entry) case final PlacedOrder order) order,
    ];
  }

  /// A response this build cannot make sense of is not an order.
  ///
  /// Throwing rather than returning a half-built object: a screen rendering one
  /// would show a customer an order number and a total that nobody wrote.
  PlacedOrder _order(Map<String, dynamic> data) {
    final PlacedOrder? order = PlacedOrder.fromJson(data);

    if (order == null) {
      throw const FormatException(
        'The order response was not the documented shape.',
      );
    }

    return order;
  }
}
