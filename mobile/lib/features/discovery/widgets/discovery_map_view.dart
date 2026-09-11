import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../core/config/maps_config.dart';
import '../../../core/geo/polyline_codec.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovered_restaurant.dart';
import '../../../domain/models/trip.dart';
import '../../../domain/models/trip_route.dart';

/// Lets the screen re-frame the map without knowing what a map is.
abstract interface class DiscoveryMapRecentre {
  /// Back to the whole route, whatever the customer has selected.
  void recentreOnRoute();
}

/// The route, its two ends, and the stops found along it.
///
/// The route stays drawn at all times, including while a restaurant is selected.
/// A discovery map that loses the route the moment somebody taps a marker has
/// stopped answering the question it exists for — *where is this, relative to my
/// journey* — and become a generic pin on a generic map.
class DiscoveryMapView extends StatefulWidget {
  const DiscoveryMapView({
    required this.trip,
    required this.route,
    required this.restaurants,
    required this.selectedRestaurantId,
    this.onRestaurantTapped,
    super.key,
  });

  final Trip trip;

  /// The selected route from Module 06, so its real geometry is drawn rather
  /// than a line between the endpoints.
  final TripRoute? route;

  final List<DiscoveredRestaurant> restaurants;
  final String? selectedRestaurantId;
  final ValueChanged<String>? onRestaurantTapped;

  @override
  State<DiscoveryMapView> createState() => _DiscoveryMapViewState();
}

