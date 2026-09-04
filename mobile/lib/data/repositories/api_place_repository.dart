import '../../core/network/api_client.dart';
import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';

/// The real implementation, against `/api/v1/customer/places`.
///
/// Every call is authenticated. Place search on a server holding a metered
/// provider key is somebody else's free geocoder if it is left open, and the
/// bill arrives here.
class ApiPlaceRepository implements PlaceRepository {
  const ApiPlaceRepository(this._client);

  final ApiClient _client;

  static const String _path = '/customer/places';

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    String? sessionToken,
  }) async {
    final String trimmed = query.trim();

    // Below the server's own minimum. Answering locally spends nothing and
    // saves the customer a validation error they did not ask for by typing one
    // letter.
    if (trimmed.length < 2) return const <PlaceSuggestion>[];

    final StringBuffer path = StringBuffer(
      '$_path/search?q=${Uri.encodeQueryComponent(trimmed)}',
    );
    if (sessionToken != null) {
      path.write('&session_token=${Uri.encodeQueryComponent(sessionToken)}');
    }

    final List<dynamic> data = await _client.getList(
      path.toString(),
      authenticated: true,
    );

    return data
        .whereType<Map<String, dynamic>>()
        .map(PlaceSuggestion.fromJson)
        .where((PlaceSuggestion s) => s.isUsable)
        .toList(growable: false);
  }

  @override
  Future<PlaceDetails> details(String placeId, {String? sessionToken}) async {
    final StringBuffer path = StringBuffer(
      '$_path/${Uri.encodeComponent(placeId)}',
    );
    if (sessionToken != null) {
      path.write('?session_token=${Uri.encodeQueryComponent(sessionToken)}');
    }

    final PlaceDetails? details = PlaceDetails.fromJson(
      await _client.get(path.toString(), authenticated: true),
    );

    if (details == null) {
      // A details response with no position has not resolved anything.
      // Deriving one from the address text is exactly what must not happen: it
      // would be indistinguishable from a real fix everywhere downstream.
      throw const PlaceUnlocatableException();
    }

    return details;
  }

  @override
  Future<PlaceDetails?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final Map<String, dynamic> data = await _client.post(
      '$_path/reverse-geocode',
      body: <String, dynamic>{'latitude': latitude, 'longitude': longitude},
      authenticated: true,
    );

    // `data` is null for a point the provider cannot name, which the client
    // unwraps to an empty map. That is a success, not a failure: the coordinates
    // came from the device and stand on their own.
    return data.isEmpty ? null : PlaceDetails.fromJson(data);
  }
}

/// A place came back without a position.
///
/// Its own type rather than a generic failure, because the screen's answer is
/// specific: ask the customer to pick a different result, not to try again.
class PlaceUnlocatableException implements Exception {
  const PlaceUnlocatableException();

  @override
  String toString() => 'PlaceUnlocatableException';
}
