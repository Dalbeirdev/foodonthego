import '../models/checkout.dart';

/// Preparing a checkout, and asking whether it could still be paid for.
///
/// **No method here takes an amount.** Not a subtotal, not a tax figure, not a
/// discount, not a total. A modified client cannot name a price because the
/// interface has no parameter for one — and neither does the request the
/// implementation builds.
///
/// Nothing here creates an order or a payment. Module 15 owns that boundary.
abstract interface class CheckoutRepository {
  /// Prepares this cart's checkout, or refreshes it.
  ///
  /// Returns the whole purchase as the server sees it: restaurant, journey,
  /// pickup, items and an authoritative payable amount. Calling it again
  /// supersedes the previous quote rather than adding to a pile.
  Future<Checkout> prepare({required String tripId});

  /// Whether this exact quote could still be paid for.
  ///
  /// `readyForPayment` comes from the server. A screen renders it and must
  /// never reconstruct it from the issues it can see.
  Future<Checkout> validate({
    required String tripId,
    required String checkoutId,
  });
}
