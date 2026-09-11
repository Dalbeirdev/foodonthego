import '../../core/network/api_client.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/models/discovery_query.dart';
import '../../domain/repositories/discovery_repository.dart';

/// The real implementation, against `/api/v1/customer/trips/{id}/restaurants`.
///
/// Thin, like its siblings. Eligibility, the corridor, the detour budget, the
/// ranking and the cache all live on the server, where a modified client cannot
/// skip them — and where the routing key they depend on stays.
///
/// Filtering is no different. The parameters are built here and interpreted
/// there; nothing in this file decides which restaurants a customer may see,
/// which is why no filter a client can send is able to reach one Module 07
/// removed.
class ApiDiscoveryRepository implements DiscoveryRepository {
  const ApiDiscoveryRepository(this._client);

  final ApiClient _client;

  @override
  Future<RestaurantDiscovery> discover(
    String tripId, {
    DiscoveryQuery query = DiscoveryQuery.unfiltered,
  }) async => RestaurantDiscovery.fromJson(
    await _client.get(_path(tripId, query), authenticated: true),
  );

  static String _path(String tripId, DiscoveryQuery query) {
    final String base =
        '/customer/trips/${Uri.encodeComponent(tripId)}/restaurants';

    final Map<String, String> params = query.toQueryParameters();

    if (params.isEmpty) return base;

    // Encoded rather than concatenated: a restaurant name with an ampersand in
    // it is a search term, not a second parameter.
    return '$base?${Uri(queryParameters: params).query}';
  }
}
