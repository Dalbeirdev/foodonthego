import '../../core/network/api_client.dart';
import '../../domain/models/trip.dart';
import '../../domain/repositories/trip_repository.dart';

/// The real implementation, against `/api/v1/customer/trips`.
///
/// Thin on purpose, like its Module 04 sibling. Ownership, the lifecycle rules
/// and the limit all live on the server, where a modified client cannot skip
/// them — and none of these paths carries a customer id, so there is nothing
/// here for a caller to point at somebody else.
class ApiTripRepository implements TripRepository {
  const ApiTripRepository(this._client);

  final ApiClient _client;

  static const String _path = '/customer/trips';

  @override
  Future<List<Trip>> trips({TripScope scope = TripScope.upcoming}) async {
    final List<dynamic> data = await _client.getList(
      '$_path?scope=${scope.wire}',
      authenticated: true,
    );

    return data
        .whereType<Map<String, dynamic>>()
        .map(Trip.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Trip?> nextTrip() async {
    final Map<String, dynamic>? data = await _client.getOrNull(
      '$_path/next',
      authenticated: true,
    );

    return data == null ? null : Trip.fromJson(data);
  }

  @override
  Future<Trip> trip(String id) async {
    return Trip.fromJson(await _client.get('$_path/$id', authenticated: true));
  }

  @override
  Future<Trip> planTrip(TripDraft draft) async {
    return Trip.fromJson(
      await _client.post(_path, body: draft.toJson(), authenticated: true),
    );
  }

  @override
  Future<Trip> updateTrip(String id, TripDraft draft) async {
    return Trip.fromJson(
      await _client.patch(
        '$_path/$id',
        body: draft.toJson(),
        authenticated: true,
      ),
    );
  }

  @override
  Future<Trip> cancelTrip(String id, {String? reason}) async {
    final String? trimmed = reason?.trim();

    return Trip.fromJson(
      await _client.post(
        '$_path/$id/cancel',
        body: <String, dynamic>{
          if (trimmed != null && trimmed.isNotEmpty) 'reason': trimmed,
        },
        authenticated: true,
      ),
    );
  }
}
