import '../models/discovered_restaurant.dart';
import '../models/discovery_query.dart';

/// Restaurants along a trip's selected route.
///
/// One method, because there is one question. Module 08 gave it a second
/// argument — what the customer has narrowed it to — and nothing else changed:
/// the route is still whichever one the customer selected on their own trip,
/// and there is still nothing here for a caller to substitute.
///
/// The query narrows a result the server has already decided the customer may
/// see. It is not a way to ask for something else.
abstract interface class DiscoveryRepository {
  Future<RestaurantDiscovery> discover(
    String tripId, {
    DiscoveryQuery query = DiscoveryQuery.unfiltered,
  });
}
