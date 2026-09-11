/// Places, as this app's own server hands them over.
///
/// Note what these are *not*: they are not Google's JSON. The app never talks to
/// a place provider — the key stays on the server, every lookup goes through
/// `/customer/places/*`, and the provider can be swapped without an app release.
/// A widget that read `structuredFormat.mainText.text` would be a widget coupled
/// to one vendor.
library;

/// One autocomplete result.
///
/// Carries **no coordinates**, exactly as the server's does. Autocomplete answers
/// "which place did you mean"; [PlaceDetails] answers "where is it". A suggestion
/// that carried a position would invite a screen to build a trip endpoint out of
/// a search term, and the position of a search term is not a place.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      PlaceSuggestion(
        placeId: json['place_id'] as String? ?? '',
        primaryText: json['primary_text'] as String? ?? '',
        secondaryText: json['secondary_text'] as String? ?? '',
      );

  /// The provider's identifier. Opaque — never parsed, never constructed here.
  final String placeId;

  /// "Jaipur International Airport"
  final String primaryText;

  /// "Sanganer, Jaipur, Rajasthan"
  final String secondaryText;

  bool get isUsable => placeId.isNotEmpty && primaryText.isNotEmpty;
}

/// A resolved place: the thing a trip endpoint can actually be built from.
///
/// Coordinates are non-nullable by construction, on both sides of the wire. A
/// provider that cannot say where a place is has not resolved it, and a details
/// object without a position would push that judgement onto every screen.
class PlaceDetails {
  const PlaceDetails({
    required this.placeId,
    required this.displayName,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.city,
    this.region,
    this.countryCode,
    this.postalCode,
  });

  /// Returns null when the payload has no usable position.
  ///
  /// Null rather than a zeroed default: (0, 0) is a real point in the Gulf of
  /// Guinea, and a journey drawn to it crosses an ocean while looking perfectly
  /// ordinary in a list.
  static PlaceDetails? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final double? latitude = _decimal(json['latitude']);
    final double? longitude = _decimal(json['longitude']);
    if (latitude == null || longitude == null) return null;

    return PlaceDetails(
      placeId: json['place_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      formattedAddress: json['formatted_address'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      city: _text(json['city']),
      region: _text(json['region']),
      countryCode: _text(json['country_code']),
      postalCode: _text(json['postal_code']),
    );
  }

  final String placeId;
  final String displayName;
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final String? city;
  final String? region;
  final String? countryCode;
  final String? postalCode;

  static String? _text(Object? value) {
    final String trimmed = (value as String?)?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _decimal(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
