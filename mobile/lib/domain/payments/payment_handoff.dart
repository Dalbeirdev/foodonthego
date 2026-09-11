import '../models/placed_order.dart';

/// What became of handing a customer to the provider's checkout.
sealed class PaymentHandoffResult {
  const PaymentHandoffResult();
}

/// The customer paid, and the provider signed a result saying so.
///
/// **This is a claim, not a fact.** Every field here reached the app through a
/// device this project does not control, and all three go straight to the server
/// to be checked against the provider. Nothing in the app treats this as proof
/// of payment, and no screen may show an order as paid on the strength of it.
class PaymentHandoffSucceeded extends PaymentHandoffResult {
  const PaymentHandoffSucceeded({
    required this.providerOrderId,
    required this.providerPaymentId,
    required this.signature,
  });

  final String providerOrderId;
  final String providerPaymentId;
  final String signature;
}

/// The customer backed out. Not an error, and not something to apologise for.
class PaymentHandoffCancelled extends PaymentHandoffResult {
  const PaymentHandoffCancelled();
}

/// The provider refused, or its sheet failed.
class PaymentHandoffFailed extends PaymentHandoffResult {
  const PaymentHandoffFailed(this.message);

  final String message;
}

/// No provider checkout can be opened on this build.
///
/// Distinct from [PaymentHandoffFailed] on purpose: nothing went wrong, the
/// capability is absent. A screen must say so plainly rather than showing a
/// customer a failed payment they never attempted.
class PaymentHandoffUnavailable extends PaymentHandoffResult {
  const PaymentHandoffUnavailable(this.reason);

  final String reason;
}

/// The boundary between this app and whoever collects the money.
///
/// One method, because the app asks the provider exactly one thing: take this
/// payment and tell me what happened.
abstract interface class PaymentHandoff {
  Future<PaymentHandoffResult> open(PaymentIntent intent);
}

/// The default, and what this build actually uses.
///
/// **No Razorpay SDK is integrated and no credentials exist.** The honest
/// implementation of "open a checkout" under those conditions is one that says
/// it cannot, which is what this does.
///
/// The alternative was to add the provider's Flutter package and wire it up
/// against credentials nobody has. That would compile, would look finished in a
/// screenshot, and could never be run — and a payment path that has never once
/// executed is worse than an absent one, because absence is visible.
///
/// It mirrors `UnconfiguredPaymentGateway` on the server for the same reason:
/// a missing integration must be a visibly missing one.
class UnconfiguredPaymentHandoff implements PaymentHandoff {
  const UnconfiguredPaymentHandoff();

  @override
  Future<PaymentHandoffResult> open(PaymentIntent intent) async =>
      const PaymentHandoffUnavailable(
        'Card payment is not enabled on this build.',
      );
}
