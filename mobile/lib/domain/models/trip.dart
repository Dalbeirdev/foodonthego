import 'saved_address.dart';

/// The states a journey can be in.
///
/// Two, matching the server exactly. On the road, arrived and completed are
/// claims about the physical world that nothing in the product can observe yet;
/// Module 09 adds them when there is movement to watch. A journey that is behind
/// the traveller is not a status — it is [Trip.hasDeparted], a fact about the
/// clock.
enum TripStatus {
  planned('PLANNED'),
  cancelled('CANCELLED');

  const TripStatus(this.wire);

  final String wire;

  static TripStatus fromWire(String? value) {
    for (final TripStatus status in TripStatus.values) {
      if (status.wire == value) return status;
    }
    // A state a newer server introduced. An older build treats it as planned
    // rather than crashing, which is the reading that keeps the journey visible
    // and read-only — `is_editable` comes from the server anyway.
    return TripStatus.planned;
  }
}

/// One end of a journey, as the server stored it.
///
/// A *snapshot*, not a reference to a saved address: it is what the place was
/// when the journey was planned. Editing the saved address it came from does
/// not change this, which is deliberate on both sides of the wire.
class JourneyPlace {
  const JourneyPlace({
    required this.label,
    required this.formattedAddress,
    required this.city,
    required this.countryCode,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  factory JourneyPlace.fromJson(Map<String, dynamic> json) => JourneyPlace(
    label: json['label'] as String? ?? '',
    formattedAddress: json['formatted_address'] as String? ?? '',
    city: json['city'] as String? ?? '',
    countryCode: json['country_code'] as String? ?? '',
    latitude: _decimal(json['latitude']),
    longitude: _decimal(json['longitude']),
    placeId: json['place_id'] as String?,
  );

  final String label;
  final String formattedAddress;
  final String city;
  final String countryCode;

  /// Null until something actually geocodes this place. Never substitute 0 —
  /// that is a real point in the Gulf of Guinea, and a corridor drawn to it
  /// crosses an ocean.
  final double? latitude;
  final double? longitude;
  final String? placeId;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// What a compact row shows: the customer's name for the place if they gave
  /// one meaningfully different from the city, otherwise the city.
  String get shortName => label.trim().isEmpty ? city : label.trim();

  static double? _decimal(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// A journey a customer has planned.
class Trip {
  const Trip({
    required this.id,
    required this.status,
    required this.origin,
    required this.destination,
    required this.departureAt,
    required this.isEditable,
    required this.hasDeparted,
    this.expectedArrivalAt,
    this.travellerCount = 1,
    this.note,
    this.cancelledAt,
    this.cancellationReason,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String? ?? '',
    status: TripStatus.fromWire(json['status'] as String?),
    origin: JourneyPlace.fromJson(
      (json['origin'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    ),
    destination: JourneyPlace.fromJson(
      (json['destination'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    ),
    departureAt: _time(json['departure_at']) ?? DateTime.now().toUtc(),
    expectedArrivalAt: _time(json['expected_arrival_at']),
    travellerCount: (json['traveller_count'] as num?)?.toInt() ?? 1,
    note: json['note'] as String?,
    cancelledAt: _time(json['cancelled_at']),
    cancellationReason: json['cancellation_reason'] as String?,
    // Read from the server rather than recomputed here. A handset with a slow
    // clock would otherwise offer an edit the server then refuses.
    isEditable: json['is_editable'] as bool? ?? false,
    hasDeparted: json['has_departed'] as bool? ?? false,
  );

  final String id;
  final TripStatus status;
  final JourneyPlace origin;
  final JourneyPlace destination;

  /// Always UTC. Rendered in the device's zone at the edge, never stored local.
  final DateTime departureAt;

  /// Null in the normal case: nothing computes an arrival time yet, and a
  /// traveller who states one is telling us something they know.
  final DateTime? expectedArrivalAt;

  final int travellerCount;
  final String? note;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  final bool isEditable;
  final bool hasDeparted;

  bool get isCancelled => status == TripStatus.cancelled;

  /// Still ahead of the traveller and not called off.
  bool get isUpcoming => !isCancelled && !hasDeparted;

  /// "New Delhi → Jaipur", the one line that identifies a journey in a list.
  String get routeSummary => '${origin.shortName} → ${destination.shortName}';

  static DateTime? _time(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// One end of a journey as the *client* sends it.
///
/// Either a saved address — by id, with the server doing the ownership check and
/// the snapshotting — or a typed place. Never both: [savedAddressId] wins, and
/// the typed fields are not sent alongside it, so there is no request in which
/// the two could disagree.
class JourneyPlaceDraft {
  const JourneyPlaceDraft.saved(this.savedAddressId)
    : label = null,
      addressLine = null,
      city = null,
      state = null,
      countryCode = null,
      latitude = null,
      longitude = null,
      placeId = null;

  const JourneyPlaceDraft.typed({
    required this.city,
    required this.countryCode,
    this.label,
    this.addressLine,
    this.state,
    this.latitude,
    this.longitude,
    this.placeId,
  }) : savedAddressId = null;

  /// Builds a draft from a saved address the customer picked.
  factory JourneyPlaceDraft.fromSavedAddress(SavedAddress address) =>
      JourneyPlaceDraft.saved(address.id);

  final String? savedAddressId;
  final String? label;
  final String? addressLine;
  final String? city;
  final String? state;
  final String? countryCode;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  bool get isSavedAddress => savedAddressId != null;

  /// The wire form. A blank optional field is **absent**, not an empty string:
  /// the server treats absent as "not supplied" and would store "" as a value.
  Map<String, dynamic> toJson() {
    if (savedAddressId != null) {
      return <String, dynamic>{'address_id': savedAddressId};
    }

    final Map<String, dynamic> json = <String, dynamic>{
      'city': city?.trim(),
      'country_code': countryCode?.trim().toUpperCase(),
    };

    void put(String key, String? value) {
      final String? trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) json[key] = trimmed;
    }

    put('label', label);
    put('address_line', addressLine);
    put('state', state);
    put('place_id', placeId);

    // Both or neither. Half a coordinate is not half a location, and the server
    // refuses it — sending it would be a validation error the customer cannot
    // act on, because no field on the form produced it.
    if (latitude != null && longitude != null) {
      json['latitude'] = latitude;
      json['longitude'] = longitude;
    }

    return json;
  }
}

/// A journey as the client sends it.
class TripDraft {
  const TripDraft({
    required this.origin,
    required this.destination,
    required this.departureAt,
    this.expectedArrivalAt,
    this.travellerCount = 1,
    this.note,
    this.clearArrival = false,
    this.clearNote = false,
  });

  final JourneyPlaceDraft? origin;
  final JourneyPlaceDraft? destination;

  /// Null on a partial update means "leave the departure alone".
  final DateTime? departureAt;
  final DateTime? expectedArrivalAt;
  final int? travellerCount;
  final String? note;

  /// Explicit clears, distinguished from "not supplied" the same way the profile
  /// form distinguishes them. Sending null for a field the customer did not
  /// touch would erase it.
  final bool clearArrival;
  final bool clearNote;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{};

    if (origin != null) json['origin'] = origin!.toJson();
    if (destination != null) json['destination'] = destination!.toJson();

    if (departureAt != null) {
      json['departure_at'] = departureAt!.toUtc().toIso8601String();
    }

    if (clearArrival) {
      json['expected_arrival_at'] = null;
    } else if (expectedArrivalAt != null) {
      json['expected_arrival_at'] = expectedArrivalAt!
          .toUtc()
          .toIso8601String();
    }

    if (travellerCount != null) json['traveller_count'] = travellerCount;

    if (clearNote) {
      json['note'] = null;
    } else {
      final String? trimmed = note?.trim();
      if (trimmed != null && trimmed.isNotEmpty) json['note'] = trimmed;
    }

    return json;
  }
}

/// Which slice of a customer's journeys to ask for.
enum TripScope {
  upcoming('upcoming'),
  past('past'),
  cancelled('cancelled'),
  all('all');

  const TripScope(this.wire);

  final String wire;
}
