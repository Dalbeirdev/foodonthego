import '../../core/network/api_client.dart';
import '../../domain/models/restaurant_detail.dart';
import '../../domain/repositories/restaurant_repository.dart';

/// The real implementation, against
/// `/api/v1/customer/trips/{trip}/restaurants/{restaurant}`.
///
/// Thin, like its siblings. Eligibility, the route context, availability and
/// the privacy allow-list all live on the server, where a modified client
/// cannot skip them — which is why passing a restaurant's id here buys nothing
/// a customer was not already entitled to.
class ApiRestaurantRepository implements RestaurantRepository {
  const ApiRestaurantRepository(this._client);

  final ApiClient _client;

  @override
  Future<RestaurantDetail> detail({
    required String tripId,
    required String restaurantId,
  }) async {
    final Map<String, dynamic> body = await _client.get(
      '/customer/trips/${Uri.encodeComponent(tripId)}'
      '/restaurants/${Uri.encodeComponent(restaurantId)}',
      authenticated: true,
    );

    final RestaurantDetail? detail = RestaurantDetail.fromJson(body);

    if (detail == null) {
      // A 200 whose body cannot be read is a contract change, not a restaurant
      // that half exists. Building a partial screen from it would show a
      // customer figures nobody sent.
      throw StateError('restaurant detail response could not be read');
    }

    return detail;
  }
}
