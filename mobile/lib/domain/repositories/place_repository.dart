import '../models/place.dart';

/// Place lookup, through this app's own server.
///
/// The app has no provider key and makes no provider call. That is not an
/// inconvenience worked around — it is the design: a key shipped in an app
/// bundle is a key anybody can extract from the bundle, and a restriction on a
/// mobile key can be forged by anything that can set a package name.
abstract interface class PlaceRepository {
  /// Autocomplete.
  ///
  /// [sessionToken] groups the keystrokes of one search with the details call
  /// that ends it, so the provider bills a session rather than a request per
  /// letter. The caller mints it when a search opens and drops it once a place
  /// has been chosen.
  Future<List<PlaceSuggestion>> search(String query, {String? sessionToken});

  /// Turns a suggestion into something with a position.
  Future<PlaceDetails> details(String placeId, {String? sessionToken});

  /// Names a coordinate the device produced.
  ///
  /// Null is a **success**: the coordinates are authoritative regardless, and a
  /// point with no name is still a perfectly good place to set off from.
  Future<PlaceDetails?> reverseGeocode({
    required double latitude,
    required double longitude,
  });
}
