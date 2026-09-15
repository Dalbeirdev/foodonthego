import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../core/config/maps_config.dart';
import '../../../core/geo/polyline_codec.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/trip.dart';
import '../../../domain/models/trip_route.dart';

/// Lets the screen ask the map to re-frame without knowing what a map is.
///
/// An interface rather than a callback, so the screen holds a `GlobalKey` to
/// something it can name — and so the map-unavailable case simply does not
/// implement it and the button is not offered.
abstract interface class RouteMapRecentre {
  void recentre();
}

/// The map, or an honest statement that there is not one.
///
/// Two states of equal standing. A map that cannot draw is not a broken screen:
/// the customer still needs to see where they are going, how far it is and how
/// long it takes, and every one of those comes from the route data rather than
/// from the tiles. The summary sheet below carries on regardless.
///
/// The map is attempted only where a Maps key exists **and** the platform is one
/// this product ships to. The web harness has neither, by design.
class RouteMapView extends StatefulWidget {
  const RouteMapView({
    required this.trip,
    required this.routes,
    required this.selectedRouteId,
    this.onRouteTapped,
    super.key,
  });

  final Trip trip;
  final List<TripRoute> routes;
  final String? selectedRouteId;

  /// Tapping an alternative's line selects it. Never the only way to choose one
  /// — the cards below do the same job for anybody who cannot hit a two-pixel
  /// line on a moving map.
  final ValueChanged<String>? onRouteTapped;

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView>
    implements RouteMapRecentre {
  gmaps.GoogleMapController? _controller;

  /// Whether the camera has been framed for the current route set.
  ///
  /// A one-shot per route set. Re-framing on every rebuild would fight the
  /// customer for control of the map the moment they panned away.
  String? _framedForRouteId;

  @override
  void didUpdateWidget(RouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedRouteId != oldWidget.selectedRouteId) {
      _frame();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  TripRoute? get _selected {
    for (final TripRoute route in widget.routes) {
      if (route.id == widget.selectedRouteId) return route;
    }
    return widget.routes.isEmpty ? null : widget.routes.first;
  }

  /// Fits the camera to the selected route.
  ///
  /// Padding rather than a hard-coded zoom: a 12 km hop and a 280 km drive need
  /// wildly different zooms, and the only thing they have in common is that the
  /// whole line should be on screen with room for the sheet below.
  Future<void> _frame({bool force = false}) async {
    final gmaps.GoogleMapController? controller = _controller;
    final TripRoute? route = _selected;

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
        // Clears the app bar above and the summary sheet below, and keeps the
        // ends of the route off the very edge of the glass.
        72,
      ),
    );
  }

  /// Re-frames on demand. The screen's "Recentre" calls this.
  @override
  void recentre() => _frame(force: true);

  @override
  Widget build(BuildContext context) {
    if (!MapsConfig.canRenderMap) {
      return MapUnavailableView(trip: widget.trip);
    }

    final TripRoute? selected = _selected;

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: gmaps.LatLng(
          widget.trip.origin.latitude,
          widget.trip.origin.longitude,
        ),
        zoom: 9,
      ),
      // The customer's own position is Module 05's business, asked for once and
      // never watched. A route screen has no reason to turn it on.
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      // Ours is in the summary sheet, where it is reachable with a thumb.
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: _markers(context),
      polylines: _polylines(context, selected),
      onMapCreated: (gmaps.GoogleMapController controller) {
        _controller = controller;
        _frame();
      },
    );
  }

  Set<gmaps.Marker> _markers(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return <gmaps.Marker>{
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
      ),
    };
  }

  /// The selected route in the brand colour and on top; the rest beneath it in
  /// grey.
  ///
  /// Width and z-order carry the distinction as well as colour, because two
  /// lines that differ only in hue are two lines somebody cannot tell apart.
  Set<gmaps.Polyline> _polylines(BuildContext context, TripRoute? selected) {
    final ThemeData theme = Theme.of(context);
    final Set<gmaps.Polyline> polylines = <gmaps.Polyline>{};

    for (final TripRoute route in widget.routes) {
      final List<GeoPoint> points = route.points();

      // A route whose geometry will not decode draws nothing rather than
      // taking the map down with it.
      if (points.length < 2) continue;

      final bool isSelected = route.id == selected?.id;

      polylines.add(
        gmaps.Polyline(
          polylineId: gmaps.PolylineId(route.id),
          points: points
              .map((GeoPoint p) => gmaps.LatLng(p.latitude, p.longitude))
              .toList(growable: false),
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: isSelected ? 6 : 4,
          zIndex: isSelected ? 2 : 1,
          consumeTapEvents: widget.onRouteTapped != null,
          onTap: widget.onRouteTapped == null
              ? null
              : () => widget.onRouteTapped!(route.id),
        ),
      );
    }

    return polylines;
  }
}

/// What stands in for the map when there cannot be one.
///
/// Deliberately not an error. It names the two ends and says the details are
/// below, because they are: nothing about the route depends on the tiles.
class MapUnavailableView extends StatelessWidget {
  const MapUnavailableView({required this.trip, super.key});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Semantics(
      container: true,
      label:
          '${strings.routeMapUnavailableTitle}. '
          '${trip.origin.shortName} to ${trip.destination.shortName}.',
      child: Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        // Scrolls rather than overflows. This sits in the space a map would
        // occupy, which on a 320x568 phone with a route summary beneath it is
        // about 180 logical pixels — less than this content's natural height,
        // and a `RenderFlex overflowed` stripe is not an acceptable answer to
        // "your map could not load".
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
                strings.routeMapUnavailableBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FotgSpacing.x3),
              // The journey itself, so the screen is still about a journey.
              Text(
                '${trip.origin.shortName}  →  ${trip.destination.shortName}',
                style: theme.textTheme.bodyLarge,
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
