import 'dart:math' as math;

import 'place.dart';
import 'saved_address.dart';

/// Where the customer got a location from.
///
/// Recorded per endpoint because the three sources have genuinely different
/// trust: a device fix is authoritative about where somebody is, a saved address
/// is something they wrote down once, and a searched place is the provider's
/// answer to a question. Module 06 will care about the difference, and so does
/// the operational log today.
enum LocationSourceType {
  currentLocation('CURRENT_LOCATION'),
  savedAddress('SAVED_ADDRESS'),
  placeSearch('PLACE_SEARCH');

  const LocationSourceType(this.wire);

  final String wire;

  static LocationSourceType fromWire(String? value) {
    for (final LocationSourceType type in LocationSourceType.values) {
      if (type.wire == value) return type;
    }
    // A source a newer server introduced. Reading it as a searched place keeps
    // the trip visible and correct in every way that matters to this screen.
    return LocationSourceType.placeSearch;
  }
}

/// What has happened to the trip itself.
///
/// Two states, matching the server exactly. There is no "active", "on the road"
/// or "completed": those are claims about the physical world that nothing in the
/// product can observe yet, and a status the app can display but never reach is
/// a status somebody will eventually write a screen for.
enum TripStatus {
  routePending('ROUTE_PENDING'),
  cancelled('CANCELLED');

  const TripStatus(this.wire);

  final String wire;

  static TripStatus fromWire(String? value) {
    for (final TripStatus status in TripStatus.values) {
      if (status.wire == value) return status;
    }
    return TripStatus.routePending;
  }
}

/// Whether a route has been calculated for this trip.
///
/// Separate from [TripStatus] because they answer different questions, and in
/// Module 05 this is **always** [RouteStatus.notCalculated]. It exists here so
/// the app reads the server's answer rather than assuming one; Module 06 is what
/// moves it, and until then no screen may render a distance or a travel time,
/// because there is none to render.
enum RouteStatus {
  notCalculated('NOT_CALCULATED'),
  calculating('CALCULATING'),
  ready('READY'),
  failed('FAILED');

  const RouteStatus(this.wire);

  final String wire;

  static RouteStatus fromWire(String? value) {
    for (final RouteStatus status in RouteStatus.values) {
      if (status.wire == value) return status;
    }
    return RouteStatus.notCalculated;
  }
}

/// One end of a trip, as the server stored it.
///
/// A **snapshot**, not a reference. It is what the place was when the trip was
/// created: editing or deleting the saved address it came from does not move the
/// journey, which is deliberate on both sides of the wire.
class TripEndpoint {
  const TripEndpoint({
    required this.sourceType,
    required this.displayName,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.city,
    this.region,
    this.countryCode,
    this.postalCode,
  });

  factory TripEndpoint.fromJson(Map<String, dynamic> json) => TripEndpoint(
    sourceType: LocationSourceType.fromWire(json['source_type'] as String?),
    displayName: (json['display_name'] as String?)?.trim() ?? '',
    formattedAddress: (json['formatted_address'] as String?)?.trim() ?? '',
    // The server sends coordinates as strings so the last decimal place — which
    // is metres — survives the trip through JSON intact.
    latitude: _decimal(json['latitude']) ?? 0,
    longitude: _decimal(json['longitude']) ?? 0,
    placeId: _text(json['place_id']),
    city: _text(json['city']),
    region: _text(json['region']),
    countryCode: _text(json['country_code']),
    postalCode: _text(json['postal_code']),
  );

  final LocationSourceType sourceType;
  final String displayName;
  final String formattedAddress;

  /// Never null. The server refuses to create a trip without a usable pair, so
  /// an endpoint that reached this app has one.
  final double latitude;
  final double longitude;

  final String? placeId;
  final String? city;
  final String? region;
  final String? countryCode;
  final String? postalCode;

