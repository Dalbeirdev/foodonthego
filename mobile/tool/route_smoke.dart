// The Module 06 end-to-end run: this app's own network layer against a running
// Laravel backend, a real routing provider, and a real MySQL database. No
// mocks, no fakes, no stubs.
//
// It walks the module's own example — Rahul opens an existing Delhi → Jaipur
// trip, calculates a route, reads back what was stored, selects an alternative
// where one exists, restarts (a fresh client with the same session), and finds
// the same route selected — then Ananya's routes are attacked from Rahul's
// session every way the API allows.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/route_smoke.dart
//
// WHAT THIS RUN CAN AND CANNOT ESTABLISH
//
// Whether the numbers below are *real road figures* depends entirely on which
// provider the backend is configured with. Against `ROUTE_PROVIDER=google` with
// a key, they are Google's. Against `ROUTE_PROVIDER=development` — which is what
// an environment with no key falls back to — they are a straight line and an
// assumed speed, and the run says so in its output rather than letting a reader
// assume otherwise. The plumbing is identical either way, which is the point of
// running it at all.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/geo/polyline_codec.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/models/trip_route.dart';
import 'package:foodonthego/domain/repositories/route_repository.dart';

import 'support/smoke_support.dart';

/// Numbers from the Indian range reserved for testing and documentation.
const String _rahulPhone = '9999900601';
const String _ananyaPhone = '9999900602';

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 06 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  final Session rahul = await signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await signIn('Ananya', 'Mehta', _ananyaPhone);

  await discardEverything(rahul);
  await discardEverything(ananya);
  await clearAddresses(rahul);
  await clearAddresses(ananya);

  // --- 1. a Module 05 trip, Delhi → Jaipur --------------------------------
  final Trip trip = await _delhiToJaipur(rahul);

  check('Module 05 produced a trip with usable endpoints', () {
    expectValue(trip.routeStatus, RouteStatus.notCalculated);
    expectValue(trip.origin.latitude != 0, true);
    expectValue(trip.destination.latitude != 0, true);
    expectValue(trip.hasRoute, false);
  });

  await checkAsync('a trip with no route reports none', () async {
    final TripRoutes before = await rahul.routes.routes(trip.id);
    expectValue(before.hasRoutes, false);
    expectValue(before.trip.routeStatus, RouteStatus.notCalculated);
  });

  // --- 2. the route itself -------------------------------------------------
  final TripRoutes calculated = await rahul.routes.calculate(trip.id);

  check('a route is calculated and the trip becomes READY', () {
    expectValue(calculated.trip.routeStatus, RouteStatus.ready);
    expectValue(calculated.hasRoutes, true);
  });

  final TripRoute primary = calculated.selected!;

  check('the route carries a real distance and a real duration', () {
    expectValue(primary.distanceMeters > 0, true);
    expectValue(primary.durationSeconds > 0, true);
  });

  check('the geometry decodes and runs between the two places', () {
    final List<GeoPoint> points = primary.points();

    expectValue(points.length >= 2, true);

    // The check that catches a mismatched or cached response: geometry that is
    // internally perfect and describes somebody else's journey.
    final double fromOrigin = PolylineCodec.metresBetween(
      points.first,
      GeoPoint(trip.origin.latitude, trip.origin.longitude),
    );
    final double toDestination = PolylineCodec.metresBetween(
      points.last,
      GeoPoint(trip.destination.latitude, trip.destination.longitude),
    );

    expectValue(fromOrigin < 5000, true);
    expectValue(toDestination < 5000, true);
  });

  check('the route carries the bounds a camera and a corridor need', () {
    expectValue(primary.bounds != null, true);
    expectValue(primary.bounds!.north >= primary.bounds!.south, true);
  });

  check('one route is selected, and exactly one', () {
    expectValue(
      calculated.routes.where((TripRoute r) => r.isSelected).length,
      1,
    );
    expectValue(primary.isRecommended, true);
  });

  // What the configured provider actually returned. Recorded rather than
  // asserted: this run does not decide what a route between two cities is.
  stdout.writeln('');
  stdout.writeln('  ── what the configured provider returned ──');
  stdout.writeln('     provider          : ${primary.provider}');
  stdout.writeln('     real provider     : ${primary.isFromRealProvider}');
  stdout.writeln('     routes returned   : ${calculated.routes.length}');
  stdout.writeln('     distance (metres) : ${primary.distanceMeters}');
  stdout.writeln('     duration (seconds): ${primary.durationSeconds}');
  stdout.writeln(
    '     traffic (seconds) : ${primary.trafficDurationSeconds ?? "not supplied"}',
  );
  stdout.writeln('     summary           : ${primary.summary ?? "none"}');
  stdout.writeln('     polyline points   : ${primary.points().length}');
  stdout.writeln('');

  // --- 3. cost control -----------------------------------------------------
  await checkAsync('reading routes does not recalculate', () async {
    final DateTime? before = primary.calculatedAt;
    final TripRoutes again = await rahul.routes.routes(trip.id);

    // Same calculation, not a new one. A read that spends money is a read that
    // spends money on every screen open.
    expectValue(again.selected!.calculatedAt, before);
  });

  await checkAsync(
    'an unforced calculation inside the window is free',
    () async {
      final DateTime? before = primary.calculatedAt;
      final TripRoutes again = await rahul.routes.calculate(trip.id);

      expectValue(again.selected!.calculatedAt, before);
    },
  );

  await checkAsync('repeated calculation leaves one route set', () async {
    for (int i = 0; i < 5; i++) {
      await rahul.routes.calculate(trip.id);
    }

    final TripRoutes after = await rahul.routes.routes(trip.id);

    expectValue(after.routes.length, calculated.routes.length);
    expectValue(after.routes.where((TripRoute r) => r.isSelected).length, 1);
  });

  // --- 4. alternatives -----------------------------------------------------
  if (calculated.routes.length > 1) {
    final TripRoute alternative = calculated.routes[1];

    await checkAsync('an alternative can be selected', () async {
      final TripRoutes after = await rahul.routes.select(
        trip.id,
        alternative.id,
      );

      expectValue(after.selected!.id, alternative.id);
      expectValue(after.routes.where((TripRoute r) => r.isSelected).length, 1);
    });

    await checkAsync('the selection survives a restart', () async {
      // A genuinely fresh client with the same stored session — what reopening
      // the app does.
      final Session reopened = Session(rahul.name, rahul.token);

      try {
        final TripRoutes after = await reopened.routes.routes(trip.id);

        expectValue(after.selected!.id, alternative.id);
      } finally {
        reopened.close();
      }
    });

    await checkAsync('switching back and forth leaves one selection', () async {
      for (final TripRoute route in <TripRoute>[
        calculated.routes[0],
        alternative,
        calculated.routes[0],
      ]) {
        await rahul.routes.select(trip.id, route.id);
      }

      final TripRoutes after = await rahul.routes.routes(trip.id);
      expectValue(after.routes.where((TripRoute r) => r.isSelected).length, 1);
      expectValue(after.selected!.id, calculated.routes[0].id);
    });
  } else {
    stdout.writeln(
      '  NOTE  Alternative-route runtime test = NOT APPLICABLE — the configured\n'
      '        provider returned a single route for this journey.',
    );
  }

  // --- 5. the trip payload -------------------------------------------------
  await checkAsync('the trip now carries its route summary', () async {
    final Trip reread = await rahul.trips.trip(trip.id);

    expectValue(reread.hasRoute, true);
    expectValue(reread.selectedRoute!.distanceMeters > 0, true);
  });

  await checkAsync('the summary carries no geometry', () async {
    final Map<String, dynamic> raw = await rahul.client.get(
      '/customer/trips/${trip.id}',
      authenticated: true,
    );

    // Ten journeys in a list must not be ten polylines.
    final String summary = jsonEncode(raw['selected_route']);
    expectValue(summary.contains('polyline'), false);
  });

  // --- 6. what a client may not send ---------------------------------------
  await checkAsync(
    'a client cannot dictate a distance or a duration',
    () async {
      await rahul.client.post(
        '/customer/trips/${trip.id}/route/calculate',
        authenticated: true,
        body: <String, dynamic>{
          'distance_meters': 1,
          'duration_seconds': 1,
          'traffic_duration_seconds': 1,
          'encoded_polyline': 'tamper',
          'is_selected': true,
          'route_status': 'READY',
          'provider': 'attacker',
        },
      );

      final TripRoutes after = await rahul.routes.routes(trip.id);

      expectValue(after.selected!.distanceMeters, primary.distanceMeters);
      expectValue(after.selected!.provider, primary.provider);
      expectValue(after.selected!.encodedPolyline == 'tamper', false);
    },
  );

  // --- 7. endpoint change invalidation -------------------------------------
  await checkAsync('changing an endpoint invalidates the route', () async {
    // Module 05 has no edit endpoint, so this is what a future one — or a
    // repair script, or an import — would do to the row.
    final Trip moved = await _tripToChandigarh(rahul);

    final TripRoutes before = await rahul.routes.calculate(moved.id);
    expectValue(before.hasRoutes, true);

    await _moveDestination(moved.id);

    final TripRoutes after = await rahul.routes.routes(moved.id);

    // The stale route is gone, and the trip is back to needing one. A route
    // that survived this would be real geometry for the wrong journey.
    expectValue(after.trip.routeStatus, RouteStatus.notCalculated);
    expectValue(after.hasRoutes, false);
    expectValue(after.trip.hasRoute, false);
  });

  // --- 8. Ananya's routes, attacked from Rahul's session -------------------
  final Trip hers = await _delhiToJaipur(ananya);
  await ananya.routes.calculate(hers.id);
  final TripRoutes herRoutes = await ananya.routes.routes(hers.id);

  await expectRefused(
    "Rahul cannot calculate a route for Ananya's trip",
    () => rahul.routes.calculate(hers.id),
    ApiErrorCode.tripNotFound,
  );

  await expectRefused(
    "Rahul cannot read Ananya's routes",
    () => rahul.routes.routes(hers.id),
    ApiErrorCode.tripNotFound,
  );

  await expectRefused(
    "Rahul cannot select a route on Ananya's trip",
    () => rahul.routes.select(hers.id, herRoutes.selected!.id),
    ApiErrorCode.tripNotFound,
  );

  await expectRefused(
    "Rahul cannot attach Ananya's route to his own trip",
    () => rahul.routes.select(trip.id, herRoutes.selected!.id),
    ApiErrorCode.routeNotFound,
  );

  await checkAsync("no refusal leaks a word about Ananya's route", () async {
    for (final Future<Object?> Function() attempt
        in <Future<Object?> Function()>[
          () => rahul.routes.routes(hers.id),
          () => rahul.routes.calculate(hers.id),
          () => rahul.routes.select(hers.id, herRoutes.selected!.id),
        ]) {
      try {
        await attempt();
        throw StateError('an attack on Ananya succeeded');
      } on ApiException catch (error) {
        final String body = '${error.message} ${error.details}';

        for (final String secret in <String>[
          '${herRoutes.selected!.distanceMeters}',
          herRoutes.selected!.encodedPolyline,
          herRoutes.selected!.id,
        ]) {
          if (body.contains(secret)) {
            throw 'a refusal mentioned "$secret"';
          }
        }
      }
    }
  });

  await checkAsync('her selection is untouched by any of it', () async {
    final TripRoutes after = await ananya.routes.routes(hers.id);

    expectValue(after.selected!.id, herRoutes.selected!.id);
  });

  // --- 9. authentication ---------------------------------------------------
  await checkAsync('an unauthenticated call reaches no routes', () async {
    final ApiClient anonymous = ApiClient();

    try {
      await ApiRouteRepository(anonymous).routes(trip.id);
      throw StateError('an unauthenticated read succeeded');
    } on ApiException catch (error) {
      expectValue(error.code, ApiErrorCode.unauthenticated);
    } finally {
      anonymous.close();
    }
  });

  rahul.close();
  ananya.close();

  stdout.writeln('');
  stdout.writeln('$passed passed, $failed failed');
  exit(failed == 0 ? 0 : 1);
}

