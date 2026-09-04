/// The three categories a saved address can be.
///
/// The trip planner will offer Home and Work as one-tap origins, which is why
/// this is a fixed set rather than free text. What the customer *calls* the
/// place is [SavedAddress.label], and that is free text.
enum AddressType {
  home('HOME'),
  work('WORK'),
  other('OTHER');

  const AddressType(this.wire);

  /// The value the API uses.
  final String wire;

  static AddressType fromWire(String? value) {
    for (final AddressType type in AddressType.values) {
      if (type.wire == value) return type;
    }
    // A category a newer server introduced. Falls back rather than crashing an
    // older build, and "Other" is the honest description of a type it has never
    // heard of.
    return AddressType.other;
  }

  /// Whether the customer has to name this place themselves. "Other" in a list
  /// of three Others is unreadable.
  bool get needsCustomLabel => this == AddressType.other;
}

/// A place a customer has saved.
///
/// [latitude] and [longitude] are null until something actually geocodes the
/// address. A client must treat null as "unknown" and never substitute 0 — that
/// is a real place in the Gulf of Guinea, and a route to it is a route into the
/// Atlantic.
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.type,
    required this.label,
    required this.addressLine1,
    required this.city,
    required this.state,
    required this.countryCode,
    required this.formattedAddress,
    this.addressLine2,
    this.landmark,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.placeId,
    this.isDefault = false,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
    id: json['id'] as String? ?? '',
    type: AddressType.fromWire(json['type'] as String?),
    label: json['label'] as String? ?? '',
    addressLine1: json['address_line_1'] as String? ?? '',
    addressLine2: json['address_line_2'] as String?,
    landmark: json['landmark'] as String?,
    city: json['city'] as String? ?? '',
    state: json['state'] as String? ?? '',
    postalCode: json['postal_code'] as String?,
    countryCode: json['country_code'] as String? ?? '',
    formattedAddress: json['formatted_address'] as String? ?? '',
    latitude: _decimal(json['latitude']),
    longitude: _decimal(json['longitude']),
    placeId: json['place_id'] as String?,
    isDefault: json['is_default'] as bool? ?? false,
  );

  final String id;
  final AddressType type;
  final String label;
  final String addressLine1;
  final String? addressLine2;
  final String? landmark;
  final String city;
  final String state;
  final String? postalCode;
  final String countryCode;

  /// The single line the server composed. Displayed rather than re-composed
  /// locally, so the app and the server never disagree about one address.
  final String formattedAddress;

  final double? latitude;
  final double? longitude;
  final String? placeId;
  final bool isDefault;

  /// Whether this address can be handed to a map or a routing engine yet.
  ///
  /// False for everything saved before the mapping module connects Places, which
  /// is why the trip planner will need to geocode on demand rather than assume.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// The address without the city line, for the second row of a list item where
  /// the label is already the first.
  String get shortAddress {
    final List<String> parts = <String>[
      addressLine1,
      if (addressLine2 != null && addressLine2!.trim().isNotEmpty)
        addressLine2!,
    ];
    return parts.join(', ');
  }

  /// "New Delhi, Delhi 110016" — the locality line.
  String get localityLine {
    final String region = <String>[
      state,
      if (postalCode != null && postalCode!.trim().isNotEmpty) postalCode!,
    ].join(' ').trim();

    return <String>[city, if (region.isNotEmpty) region].join(', ');
  }

  /// The API sends decimals as strings so they do not lose precision in JSON.
  static double? _decimal(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// What the form sends. Deliberately not [SavedAddress]: a draft has no id, no
/// server-composed one-line form, and no default flag the server has agreed to.
class AddressDraft {
  const AddressDraft({
    required this.type,
    required this.addressLine1,
    required this.city,
    required this.state,
    required this.countryCode,
    this.label,
    this.addressLine2,
    this.landmark,
    this.postalCode,
    this.isDefault = false,
  });

  final AddressType type;
  final String? label;
  final String addressLine1;
  final String? addressLine2;
  final String? landmark;
  final String city;
  final String state;
  final String? postalCode;
  final String countryCode;
  final bool isDefault;

  /// Blank optional fields are sent as absent, not as "". An empty string is not
  /// a landmark, and storing one makes every later null check wrong.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.wire,
    if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
    'address_line_1': addressLine1.trim(),
    'address_line_2': _orNull(addressLine2),
    'landmark': _orNull(landmark),
    'city': city.trim(),
    'state': state.trim(),
    'postal_code': _orNull(postalCode),
    'country_code': countryCode.trim().toUpperCase(),
    'is_default': isDefault,
  };

  static String? _orNull(String? value) {
    final String trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
