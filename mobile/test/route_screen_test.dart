import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/maps_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/features/routes/route_screen.dart';
import 'package:foodonthego/features/routes/widgets/route_map_view.dart';

import 'support/harness.dart';

/// The route screen, in every state it can be in.
///
/// The map itself cannot render in a test binding — there is no platform view —
/// and that is not a gap being worked around: a map that will not draw is a
/// state this screen has to handle anyway, and it is the state this environment
/// exercises. Everything a customer needs from a route comes from the route
/// data, and these tests hold the screen to that.
void main() {
  Future<FakeRouteRepository> openRoute(
    WidgetTester tester, {
    FakeRouteRepository? routes,
    Size size = const Size(390, 844),
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeRouteRepository repository = routes ?? FakeRouteRepository();

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        routes: repository,
        initialLocation: '/trips/trip-1/route',
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  /// Scrolls the summary sheet until [finder] is on screen.
  ///
  /// The alternatives sit below the fold in a lazy list, so a finder that has
  /// not been scrolled to reports zero matches whether or not the widget exists.
  /// The sheet is the last scrollable on the screen; the first is the map area.
  Future<void> scrollSheetTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  group('a calculated route', () {
    testWidgets('shows the real distance and travel time', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      expect(find.byType(RouteScreen), findsOneWidget);
      // 17100 s traffic-aware, 278 000 m — the figures the server sent, in the
      // units a person reads.
      expect(find.text('4 hr 45 min'), findsWidgets);
      expect(find.text('278 km'), findsWidgets);
    });

    testWidgets('leads with the traffic-aware time and names the delay', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      // 17100 - 16200 = 900 s.
      expect(find.text('+15 min'), findsWidgets);
      expect(find.text('Current traffic'), findsWidgets);
    });

    testWidgets('says the traffic figure is not live', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      // Nothing is refreshing it, so nothing implies it is current.
      expect(find.textContaining('Calculated'), findsWidgets);
      expect(find.textContaining('Traffic as it was'), findsWidgets);
    });

    testWidgets('calls this a travel time, not a pickup time', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      // The distinction the whole product turns on: how long the driving takes
      // is not when somebody reaches a restaurant.
      expect(
        find.textContaining('Driving time from the route'),
        findsOneWidget,
      );
    });

    testWidgets('shows both ends of the journey', (WidgetTester tester) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      expect(find.textContaining('Hauz Khas'), findsWidgets);
      expect(find.textContaining('Jaipur'), findsWidgets);
    });

    testWidgets('offers a recentre control where there is a map', (
      WidgetTester tester,
    ) async {
      MapsConfig.debugCanRenderMap = true;
      addTearDown(() => MapsConfig.debugCanRenderMap = null);

      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      expect(find.byTooltip('Fit the route back into view'), findsOneWidget);
    });

    testWidgets('offers no recentre control without a map to recentre', (
      WidgetTester tester,
    ) async {
      // This build carries no Maps key, so the screen is in its map-unavailable
      // state. The recentre button would have nothing to act on, and a control
      // that does nothing when tapped reads as a broken app.
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      expect(find.byType(MapUnavailableView), findsOneWidget);
      expect(find.byTooltip('Fit the route back into view'), findsNothing);
    });
  });

  group('the map', () {
    testWidgets('falls back to a summary when it cannot render', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      // No Maps key and no platform view here — the documented map-unavailable
      // state, which loses nothing a customer needs.
      expect(find.byType(MapUnavailableView), findsOneWidget);
      expect(find.text('Map unavailable'), findsOneWidget);
      // The journey and its figures are still on screen.
      expect(find.text('278 km'), findsWidgets);
    });

    testWidgets('the fallback names the journey for a screen reader', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      expect(
        find.bySemanticsLabel(RegExp('Map unavailable.*Hauz Khas')),
        findsOneWidget,
      );
    });
  });

  group('alternatives', () {
    testWidgets('a single route offers no choice', (WidgetTester tester) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      // A list headed "Alternative routes" with one entry is a control that
      // does nothing.
      expect(find.text('Alternative routes'), findsNothing);
    });

    testWidgets('several routes are listed with their own figures', (
      WidgetTester tester,
    ) async {
      await openRoute(
        tester,
        routes: FakeRouteRepository(alternatives: 3, calculated: true),
      );

      expect(find.text('Alternative routes'), findsOneWidget);

      await scrollSheetTo(tester, find.text('Recommended'));
      expect(find.text('Recommended'), findsWidgets);
      expect(find.text('Alternative'), findsWidgets);

      await scrollSheetTo(tester, find.text('265 km'));
      expect(find.text('265 km'), findsWidgets);
    });

    testWidgets('an alternative can be chosen, and the server decides', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = await openRoute(
        tester,
        routes: FakeRouteRepository(alternatives: 3, calculated: true),
      );

      await scrollSheetTo(tester, find.text('265 km'));
      await tester.tap(find.text('265 km'));
      await tester.pumpAndSettle();

      expect(routes.selectCalls, 1);
      // The card the customer picked now reads as selected.
      expect(find.text('Selected'), findsOneWidget);
    });

    testWidgets('a refused selection does not linger on screen', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = await openRoute(
        tester,
        routes: FakeRouteRepository(alternatives: 2, calculated: true),
      );

      routes.nextSelectError = const ApiException(
        code: ApiErrorCode.routeStale,
        message: 'stale',
        status: 409,
      );

      await scrollSheetTo(tester, find.text('265 km'));
      await tester.tap(find.text('265 km'));
      await tester.pumpAndSettle();

      // Nothing was applied optimistically, so the original selection stands.
      expect(find.text('278 km'), findsWidgets);
    });

    testWidgets('choosing is not only possible on the map', (
      WidgetTester tester,
    ) async {
      await openRoute(
        tester,
        routes: FakeRouteRepository(alternatives: 2, calculated: true),
      );

      await scrollSheetTo(tester, find.text('265 km'));

      // A two-pixel polyline on a moving map is not a control anybody can rely
      // on — least of all with a screen reader.
      expect(
        find.bySemanticsLabel(RegExp('Alternative.*265 km')),
        findsOneWidget,
      );
    });
  });

  group('nothing to show', () {
    testWidgets('a journey with no route offers to work one out', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..nextCalculateError = const ApiException(
          code: ApiErrorCode.routeProviderUnavailable,
          message: 'down',
          status: 503,
        );

      await openRoute(tester, routes: routes);

      expect(find.text("We couldn't work out your route"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('no driving route is not offered a retry', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..nextCalculateError = const ApiException(
          code: ApiErrorCode.routeNoRouteFound,
          message: 'no route',
          status: 422,
        );

      await openRoute(tester, routes: routes);

      expect(find.text("We couldn't find a driving route"), findsOneWidget);
      // Retrying spends a request to be told the same thing.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a timeout says so, and offers another go', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..nextCalculateError = const ApiException(
          code: ApiErrorCode.routeTimeout,
          message: 'slow',
          status: 504,
        );

      await openRoute(tester, routes: routes);

      expect(find.text('That took too long'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a rate limit asks the customer to wait', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..nextCalculateError = const ApiException(
          code: ApiErrorCode.routeProviderRateLimited,
          message: 'busy',
          status: 429,
        );

      await openRoute(tester, routes: routes);

      expect(find.text('Route planning is busy'), findsOneWidget);
      // Nothing about our quota or our billing.
      expect(find.textContaining('quota'), findsNothing);
    });

    testWidgets('being offline with nothing stored says so', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..nextReadError = const ApiException(
          code: ApiErrorCode.network,
          message: 'offline',
          status: 0,
        );

      await openRoute(tester, routes: routes);

      expect(find.text("You're offline"), findsOneWidget);
      // No straight line drawn to fill the space.
      expect(find.byType(MapUnavailableView), findsNothing);
    });

    testWidgets('the journey stays on screen whatever went wrong', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..nextCalculateError = const ApiException(
          code: ApiErrorCode.routeProviderUnavailable,
          message: 'down',
          status: 503,
        );

      await openRoute(tester, routes: routes);

      // Losing the journey as well would be two failures.
      expect(find.textContaining('Hauz Khas'), findsWidgets);
    });
  });

  group('what the screen admits to', () {
    testWidgets('a development route is labelled as not being a real one', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = FakeRouteRepository()
        ..provider = 'development';

      await openRoute(tester, routes: routes);

      expect(
        find.textContaining('this is not a real road route'),
        findsOneWidget,
      );
    });

    testWidgets('a real provider carries no such label', (
      WidgetTester tester,
    ) async {
      await openRoute(tester, routes: FakeRouteRepository(calculated: true));

      expect(find.textContaining('not a real road route'), findsNothing);
    });

    testWidgets('an offline cached route is labelled offline', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = await openRoute(
        tester,
        routes: FakeRouteRepository(calculated: true),
      );

      routes.nextCalculateError = const ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
        status: 0,
      );

      await scrollSheetTo(tester, find.text('Calculate again'));
      await tester.tap(find.text('Calculate again'));
      await tester.pumpAndSettle();

      // The route is still there, and nothing implies its traffic figure is
      // current.
      expect(
        find.textContaining('showing your last calculated route'),
        findsOneWidget,
      );
      expect(find.text('278 km'), findsWidgets);
    });
  });

  group('cost', () {
    testWidgets('opening the screen does not calculate an existing route', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = await openRoute(
        tester,
        routes: FakeRouteRepository(calculated: true),
      );

      expect(routes.readCalls, 1);
      expect(routes.calculateCalls, 0);
    });

    testWidgets('rebuilding the screen does not calculate again', (
      WidgetTester tester,
    ) async {
      final FakeRouteRepository routes = await openRoute(tester);

      expect(routes.calculateCalls, 1);

      // Several rebuilds — a keyboard, a theme change, a parent's state.
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(routes.calculateCalls, 1);
    });
  });

  group('layout', () {
    testWidgets('fits the smallest supported screen', (
      WidgetTester tester,
    ) async {
      await openRoute(
        tester,
        routes: FakeRouteRepository(alternatives: 3, calculated: true),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('278 km'), findsWidgets);
    });

    testWidgets('a notice never covers the map-unavailable text', (
      WidgetTester tester,
    ) async {
      // A banner over map tiles hides nothing that matters. A banner over the
      // map-unavailable state hides the only thing on it — on a 320-wide phone
      // the development notice landed on top of the two place names.
      await openRoute(
        tester,
        routes: FakeRouteRepository()..provider = 'development',
        size: const Size(320, 568),
      );

      final Rect fallback = tester.getRect(find.byType(MapUnavailableView));
      final Rect notice = tester.getRect(
        find.textContaining('this is not a real road route'),
      );

      expect(fallback.overlaps(notice), isFalse);
    });

    testWidgets('survives long place names', (WidgetTester tester) async {
      await openRoute(
        tester,
        routes: FakeRouteRepository(
          trip: sampleTrip(
            originName:
                'Indira Gandhi International Airport, Terminal 3, New Delhi',
            destinationName:
                'Jaipur International Airport, Sanganer, Jaipur, Rajasthan',
          ),
          calculated: true,
        ),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('survives large text', (WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(360, 740));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: wrapApp(
            repository: StubHomeRepository.value(
              const HomeDashboard(
                customer: CustomerSummary(fullName: 'Rahul Sharma'),
              ),
            ),
            routes: FakeRouteRepository(alternatives: 2, calculated: true),
            initialLocation: '/trips/trip-1/route',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The route summary is in a scrolling sheet precisely so 1.6x text pushes
      // rather than overflows.
      expect(tester.takeException(), isNull);
    });
  });
}
