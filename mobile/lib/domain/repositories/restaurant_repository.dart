import '../models/restaurant_detail.dart';

/// One restaurant, on one customer's route.
///
/// Both identifiers are required and neither is optional. A restaurant detail
/// without a trip would be a generic restaurant page — which is precisely the
/// product FoodOnTheGo is not — and the route figures on the screen have no
/// meaning without the journey they were measured against.
abstract interface class RestaurantRepository {
  Future<RestaurantDetail> detail({
    required String tripId,
    required String restaurantId,
  });
}
