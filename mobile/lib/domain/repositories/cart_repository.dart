import '../models/cart.dart';
import '../models/cart_revalidation.dart';

/// A customer's cart: reading it, correcting it, and emptying it.
///
/// Separate from [MenuRepository], and the split follows the server's own. A
/// cart line is *added* from a menu, under a restaurant, carrying a menu
/// selection — so adding stays on the menu repository. Everything here is
/// addressed by the journey alone, because a cart already knows which kitchen
/// it belongs to and naming a second one would be a chance for the two to
/// disagree.
///
/// **No method here takes a price.** Not a subtotal, not a total, not a
/// discount, not a line total. A quantity is a count, and the server decides
/// what that count costs — there is no parameter for a modified client to lie
/// in.
abstract interface class CartRepository {
  /// What is in the cart. Never an error for an empty one: a customer who has
  /// added nothing has a cart with nothing in it.
  Future<CartView> cart({required String tripId});

  /// The cart, plus whether it still means what it said.
  ///
  /// One request for both, because the cart screen needs both the moment it
  /// opens and asking twice would show the customer a total from one instant
  /// and a verdict from another.
  ///
  /// Reads only. Nothing is corrected, in either direction: a price that has
  /// risen is reported for the customer to accept, and one that has fallen is
  /// reported too rather than quietly applied.
  Future<RevalidatedCart> revalidate({required String tripId});

  /// Changes how many of one line the customer wants.
  ///
  /// [quantity] is at least one. Zero is not "remove" — a caller that means
  /// remove calls [removeLine], and the server refuses a zero rather than
  /// guessing, so an off-by-one in a stepper cannot destroy a selection.
  ///
  /// The line is re-priced from live menu data. A dish that has gone up is
  /// refused with `PRICE_UPDATED` and both figures rather than quietly costing
  /// more.
  Future<CartView> setQuantity({
    required String tripId,
    required String lineId,
    required int quantity,
    String? idempotencyKey,
  });

  /// Takes one line out. Closes the cart if it was the last.
  Future<CartView> removeLine({
    required String tripId,
    required String lineId,
    String? idempotencyKey,
  });

  /// Empties the cart, at the customer's explicit request.
  ///
  /// Never called to make some other request succeed. Destroying a customer's
  /// selections is their decision, taken on a screen that says what will
  /// happen.
  Future<CartView> empty({required String tripId, String? idempotencyKey});
}