/// Creates a Delhi → Jaipur trip through Module 05's own flow.
Future<Trip> _delhiToJaipur(Session session) async {
  final List<PlaceSuggestion> origin = await session.places.search('hauz khas');
  final List<PlaceSuggestion> destination = await session.places.search(
    'jaipur airport',
  );

  return session.trips.createTrip(
    TripDraft(
      origin: TripLocation.fromPlace(
        await session.places.details(origin.first.placeId),
      ),
      destination: TripLocation.fromPlace(
        await session.places.details(destination.first.placeId),
      ),
    ),
  );
}

Future<Trip> _tripToChandigarh(Session session) async {
  final List<PlaceSuggestion> origin = await session.places.search(
    'connaught place',
  );
  final List<PlaceSuggestion> destination = await session.places.search(
    'sector 17',
  );

  return session.trips.createTrip(
    TripDraft(
      origin: TripLocation.fromPlace(
        await session.places.details(origin.first.placeId),
      ),
      destination: TripLocation.fromPlace(
        await session.places.details(destination.first.placeId),
      ),
    ),
  );
}

/// Moves a trip's destination behind the API's back.
///
/// Module 05 offers no way to edit an endpoint, so the only honest way to
/// exercise the invalidation rule is to change the row the way a future edit
/// endpoint, a data repair or an import would.
Future<void> _moveDestination(String tripUuid) async {
  final ProcessResult result = await Process.run('mysql', <String>[
    '-N',
    '-B',
    'foodonthego_local',
    '-e',
    "UPDATE trips SET destination_latitude = 19.0760, destination_longitude = 72.8777, "
        "destination_name = 'Mumbai' WHERE uuid = '$tripUuid';",
  ]);

  if (result.exitCode != 0) {
    throw StateError('could not move the destination: ${result.stderr}');
  }
}
