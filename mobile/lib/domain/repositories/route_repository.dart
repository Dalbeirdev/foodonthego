import '../models/trip.dart';
import '../models/trip_route.dart';

/// A trip and the routes calculated for it, together.
///
/// One type rather than two responses, because the trip's `route_status` and the
/// routes have to agree: a screen holding a READY status and an empty list, or
/// the other way round, renders something that was never true.
class TripRoutes {
  const TripRoutes({required this.trip, required this.routes});

  final Trip trip;
  final List<TripRoute> routes;

  TripRoute? get selected {
    for (final TripRoute route in routes) {
      if (route.isSelected) return route;
    }
    return null;
  }

  /// The recommended route, which is what the server selects by default.
  TripRoute? get recommended {
    for (final TripRoute route in routes) {
      if (route.isRecommended) return route;
    }
    return routes.isEmpty ? null : routes.first;
  }

  List<TripRoute> get alternatives =>
      routes.where((TripRoute route) => !route.isRecommended).toList();

  bool get hasRoutes => routes.isNotEmpty;

  /// Whether any of these came from a real routing provider.
  ///
  /// False means a development stand-in produced them, and the screen says so
  /// rather than letting a straight line pass for a road.
  bool get isFromRealProvider =>
      routes.isNotEmpty && routes.every((TripRoute r) => r.isFromRealProvider);
}

/// Everything the app can do with a trip's routes.
///
/// Note what is absent. There is no way to *supply* a route: no distance, no
/// duration, no geometry, no selection flag crosses the wire from here. The only
/// thing this app tells the server about a route is which of the ones it
/// calculated the customer picked.
abstract interface class RouteRepository {
  /// The routes already calculated. **Never calculates.**
  ///
  /// Separate from [calculate] on purpose: a read that could spend money is a
  /// read that spends money every time a screen rebuilds.
  Future<TripRoutes> routes(String tripId);

  /// Calculates, or returns what the server already knows.
  ///
  /// [refresh] skips the server's freshness window. For an explicit "work it out
  /// again", never for an ordinary screen open.
  Future<TripRoutes> calculate(String tripId, {bool refresh = false});

  Future<TripRoutes> select(String tripId, String routeId);
}
