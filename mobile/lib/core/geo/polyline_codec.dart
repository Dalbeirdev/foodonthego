import 'dart:math' as math;

/// One point on a route.
///
/// This app's own type rather than the map plugin's `LatLng`, so the domain,
/// the repositories and every test stay independent of which map is on screen
/// — and so a widget test can run without a platform view.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// A polyline that could not be read.
class PolylineFormatException implements Exception {
  const PolylineFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'PolylineFormatException: $reason';
}

/// Google's encoded polyline algorithm, decoding half.
///
/// The mirror of the backend's implementation, and it exists for the same
/// reason: what arrives has to be *proved* to be geometry before anything draws
/// it. The server validates before storing; this validates before rendering,
/// because between the two sits a network and a JSON parser.
///
/// Forty lines, so no dependency. A map plugin's own decoder would tie this to
/// whichever map is on screen, and the decoded points are needed for the camera
/// bounds whether a map renders or not.
class PolylineCodec {
  const PolylineCodec._();

  /// A route across India is a few thousand points. This is well above that and
  /// exists so a malformed payload cannot become an unbounded list on a phone.
  static const int maxPoints = 100000;

  static List<GeoPoint> decode(String encoded) {
    if (encoded.isEmpty) {
      throw const PolylineFormatException('the polyline was empty');
    }

    final List<GeoPoint> points = <GeoPoint>[];
    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      for (int component = 0; component < 2; component++) {
        int shift = 0;
        int result = 0;
        int byte;

        do {
          if (index >= encoded.length) {
            throw const PolylineFormatException('the polyline ended mid-value');
          }

          byte = encoded.codeUnitAt(index++) - 63;

          if (byte < 0) {
            throw const PolylineFormatException(
              'the polyline contained a character outside the alphabet',
            );
          }

          result |= (byte & 0x1f) << shift;
          shift += 5;

          // Five bits per character and a coordinate is at most 32 bits. Beyond
          // this the string is not a polyline, and continuing would shift into
          // nothing for ever.
          if (shift > 35) {
            throw const PolylineFormatException(
              'the polyline contained an over-long value',
            );
          }
        } while (byte >= 0x20);

        final int delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

        if (component == 0) {
          latitude += delta;
        } else {
          longitude += delta;
        }
      }

      points.add(GeoPoint(latitude / 1e5, longitude / 1e5));

      if (points.length > maxPoints) {
        throw const PolylineFormatException(
          'the polyline held more points than we will decode',
        );
      }
    }

    if (points.isEmpty) {
      throw const PolylineFormatException('the polyline decoded to no points');
    }

    return points;
  }

  /// Encodes points. Used by tests and fixtures; the app only ever decodes.
  static String encode(List<GeoPoint> points) {
    final StringBuffer buffer = StringBuffer();
    int previousLatitude = 0;
    int previousLongitude = 0;

    for (final GeoPoint point in points) {
      final int latitude = (point.latitude * 1e5).round();
      final int longitude = (point.longitude * 1e5).round();

      _writeValue(buffer, latitude - previousLatitude);
      _writeValue(buffer, longitude - previousLongitude);

      previousLatitude = latitude;
      previousLongitude = longitude;
    }

    return buffer.toString();
  }

  static void _writeValue(StringBuffer buffer, int value) {
    int shifted = value < 0 ? ~(value << 1) : (value << 1);

    while (shifted >= 0x20) {
      buffer.writeCharCode((0x20 | (shifted & 0x1f)) + 63);
      shifted >>= 5;
    }

    buffer.writeCharCode(shifted + 63);
  }

  /// Straight-line metres between two points.
  ///
  /// Used to sanity-check that geometry starts and ends roughly where the
  /// journey does — never to *derive* a distance. A route's length is the road,
  /// not the crow's flight, and the difference on a Delhi–Jaipur journey is
  /// about forty kilometres.
  static double metresBetween(GeoPoint a, GeoPoint b) {
    const double earthRadius = 6371000;

    final double phi1 = a.latitude * math.pi / 180;
    final double phi2 = b.latitude * math.pi / 180;
    final double deltaPhi = phi2 - phi1;
    final double deltaLambda = (b.longitude - a.longitude) * math.pi / 180;

    final double h =
        math.pow(math.sin(deltaPhi / 2), 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.pow(math.sin(deltaLambda / 2), 2);

    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}
