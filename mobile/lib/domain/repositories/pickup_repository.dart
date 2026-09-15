import '../models/pickup.dart';
import '../models/pre_checkout.dart';

/// Choosing when to collect, and asking whether the order could be paid for.
///
/// **No method here takes a time.** Not a timestamp, not a duration, not a
/// window. [selectOption] takes an opaque id the server minted and the server
/// resolves; there is no parameter a modified client could put a pickup time
/// of its own into, because the interface has none.
///
/// Nothing here decides anything either. Whether a window is feasible, whether
/// a selection still stands, and whether a cart is ready for checkout are all
/// answers this repository fetches and never computes.
abstract interface class PickupRepository {
  /// What pickup times this cart could have, with the arithmetic behind them.
  ///
  /// A POST, following the server: it is a calculation over live state whose
  /// answers are short-lived, and the ids it returns expire. Re-fetching is the
  /// only way to get usable ones — they are deliberately not cached.
  Future<PickupView> options({required String tripId});

  /// Agrees to one of them, by id.
  ///
  /// The server re-checks the owner, the cart, the journey, the restaurant, the
  /// facts the plan was made under, and whether the window is still one the
  /// kitchen can honour. A refusal here is normal and expected: the plan that
  /// produced the id was true when it was produced.
  Future<PickupView> selectOption({
    required String tripId,
    required String optionId,
    String? idempotencyKey,
  });

  /// Whether this cart could be paid for, and everything standing in the way.
  ///
  /// `ready_for_checkout` comes from the server. A screen renders it; it must
  /// never work the answer out from the issue list, because a client that
  /// reasoned its own way to "ready" would be one release away from disagreeing
  /// with the server about whether a customer may be charged.
  Future<PreCheckoutResult> preCheckout({required String tripId});
}
