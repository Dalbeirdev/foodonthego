import '../models/cart.dart';
import '../models/restaurant_menu.dart';

/// A restaurant's menu, on one customer's route.
///
/// The **menu** is read-only, and there is no write method to leave out later:
/// a customer cannot create, edit, reprice, restock or photograph a menu item,
/// and the absence of those methods here is the client half of a rule the
/// server enforces on its own.
///
/// {@template cart_write}
/// Adding to a cart is the one write in this interface, and it writes to the
/// *customer's* cart, never to the restaurant's menu. It carries selections
/// and no money: there is no price parameter, so there is nothing for a
/// modified client to lie about.
/// {@endtemplate}
abstract interface class MenuRepository {
  /// The whole menu, optionally narrowed by a search.
  ///
  /// The search is sent to the server rather than applied here. A menu is not
  /// paginated, so filtering on the device would work — but the server already
  /// knows which categories are being served at this hour, and a client-side
  /// filter would search a list the customer was never entitled to see.
  Future<RestaurantMenu> menu({
    required String tripId,
    required String restaurantId,
    String? search,
  });

  /// One item, fetched fresh, with everything needed to configure it.
  Future<MenuItemPreview> item({
    required String tripId,
    required String restaurantId,
    required String itemId,
  });

  /// Adds one configured dish to the customer's cart.
  ///
  /// {@macro cart_write}
  ///
  /// [quotedUnitPriceMinor] is what the screen showed the customer — an
  /// assertion, not an instruction. The server charges its own figure and
  /// refuses if that is higher than this one, so the customer never pays more
  /// than they saw.
  ///
  /// [idempotencyKey] makes a retry after a lost response safe: the same key
  /// with the same body returns the first answer rather than adding twice.
  Future<CartAddition> addToCart({
    required String tripId,
    required String restaurantId,
    required String itemId,
    required int quantity,
    String? variantId,
    List<String> optionIds = const <String>[],
    String? specialInstructions,
    int? quotedUnitPriceMinor,
    String? idempotencyKey,
  });

  /// What the customer has so far, for the badge.
  Future<CartSummary> cart({required String tripId});
}
