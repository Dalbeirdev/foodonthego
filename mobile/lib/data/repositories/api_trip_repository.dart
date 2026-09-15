import '../../core/network/api_client.dart';
import '../../domain/models/trip.dart';
import '../../domain/repositories/trip_repository.dart';

/// The real implementation, against `/api/v1/customer/trips`.
///
/// Thin on purpose, like its Module 04 sibling. Ownership, coordinate
/// validation, the same-place rule and the open-trip limit all live on the
/// server, where a modified client cannot skip them — and none of these paths
/// carries a customer id, so there is nothing here for a caller to point at
/// somebody else.
class ApiTripRepository implements TripRepository {
  const ApiTripRepository(this._client);

  final ApiClient _client;

  static const String _path = '/customer/trips';

  @override
  Future<List<Trip>> trips({TripScope scope = TripScope.open}) async {
    final String? status = scope.status;

    final List<dynamic> data = await _client.getList(
      status == null ? _path : '$_path?status=$status',
      authenticated: true,
    );

    return data
        .whereType<Map<String, dynamic>>()
        .map(Trip.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Trip?> currentTrip() async {
    final Map<String, dynamic>? data = await _client.getOrNull(
      '$_path/current',
      authenticated: true,
    );

    return data == null ? null : Trip.fromJson(data);
  }

  @override
  Future<Trip> trip(String id) async =>
      Trip.fromJson(await _client.get('$_path/$id', authenticated: true));

  @override
  Future<Trip> createTrip(TripDraft draft) async => Trip.fromJson(
    await _client.post(_path, body: draft.toJson(), authenticated: true),
  );

  @override
  Future<Trip> discardTrip(String id) async => Trip.fromJson(
    await _client.post('$_path/$id/discard', authenticated: true),
  );
}
