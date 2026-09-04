import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A position the device produced.
///
/// [accuracyMetres] is carried because it is the honest part of a fix: a
/// coordinate is exact-looking whatever its provenance, and a 2 km cell-tower
/// fix and a 5 m GPS fix render identically unless something says otherwise.
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMetres,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMetres;

  /// Whether the fix is precise enough to set off from without a warning.
  bool get isCoarse => (accuracyMetres ?? 0) > 500;
}

/// Every way asking for the device's position can end.
///
/// A sealed hierarchy rather than a nullable position and a flag, because these
/// outcomes need genuinely different screens and an `if (position == null)`
/// collapses six of them into one apology. In particular
/// [LocationServicesDisabled] must never be reported as a denial: the customer
/// has denied nothing, and telling them they did sends them to an app-permission
/// screen that will not fix it.
sealed class LocationResult {
  const LocationResult();
}

/// The device answered.
final class LocationFix extends LocationResult {
  const LocationFix(this.location);

  final DeviceLocation location;
}

/// Refused this time. The customer can be asked again later.
final class LocationPermissionDenied extends LocationResult {
  const LocationPermissionDenied();
}

/// Refused permanently, or blocked by device policy. The system will not show a
/// prompt again, so the only route through is the settings app — and the screen
/// must say so rather than offering a button that does nothing.
final class LocationPermissionDeniedForever extends LocationResult {
  const LocationPermissionDeniedForever();
}

/// Location is switched off on the device itself.
///
/// Distinct from a denial, and the distinction is the whole point of this class:
/// the permission may be granted and the answer still be this one.
final class LocationServicesDisabled extends LocationResult {
  const LocationServicesDisabled();
}

/// The hardware was asked and did not answer in time.
///
/// Common and unremarkable indoors, in a tunnel, or on a cold GPS start. The
/// screen offers "Try again" and a search box, not an error.
final class LocationTimedOut extends LocationResult {
  const LocationTimedOut();
}

/// The platform failed in some other way.
final class LocationUnavailable extends LocationResult {
  const LocationUnavailable(this.reason);

  /// For the log and for development. Never rendered to a customer: a platform
  /// message is written for whoever wrote the platform.
  final String reason;
}

/// Reading the device's position.
///
/// An interface so tests can produce every branch above without a device, a
/// permission dialog or a GPS antenna — which is the only way the six failure
/// screens get exercised at all.
abstract interface class LocationService {
  /// Asks for a single fix, requesting permission first if it is needed.
  ///
  /// Deliberately one-shot. Module 05 needs to know where somebody is *now*, at
  /// the moment they tap "Use my current location", and nothing more: there is
  /// no stream, no background permission, and no reason for this app to watch
  /// anybody move.
  Future<LocationResult> currentLocation({Duration timeout});

  /// Opens the OS settings page where a permanent denial can be undone.
  ///
  /// Returns false when the platform declined to open it, so the screen can fall
  /// back to telling the customer where to go rather than appearing to do
  /// nothing.
  Future<bool> openPermissionSettings();
}

/// The real one, on top of `geolocator`.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> currentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      // Services first, and before any permission request. Asked the other way
      // round, a device with location switched off produces a permission prompt
      // that cannot help, and then an answer that looks like a refusal.
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServicesDisabled();
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // The contextual request. It happens here — inside the action the
        // customer just took — and nowhere near app start.
        permission = await Geolocator.requestPermission();
      }

      switch (permission) {
        case LocationPermission.denied:
          return const LocationPermissionDenied();
        case LocationPermission.deniedForever:
          return const LocationPermissionDeniedForever();
        case LocationPermission.whileInUse:
        case LocationPermission.always:
        case LocationPermission.unableToDetermine:
          break;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );

      return LocationFix(
        DeviceLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMetres: position.accuracy,
        ),
      );
    } on TimeoutException {
      return const LocationTimedOut();
    } on LocationServiceDisabledException {
      // Can still surface here: services can be switched off between the check
      // above and the fix below.
      return const LocationServicesDisabled();
    } on PermissionDeniedException {
      return const LocationPermissionDenied();
    } on PositionUpdateException catch (error) {
      return LocationUnavailable(error.toString());
    } catch (error) {
      // Platform channels can throw anything at all, and a crash here would take
      // the trip planner down over an optional convenience.
      return LocationUnavailable(error.toString());
    }
  }

  @override
  Future<bool> openPermissionSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
