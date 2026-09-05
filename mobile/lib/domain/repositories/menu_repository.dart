import '../models/restaurant_menu.dart';

/// A restaurant's menu, on one customer's route.
///
/// Read-only, and there is no write method to leave out later: a customer
/// cannot create, edit, reprice, restock or photograph a menu item, and the
/// absence of those methods here is the client half of a rule the server
/// enforces on its own.
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

  /// One item, fetched fresh.
  Future<MenuItemPreview> item({
    required String tripId,
    required String restaurantId,
    required String itemId,
  });
}
