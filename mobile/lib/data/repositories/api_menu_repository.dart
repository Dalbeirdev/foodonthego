import '../../core/network/api_client.dart';
import '../../domain/models/restaurant_menu.dart';
import '../../domain/repositories/menu_repository.dart';

/// The real implementation, against
/// `/api/v1/customer/trips/{trip}/restaurants/{restaurant}/menu`.
///
/// Thin, like its siblings. Which categories are being served at this hour,
/// which items are withdrawn, whether this restaurant is one this customer may
/// see at all, and the allow-list of fields a customer is shown — all of it
/// lives on the server, where a modified client cannot skip it.
class ApiMenuRepository implements MenuRepository {
  const ApiMenuRepository(this._client);

  final ApiClient _client;

  @override
  Future<RestaurantMenu> menu({
    required String tripId,
    required String restaurantId,
    String? search,
  }) async {
    final String term = (search ?? '').trim();

    final String path = term.isEmpty
        ? _base(tripId, restaurantId)
        : '${_base(tripId, restaurantId)}'
              '?${Uri(queryParameters: <String, String>{'search': term}).query}';

    final Map<String, dynamic> body = await _client.get(
      path,
      authenticated: true,
    );

    final RestaurantMenu? menu = RestaurantMenu.fromJson(body);

    if (menu == null) {
      // A 200 whose body cannot be read is a contract change, not a restaurant
      // with half a menu. Building a screen from it would show prices nobody
      // sent.
      throw StateError('menu response could not be read');
    }

    return menu;
  }

  @override
  Future<MenuItemPreview> item({
    required String tripId,
    required String restaurantId,
    required String itemId,
  }) async {
    final Map<String, dynamic> body = await _client.get(
      '${_base(tripId, restaurantId)}/items/${Uri.encodeComponent(itemId)}',
      authenticated: true,
    );

    final MenuItemPreview? preview = MenuItemPreview.fromJson(body);

    if (preview == null) {
      throw StateError('menu item response could not be read');
    }

    return preview;
  }

  String _base(String tripId, String restaurantId) =>
      '/customer/trips/${Uri.encodeComponent(tripId)}'
      '/restaurants/${Uri.encodeComponent(restaurantId)}/menu';
}
