import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/core/location/location_service.dart';
import 'package:foodonthego/features/trips/trip_planner_screen.dart';

import 'support/harness.dart';

/// The location permission matrix, on the screen rather than in the abstract.
///
/// Every branch is here because each one needs different words and a different
/// button, and because a customer who is told they refused permission when they
/// did not will go to a settings screen where everything already looks right.
///
/// The other half of this file is about what is *not* asked: nothing requests
/// location until the customer taps the row that needs it.
void main() {
  Future<void> openPlanner(
    WidgetTester tester, {
    required FakeLocationService location,
    FakePlaceRepository? places,
    FakeTripRepository? trips,
  }) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        location: location,
        places: places,
        trips: trips,
        initialLocation: '/trips/plan',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TripPlannerScreen), findsOneWidget);
  }

  Future<void> tapCurrentLocation(WidgetTester tester) async {
    await tester.tap(find.text('Setting off from'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
  }

  group('permission is asked for contextually', () {
    testWidgets('nothing asks the device at startup', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService();

      usePhoneSurface(tester);
      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          location: location,
        ),
      );
      await tester.pumpAndSettle();

      // Not on launch, not on the home screen, not as the price of admission.
      // An app that asks before the customer has any reason to say yes is an
      // app most people say no to.
      expect(location.calls, 0);
    });

    testWidgets('nothing asks the device on opening the planner', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService();
      await openPlanner(tester, location: location);

      expect(location.calls, 0);
    });

    testWidgets('nothing asks the device on opening the picker', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService();
      await openPlanner(tester, location: location);

      await tester.tap(find.text('Setting off from'));
      await tester.pumpAndSettle();

      // The row is offered. It has not been acted on.
      expect(find.text('Use my current location'), findsOneWidget);
      expect(location.calls, 0);
    });

    testWidgets('the tap is what asks', (WidgetTester tester) async {
      final FakeLocationService location = FakeLocationService();
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(location.calls, 1);
    });
  });

  group('the six outcomes', () {
    testWidgets('granted: the fix becomes the origin', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService();
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      // Named by the reverse geocode the fake server performs. The coordinates
      // are the device's own throughout; nothing snapped them to a landmark.
      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.textContaining('Green Park'), findsWidgets);
    });

    testWidgets('denied: offers another go, and a way round it', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationPermissionDenied(),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(find.text('Location not shared'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The way out that does not depend on location at all. A permission
      // screen with no alternative is how an app traps somebody.
      expect(find.text('Search instead'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('denied permanently: sends them to settings, not to a prompt', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationPermissionDeniedForever(),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(find.text('Location is blocked'), findsOneWidget);
      // "Try again" here would be a button that cannot work: the system will
      // not show another prompt.
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(location.settingsOpened, 1);
    });

    testWidgets(
      'settings that will not open says where to go rather than nothing',
      (WidgetTester tester) async {
        final FakeLocationService location = FakeLocationService(
          result: const LocationPermissionDeniedForever(),
        )..settingsCanOpen = false;

        await openPlanner(tester, location: location);
        await tapCurrentLocation(tester);

        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();

        expect(find.textContaining("device's app permissions"), findsOneWidget);
      },
    );

    testWidgets('services disabled is never reported as a denial', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationServicesDisabled(),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      // The distinction that matters most in this matrix. The customer has
      // refused nothing, and an app-permission screen will not fix it.
      expect(find.text('Location is switched off'), findsOneWidget);
      expect(find.text('Location not shared'), findsNothing);
      expect(find.text('Location is blocked'), findsNothing);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('a timeout is an ordinary thing, not an error', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationTimedOut(),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(find.text('We could not find you'), findsOneWidget);
      expect(find.textContaining('common indoors'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a platform failure does not show the platform message', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationUnavailable(
          'PlatformException(FL_LOC_002, GoogleApiClient not connected)',
        ),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(find.text('Location unavailable'), findsOneWidget);
      // A platform message is written for whoever wrote the platform.
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('FL_LOC_002'), findsNothing);
    });
  });

  group('after a refusal', () {
    testWidgets('a retry that succeeds gets the origin', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationPermissionDenied(),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(find.text('Location not shared'), findsOneWidget);

      location.result = const LocationFix(
        DeviceLocation(latitude: 28.5590, longitude: 77.2070),
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(location.calls, 2);
      expect(find.text('Location not shared'), findsNothing);
    });

    testWidgets('searching is always reachable from a refusal', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationServicesDisabled(),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      await tester.tap(find.text('Search instead'));
      await tester.pumpAndSettle();

      // The field has focus, so the keyboard is already up and the next
      // keystroke searches.
      final TextField field = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(field.focusNode?.hasFocus, isTrue);
    });
  });

  group('an approximate fix', () {
    testWidgets('is used, and the customer is told it is approximate', (
      WidgetTester tester,
    ) async {
      final FakeLocationService location = FakeLocationService(
        result: const LocationFix(
          DeviceLocation(
            latitude: 28.5590,
            longitude: 77.2070,
            // A cell-tower fix. Renders identically to a 5 m GPS fix unless
            // something says otherwise.
            accuracyMetres: 2400,
          ),
        ),
      );
      await openPlanner(tester, location: location);
      await tapCurrentLocation(tester);

      expect(find.textContaining('approximate'), findsOneWidget);
    });
  });
}
