import '../../core/network/api_client.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/trip_route.dart';
import '../../domain/repositories/route_repository.dart';

/// The real implementation, against `/api/v1/customer/trips/{id}/…`.
///
/// Thin, like its siblings. Ownership, provider choice, validation, the
/// one-selected invariant and the freshness window all live on the server, where
/// a modified client cannot skip them — and no path here carries a customer id.
class ApiRouteRepository implements RouteRepository {
  const ApiRouteRepository(this._client);

  final ApiClient _client;

  @override
  Future<TripRoutes> routes(String tripId) async => _read(
    await _client.get(
      '/customer/trips/${Uri.encodeComponent(tripId)}/routes',
      authenticated: true,
    ),
  );

  @override
  Future<TripRoutes> calculate(String tripId, {bool refresh = false}) async {
    final String path =
        '/customer/trips/${Uri.encodeComponent(tripId)}/route/calculate'
        '${refresh ? '?refresh=1' : ''}';

    // No body. There is nothing about a route a client is entitled to propose.
    return _read(await _client.post(path, authenticated: true));
  }

  @override
  Future<TripRoutes> select(String tripId, String routeId) async => _read(
    await _client.post(
      '/customer/trips/${Uri.encodeComponent(tripId)}'
      '/routes/${Uri.encodeComponent(routeId)}/select',
      authenticated: true,
    ),
  );

  TripRoutes _read(Map<String, dynamic> data) {
    final List<dynamic> raw = (data['routes'] as List<dynamic>?) ?? <dynamic>[];

    return TripRoutes(
      trip: Trip.fromJson(
        (data['trip'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      // A route that cannot be read is dropped rather than half-built: the map
      // is about to draw these, and a null distance becomes "0 km" on a screen.
      routes: raw
          .whereType<Map<String, dynamic>>()
          .map(TripRoute.fromJson)
          .whereType<TripRoute>()
          .toList(growable: false),
    );
  }
}
