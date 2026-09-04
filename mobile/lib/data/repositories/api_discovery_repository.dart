import '../../core/network/api_client.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/repositories/discovery_repository.dart';

/// The real implementation, against `/api/v1/customer/trips/{id}/restaurants`.
///
/// Thin, like its siblings. Eligibility, the corridor, the detour budget, the
/// ranking and the cache all live on the server, where a modified client cannot
/// skip them — and where the routing key they depend on stays.
class ApiDiscoveryRepository implements DiscoveryRepository {
  const ApiDiscoveryRepository(this._client);

  final ApiClient _client;

  @override
  Future<RestaurantDiscovery> discover(String tripId) async =>
      RestaurantDiscovery.fromJson(
        await _client.get(
          '/customer/trips/${Uri.encodeComponent(tripId)}/restaurants',
          authenticated: true,
        ),
      );
}
