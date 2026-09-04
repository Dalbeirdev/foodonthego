import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_service.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/place.dart';
import '../../domain/models/trip.dart';
import '../../domain/repositories/place_repository.dart';
import 'providers.dart';

/// Where the "use my current location" action has got to.
sealed class CurrentLocationStatus {
  const CurrentLocationStatus();
}

/// Nothing asked for yet.
///
/// The state the app is in at launch and stays in until the customer taps the
/// row. Permission is requested from [CurrentLocationController.resolve] and
/// nowhere else — never at startup, never on a splash screen, never as the price
/// of opening the planner.
final class CurrentLocationIdle extends CurrentLocationStatus {
  const CurrentLocationIdle();
}

final class CurrentLocationLocating extends CurrentLocationStatus {
  const CurrentLocationLocating();
}

/// A usable origin.
final class CurrentLocationReady extends CurrentLocationStatus {
  const CurrentLocationReady(this.location, {this.isCoarse = false});

  final TripLocation location;

  /// The fix was accurate to worse than half a kilometre. Still usable, and the
  /// customer is told rather than left to discover it when the route starts
  /// somewhere they were not.
  final bool isCoarse;
}

/// The device would not, or could not, say where it is.
///
/// Carries the outcome unchanged so the screen can distinguish the six cases —
/// in particular "location is switched off" from "you said no", which need
/// different words and different buttons.
final class CurrentLocationBlocked extends CurrentLocationStatus {
  const CurrentLocationBlocked(this.reason);

  final LocationResult reason;
}

/// Turning the device's position into a trip endpoint.
///
/// Two steps, and the second one is optional: get a fix, then ask our server to
/// name it. A name that cannot be found is not a failure — the coordinates came
/// from the hardware and are the authoritative part. Labelling them "Current
/// location" is true of any coordinate; inventing an address for them would not
/// be.
class CurrentLocationController extends Notifier<CurrentLocationStatus> {
  /// The picker can close while the device is still being asked. See
  /// [PlaceSearchController] — the same reasoning, and the same fix.
  bool _disposed = false;

  late final LocationService _location;
  late final PlaceRepository _places;

  @override
  CurrentLocationStatus build() {
    _location = ref.read(locationServiceProvider);
    _places = ref.read(placeRepositoryProvider);

    ref.onDispose(() => _disposed = true);

    return const CurrentLocationIdle();
  }

  /// Asks the device, then asks our server for a name.
  ///
  /// Returns the endpoint on success and null otherwise; [state] carries the
  /// detail either way, because the six failure branches need six different
  /// things said to the customer.
  Future<TripLocation?> resolve({required String fallbackLabel}) async {
    state = const CurrentLocationLocating();

    // The backstop. Whatever the platform does — and a browser with an
    // unanswered permission prompt does nothing at all, forever — this future
    // completes, so the sheet can never be left spinning with no way out.
    final LocationResult result = await _location.currentLocation().timeout(
      kLocationDeadline,
      onTimeout: () => const LocationTimedOut(),
    );

    if (_disposed) return null;

    if (result is! LocationFix) {
      state = CurrentLocationBlocked(result);
      return null;
    }

    final DeviceLocation fix = result.location;

    PlaceDetails? named;
    try {
      named = await _places.reverseGeocode(
        latitude: fix.latitude,
        longitude: fix.longitude,
      );
    } on ApiException {
      // The name was a nicety. Losing it costs a line of text; refusing the
      // whole origin over it would cost the customer their journey.
      named = null;
    }

    if (_disposed) return null;

    final TripLocation location = TripLocation.fromCurrentLocation(
      latitude: fix.latitude,
      longitude: fix.longitude,
      fallbackLabel: fallbackLabel,
      named: named,
    );

    state = CurrentLocationReady(location, isCoarse: fix.isCoarse);

    return location;
  }

  /// Sends the customer to the OS settings page. Only offered for a permanent
  /// denial, where nothing in the app can produce another prompt.
  Future<bool> openSettings() => _location.openPermissionSettings();

  void reset() => state = const CurrentLocationIdle();
}

final currentLocationControllerProvider =
    NotifierProvider.autoDispose<
      CurrentLocationController,
      CurrentLocationStatus
    >(CurrentLocationController.new);
