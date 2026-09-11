import '../../core/geo/polyline_codec.dart';

/// The box a route fits inside.
///
/// Comes from the server rather than being derived on the phone, so the camera
/// frames the same area the corridor search will later use. Deriving it here
/// would mean decoding the whole geometry before the first frame.
class RouteBounds {
  const RouteBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  static RouteBounds? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final double? north = _decimal(json['north']);
    final double? south = _decimal(json['south']);
    final double? east = _decimal(json['east']);
    final double? west = _decimal(json['west']);

    if (north == null || south == null || east == null || west == null) {
      return null;
    }

    // A box with its corners crossed frames nothing, and asking a map to fit it
    // is how a camera ends up over the Atlantic.
    if (north < south) return null;

    return RouteBounds(north: north, south: south, east: east, west: west);
  }

  final double north;
  final double south;
  final double east;
  final double west;

  GeoPoint get southWest => GeoPoint(south, west);

  GeoPoint get northEast => GeoPoint(north, east);

  static double? _decimal(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// One route the provider returned for a trip.
///
/// Units are the point. `distanceMeters` and `durationSeconds` are integers all
/// the way from the provider to the widget that formats them, because a value
/// that arrives as "278 km" cannot be shown in miles, cannot be summed, and
/// cannot be re-rendered in another language.
class TripRoute {
  const TripRoute({
    required this.id,
    required this.provider,
    required this.providerRouteIndex,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
    required this.isRecommended,
    required this.isSelected,
    this.summary,
    this.trafficDurationSeconds,
    this.trafficDelaySeconds,
    this.bounds,
    this.calculatedAt,
  });

  /// Returns null for anything that could not be drawn or read.
  ///
  /// A route with no distance, no duration or no geometry is not a route. The
  /// server refuses to store one; this refuses to render one, because between
  /// the two sits a network.
  static TripRoute? fromJson(Map<String, dynamic> json) {
    final int? distance = _whole(json['distance_meters']);
    final int? duration = _whole(json['duration_seconds']);
    final String polyline = json['encoded_polyline'] as String? ?? '';
    final String id = json['route_id'] as String? ?? '';

    if (id.isEmpty ||
        distance == null ||
        distance <= 0 ||
        duration == null ||
        duration <= 0 ||
        polyline.isEmpty) {
      return null;
    }

    return TripRoute(
      id: id,
      provider: json['provider'] as String? ?? '',
      providerRouteIndex: _whole(json['provider_route_index']) ?? 0,
      summary: _text(json['summary']),
      distanceMeters: distance,
      durationSeconds: duration,
      trafficDurationSeconds: _whole(json['traffic_duration_seconds']),
      trafficDelaySeconds: _whole(json['traffic_delay_seconds']),
      encodedPolyline: polyline,
      bounds: RouteBounds.fromJson(json['bounds'] as Map<String, dynamic>?),
      isRecommended: json['is_recommended'] as bool? ?? false,
      isSelected: json['is_selected'] as bool? ?? false,
      calculatedAt: _time(json['calculated_at']),
    );
  }

  final String id;

  /// Which service produced this.
  ///
  /// Carried to the screen on purpose: a route from a development stand-in is
  /// labelled as one, so a synthetic line can never be mistaken for a road.
  final String provider;

  final int providerRouteIndex;

  /// "via NH 48" — the provider's own words, shown as-is or not at all.
  final String? summary;

  final int distanceMeters;

  /// The journey without traffic.
  final int durationSeconds;

  /// The journey in current traffic, or null when the provider gave none.
  ///
  /// Null is not zero. An absent traffic reading is not a claim that traffic is
  /// costing nothing.
  final int? trafficDurationSeconds;

  /// How much longer traffic is making it, when that is a real figure.
  final int? trafficDelaySeconds;

  final String encodedPolyline;
  final RouteBounds? bounds;
  final bool isRecommended;
  final bool isSelected;

  /// Always UTC. What "calculated a few minutes ago" is measured from.
  final DateTime? calculatedAt;

  bool get hasTraffic => trafficDurationSeconds != null;

  /// The duration to lead with: traffic-aware when there is one.
  int get effectiveDurationSeconds => trafficDurationSeconds ?? durationSeconds;

  /// Whether this came from a real routing provider.
  ///
  /// Anything else is a development stand-in, and the screen says so rather
  /// than letting a straight line pass for a road.
  bool get isFromRealProvider =>
      provider.isNotEmpty && provider != 'development' && provider != 'fixture';

  /// The geometry, decoded, or an empty list if it cannot be read.
  ///
  /// Never throws: a route that will not decode must degrade to "no line on the
  /// map" rather than taking the screen down with it. The empty result is what
  /// the map layer checks before drawing.
  List<GeoPoint> points() {
    try {
      return PolylineCodec.decode(encodedPolyline);
    } on PolylineFormatException {
      return const <GeoPoint>[];
    }
  }

  static String? _text(Object? value) {
    final String trimmed = (value as String?)?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _whole(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _time(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// A trip's route summary as it appears on a trip payload.
///
/// Deliberately without geometry: a list of ten journeys must not be ten
/// polylines, and the home card needs a distance and a time rather than a line.
class RouteSummary {
  const RouteSummary({
    required this.routeId,
    required this.distanceMeters,
    required this.durationSeconds,
    this.trafficDurationSeconds,
    this.trafficDelaySeconds,
    this.summary,
    this.calculatedAt,
  });

  static RouteSummary? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final int? distance = TripRoute._whole(json['distance_meters']);
    final int? duration = TripRoute._whole(json['duration_seconds']);

    if (distance == null ||
        distance <= 0 ||
        duration == null ||
        duration <= 0) {
      return null;
    }

    return RouteSummary(
      routeId: json['route_id'] as String? ?? '',
      distanceMeters: distance,
      durationSeconds: duration,
      trafficDurationSeconds: TripRoute._whole(
        json['traffic_duration_seconds'],
      ),
      trafficDelaySeconds: TripRoute._whole(json['traffic_delay_seconds']),
      summary: TripRoute._text(json['summary']),
      calculatedAt: TripRoute._time(json['calculated_at']),
    );
  }

  final String routeId;
  final int distanceMeters;
  final int durationSeconds;
  final int? trafficDurationSeconds;
  final int? trafficDelaySeconds;
  final String? summary;
  final DateTime? calculatedAt;

  int get effectiveDurationSeconds => trafficDurationSeconds ?? durationSeconds;
}
