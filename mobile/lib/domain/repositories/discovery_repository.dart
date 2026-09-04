import '../models/discovered_restaurant.dart';

/// Restaurants along a trip's selected route.
///
/// One method, because there is one question. Note what is absent: no filters,
/// no sort order, no page cursor and no route id. Filters and sorting belong to
/// Module 08, and the route is whichever one the customer selected on their own
/// trip — there is nothing here for a caller to substitute.
abstract interface class DiscoveryRepository {
  Future<RestaurantDiscovery> discover(String tripId);
}