  /// What a compact row shows.
  String get shortName {
    if (displayName.isNotEmpty) return displayName;
    if ((city ?? '').isNotEmpty) return city!;
    return formattedAddress;
  }

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

/// A trip a customer has created.
///
/// Read the absences. There is no distance, no travel time, no arrival estimate
/// and no polyline, because the server has no such columns and Module 06 is what
/// adds them. A field here that no endpoint fills is a field a screen would
/// eventually render as "0 km".
class Trip {
  const Trip({
    required this.id,
    required this.status,
    required this.routeStatus,
    required this.origin,
    required this.destination,
    this.cancelledAt,
    this.createdAt,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String? ?? '',
    status: TripStatus.fromWire(json['status'] as String?),
    routeStatus: RouteStatus.fromWire(json['route_status'] as String?),
    origin: TripEndpoint.fromJson(
      (json['origin'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    ),
    destination: TripEndpoint.fromJson(
      (json['destination'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    ),
    cancelledAt: _time(json['cancelled_at']),
    createdAt: _time(json['created_at']),
  );

  final String id;
  final TripStatus status;
  final RouteStatus routeStatus;
  final TripEndpoint origin;
  final TripEndpoint destination;

  /// Always UTC. Rendered in the device's zone at the edge, never stored local.
  final DateTime? cancelledAt;
  final DateTime? createdAt;

  bool get isCancelled => status == TripStatus.cancelled;

  bool get isDiscardable => !isCancelled;

  /// Whether a route exists yet. False for every trip Module 05 can create, and
  /// the reason no screen shows a distance.
  bool get hasRoute => routeStatus == RouteStatus.ready;

  /// "New Delhi → Jaipur", the one line that identifies a trip in a list.
  String get routeSummary => '${origin.shortName} → ${destination.shortName}';

  static DateTime? _time(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// One end of a trip as the *client* sends it.
///
/// Three constructors, one per source, and no way to build a fourth kind. A
/// single constructor with everything nullable would let a screen send a saved
/// address id *and* a contradicting coordinate pair, and the server would have
/// to decide which of the two the customer meant.
class TripLocation {
  const TripLocation._({
    required this.sourceType,
    required this.displayName,
    required this.formattedAddress,
    this.savedAddressId,
    this.placeId,
    this.latitude,
    this.longitude,
    this.city,
    this.region,
    this.countryCode,
    this.postalCode,
  });

  /// A place the customer searched for and the server then resolved.
  ///
  /// Built from [PlaceDetails] and never from a [PlaceSuggestion], because a
  /// suggestion has no position and the only way to give it one would be to
  /// invent it.
  factory TripLocation.fromPlace(PlaceDetails place) => TripLocation._(
    sourceType: LocationSourceType.placeSearch,
    displayName: place.displayName,
    formattedAddress: place.formattedAddress,
    // Normalised to null when blank. An empty id is the absence of an id, and
    // keeping it as "" would make every unidentified place equal to every
    // other one under [isSamePlaceAs].
    placeId: place.placeId.trim().isEmpty ? null : place.placeId,
    latitude: place.latitude,
    longitude: place.longitude,
    city: place.city,
    region: place.region,
    countryCode: place.countryCode,
    postalCode: place.postalCode,
  );

  /// The device's own fix.
  ///
  /// [named] is the reverse-geocoded description when the server could produce
  /// one. When it could not, the coordinates still stand — they came from the
  /// hardware and are authoritative — and the endpoint is simply labelled
  /// "Current location", which is true of any coordinate.
  factory TripLocation.fromCurrentLocation({
    required double latitude,
    required double longitude,
    required String fallbackLabel,
    PlaceDetails? named,
  }) => TripLocation._(
    sourceType: LocationSourceType.currentLocation,
    displayName: fallbackLabel,
    formattedAddress: named?.formattedAddress ?? '',
    placeId: named?.placeId,
    latitude: latitude,
    longitude: longitude,
    city: named?.city,
    region: named?.region,
    countryCode: named?.countryCode,
    postalCode: named?.postalCode,
  );

  /// One of the customer's saved addresses.
  ///
  /// Only the id crosses the wire. The server looks the address up **through the
  /// signed-in customer's own scope** and copies the values out of the database,
  /// so a client cannot substitute somebody else's row and cannot dictate what a
  /// row it does own contains.
  ///
  /// Returns null for an address with no coordinates: it cannot be used as a
  /// trip endpoint, and the caller must ask the customer to locate it rather
  /// than sending it and hoping.
  static TripLocation? fromSavedAddress(SavedAddress address) {
    if (!address.hasCoordinates) return null;

    return TripLocation._(
      sourceType: LocationSourceType.savedAddress,
      savedAddressId: address.id,
      displayName: address.label,
      formattedAddress: address.formattedAddress,
      // Kept for the row the customer is looking at, never sent: see [toJson].
      latitude: address.latitude,
      longitude: address.longitude,
      city: address.city,
    );
  }

  final LocationSourceType sourceType;
  final String? savedAddressId;
  final String displayName;
  final String formattedAddress;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? region;
  final String? countryCode;
  final String? postalCode;

  bool get isSavedAddress => sourceType == LocationSourceType.savedAddress;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// What the picker row shows under the name.
  String get secondaryLine {
    if (formattedAddress.isNotEmpty) return formattedAddress;
    if ((city ?? '').isNotEmpty) return city!;
    return '';
  }

  /// Straight-line metres to another endpoint, for the client-side "these are
  /// the same place" check.
  ///
  /// Advisory only — the server runs the same rule and its answer is the one
  /// that decides. Doing it here as well is what turns a round trip and an error
  /// banner into an inline message before the customer taps anything.
  double? distanceInMetresTo(TripLocation other) {
    if (!hasCoordinates || !other.hasCoordinates) return null;

    const double earthRadius = 6371000;

    final double phi1 = latitude! * math.pi / 180;
    final double phi2 = other.latitude! * math.pi / 180;
    final double deltaPhi = phi2 - phi1;
    final double deltaLambda = (other.longitude! - longitude!) * math.pi / 180;

    final double a =
        math.pow(math.sin(deltaPhi / 2), 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.pow(math.sin(deltaLambda / 2), 2);

    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Whether these two ends are, for practical purposes, the same place.
  ///
  /// Same provider place id, or the same saved address, or close enough that
  /// nobody would drive it. The threshold matches the server's default; the
  /// server is still the authority.
  bool isSamePlaceAs(TripLocation other, {double thresholdMetres = 75}) {
    // Both identity checks require a non-empty value on this side. An absent id
    // is not evidence of sameness, and treating "" == "" as a match would make
    // two unrelated unidentified places the same place.
    if ((placeId ?? '').isNotEmpty && placeId == other.placeId) return true;
    if ((savedAddressId ?? '').isNotEmpty &&
        savedAddressId == other.savedAddressId) {
      return true;
    }

    final double? metres = distanceInMetresTo(other);

    return metres != null && metres <= thresholdMetres;
  }

  /// The wire form.
  ///
  /// A saved address sends its id and **nothing else**. Sending the coordinates
  /// alongside would create a request in which the two could disagree, and the
  /// server would then be choosing between a value it can verify and one it
  /// cannot.
  Map<String, dynamic> toJson() {
    if (isSavedAddress) {
      return <String, dynamic>{
        'source_type': sourceType.wire,
        'saved_address_id': savedAddressId,
      };
    }

    final Map<String, dynamic> json = <String, dynamic>{
      'source_type': sourceType.wire,
      'latitude': latitude,
      'longitude': longitude,
    };

    void put(String key, String? value) {
      final String trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) json[key] = trimmed;
    }

    put('place_id', placeId);
    put('display_name', displayName);
    put('formatted_address', formattedAddress);
    put('city', city);
    put('region', region);
    put('country_code', countryCode);
    put('postal_code', postalCode);

    return json;
  }
}

/// A trip as the client sends it.
///
/// Two fields, because a trip is two places. Everything a caller might hope to
/// seed — the customer id, the status, the route status, a distance, an ETA — is
/// absent here *and* rejected there; this class simply has nowhere to put them.
class TripDraft {
  const TripDraft({required this.origin, required this.destination});

  final TripLocation origin;
  final TripLocation destination;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'origin': origin.toJson(),
    'destination': destination.toJson(),
  };
}