class _DiscoveryMapViewState extends State<DiscoveryMapView>
    implements DiscoveryMapRecentre {
  gmaps.GoogleMapController? _controller;

  /// One framing per route, not one per rebuild. Re-framing whenever the widget
  /// rebuilds would take the map away from a customer the moment they panned.
  String? _framedForRouteId;

  @override
  void didUpdateWidget(DiscoveryMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A newly selected restaurant moves the camera to it; deselecting returns
    // to the whole route.
    if (widget.selectedRestaurantId != oldWidget.selectedRestaurantId) {
      widget.selectedRestaurantId == null
          ? _frameRoute(force: true)
          : _frameSelected();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void recentreOnRoute() => _frameRoute(force: true);

  /// Fits the whole route, with room for the card sheet below.
  Future<void> _frameRoute({bool force = false}) async {
    final gmaps.GoogleMapController? controller = _controller;
    final TripRoute? route = widget.route;

    if (controller == null || route == null) return;
    if (!force && _framedForRouteId == route.id) return;

    _framedForRouteId = route.id;

    final RouteBounds? bounds = route.bounds;
    if (bounds == null) return;

    await controller.animateCamera(
      gmaps.CameraUpdate.newLatLngBounds(
        gmaps.LatLngBounds(
          southwest: gmaps.LatLng(bounds.south, bounds.west),
          northeast: gmaps.LatLng(bounds.north, bounds.east),
        ),
        72,
      ),
    );
  }

  /// Moves to a chosen restaurant, without losing the route.
  ///
  /// Zoom 12 rather than as close as the map will go: the useful thing to see is
  /// the stop *and* the road it is beside, not the roof of the building.
  Future<void> _frameSelected() async {
    final gmaps.GoogleMapController? controller = _controller;
    if (controller == null) return;

    for (final DiscoveredRestaurant r in widget.restaurants) {
      if (r.id != widget.selectedRestaurantId) continue;

      await controller.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(
          gmaps.LatLng(r.position.latitude, r.position.longitude),
          12,
        ),
      );

      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MapsConfig.canRenderMap) {
      return DiscoveryMapUnavailableView(
        trip: widget.trip,
        count: widget.restaurants.length,
      );
    }

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: gmaps.LatLng(
          widget.trip.origin.latitude,
          widget.trip.origin.longitude,
        ),
        zoom: 9,
      ),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: _markers(context),
      polylines: _polylines(context),
      onMapCreated: (gmaps.GoogleMapController controller) {
        _controller = controller;
        _frameRoute();
      },
    );
  }

  /// Both ends of the journey, and one marker per discovered restaurant.
  ///
  /// **Only** the restaurants in the current result set. A map that also showed
  /// nearby restaurants which failed the corridor or detour rules would be
  /// offering stops the server has already decided are not on this route.
  Set<gmaps.Marker> _markers(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final Set<gmaps.Marker> markers = <gmaps.Marker>{
      gmaps.Marker(
        markerId: const gmaps.MarkerId('origin'),
        position: gmaps.LatLng(
          widget.trip.origin.latitude,
          widget.trip.origin.longitude,
        ),
        infoWindow: gmaps.InfoWindow(
          title: strings.routeOriginMarker,
          snippet: widget.trip.origin.shortName,
        ),
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
          gmaps.BitmapDescriptor.hueGreen,
        ),
        // Behind the restaurants: the ends are context, the stops are the
        // subject.
        zIndexInt: 1,
      ),
      gmaps.Marker(
        markerId: const gmaps.MarkerId('destination'),
        position: gmaps.LatLng(
          widget.trip.destination.latitude,
          widget.trip.destination.longitude,
        ),
        infoWindow: gmaps.InfoWindow(
          title: strings.routeDestinationMarker,
          snippet: widget.trip.destination.shortName,
        ),
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
          gmaps.BitmapDescriptor.hueOrange,
        ),
        zIndexInt: 1,
      ),
    };

    for (final DiscoveredRestaurant restaurant in widget.restaurants) {
      final bool isSelected = restaurant.id == widget.selectedRestaurantId;

      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('restaurant:${restaurant.id}'),
          position: gmaps.LatLng(
            restaurant.position.latitude,
            restaurant.position.longitude,
          ),
          infoWindow: gmaps.InfoWindow(
            title: restaurant.displayName,
            snippet: restaurant.cuisines.isEmpty
                ? null
                : restaurant.cuisines.join(', '),
          ),
          // Hue *and* z-order, so the selected marker is distinguishable
          // without relying on colour perception, and is never hidden under a
          // neighbour on a crowded stretch of road.
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            isSelected
                ? gmaps.BitmapDescriptor.hueRed
                : gmaps.BitmapDescriptor.hueAzure,
          ),
          zIndexInt: isSelected ? 3 : 2,
          onTap: widget.onRestaurantTapped == null
              ? null
              : () => widget.onRestaurantTapped!(restaurant.id),
        ),
      );
    }

    return markers;
  }

  /// The route, always. Never removed while a restaurant is selected.
  Set<gmaps.Polyline> _polylines(BuildContext context) {
    final TripRoute? route = widget.route;
    if (route == null) return const <gmaps.Polyline>{};

    final List<GeoPoint> points = route.points();
    if (points.length < 2) return const <gmaps.Polyline>{};

    return <gmaps.Polyline>{
      gmaps.Polyline(
        polylineId: gmaps.PolylineId(route.id),
        points: points
            .map((GeoPoint p) => gmaps.LatLng(p.latitude, p.longitude))
            .toList(growable: false),
        color: Theme.of(context).colorScheme.primary,
        width: 6,
        zIndex: 1,
      ),
    };
  }
}

/// What stands in for the map when there cannot be one.
///
/// Not an error, and not empty. It says how many stops were found and points at
/// the list, which holds every fact the map would have conveyed except the
/// picture.
class DiscoveryMapUnavailableView extends StatelessWidget {
  const DiscoveryMapUnavailableView({
    required this.trip,
    required this.count,
    super.key,
  });

  final Trip trip;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Semantics(
      container: true,
      label:
          '${strings.routeMapUnavailableTitle}. '
          '${strings.discoveryResultCount(count)}.',
      child: Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        // Scrolls rather than overflows: this sits in the space a map would
        // occupy, which on a short phone is not much.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FotgSpacing.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.map_outlined,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: FotgSpacing.x2),
              Text(
                strings.routeMapUnavailableTitle,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FotgSpacing.x1),
              Text(
                strings.discoveryResultCount(count),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FotgSpacing.x2),
              Text(
                '${trip.origin.shortName}  →  ${trip.destination.shortName}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
