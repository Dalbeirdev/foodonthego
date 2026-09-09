import '../../core/network/api_client.dart';
import '../../domain/models/order_status_report.dart';
import '../../domain/models/pickup_credential.dart';
import '../../domain/models/placed_order.dart';
import '../../domain/models/tracked_order.dart';
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
  Future<TrackedOrder> tracking(String orderId) async {
    final Map<String, dynamic> data = await _client.get(
      '/customer/orders/${Uri.encodeComponent(orderId)}',
      authenticated: true,
    );

    /*
     * `data`, not `data['data']`.
     *
     * ApiClient.get already returns the envelope's `data` member, which every
     * other method in this class relies on -- `mine()` reads data['orders'],
     * not data['data']['orders']. The first version of this method unwrapped a
     * second time, so TrackedOrder.fromJson was handed null on every real call
     * and every tracking request threw a FormatException.
     *
     * NOTHING IN THE WIDGET SUITE COULD CATCH IT. Those tests use a fake
     * repository, so this parsing had never once run against a real response;
     * it took a device test against a real server to fail. The same shape as
     * Module 16's nullable order number, and the same lesson: a seam that only
     * the fake implements is a seam nothing tests.
     */
    final TrackedOrder? tracked = TrackedOrder.fromJson(data);

    if (tracked == null) {
      throw const FormatException(
        'The tracking response was not the documented shape.',
      );
    }

    return tracked;
  }

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

  @override
  Future<OrderStatusReport> statusOf(String orderId) async {
    final Map<String, dynamic> data = await _client.get(
      '/customer/orders/${Uri.encodeComponent(orderId)}/status',
      authenticated: true,
    );

    final OrderStatusReport? report = OrderStatusReport.fromJson(data);

    if (report == null) {
      throw const FormatException(
        'The order status response was not the documented shape.',
      );
    }

    return report;
  }

  @override
  Future<PickupCredential> pickupCredential(String orderId) async {
    final Map<String, dynamic> data = await _client.get(
      '/customer/orders/${Uri.encodeComponent(orderId)}/pickup-credential',
      authenticated: true,
    );

    final PickupCredential? credential = PickupCredential.fromJson(
      data['pickup'],
    );

    // Throwing rather than returning an empty credential. A screen rendering
    // one would show a customer a blank code, or a QR built from an empty
    // string, and send them to a counter with something that cannot work.
    if (credential == null) {
      throw const FormatException(
        'The pickup credential response was not the documented shape.',
      );
    }

    return credential;
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
