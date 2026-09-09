import '../models/order_status_report.dart';
import '../models/pickup_credential.dart';
import '../models/placed_order.dart';

/// Placing an order and paying for it.
///
/// **No method here takes an amount.** Not one that is validated — one that
/// exists. The price is the server's, read from the quote it wrote, and there
/// is no parameter through which a client figure could travel.
abstract interface class OrderRepository {
  /// Turn an accepted checkout quote into an order.
  ///
  /// Idempotent on the server: a retry or a double tap returns the order that
  /// already exists rather than a second one.
  Future<PlacedOrder> place({
    required String tripId,
    required String checkoutId,
  });

  /// Open a payment against an order and get what the provider SDK needs.
  Future<PaymentIntent> createIntent({required String orderId});

  /// Hand the provider's result back for the server to check.
  ///
  /// These three values come from the provider by way of the device. The server
  /// treats them as a claim to verify — signature, then binding, then amount —
  /// never as a report to believe, so a caller cannot settle an order by
  /// inventing them.
  Future<PlacedOrder> verifyPayment({
    required String orderId,
    required String providerOrderId,
    required String providerPaymentId,
    required String signature,
  });

  Future<PlacedOrder> byId(String orderId);

  Future<List<PlacedOrder>> mine();

  /// Where a purchase stands, for an app that has come back and does not know.
  ///
  /// The app-restart path: payment captured, process killed before the
  /// confirmation rendered. Idempotent on the server, so polling it cannot
  /// produce a second order.
  Future<OrderStatusReport> statusOf(String orderId);

  /// The pickup code and QR payload for an order.
  ///
  /// Separate from the order on purpose. See [PickupCredential].
  Future<PickupCredential> pickupCredential(String orderId);
}
