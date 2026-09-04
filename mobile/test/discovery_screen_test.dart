import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/maps_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/features/discovery/widgets/discovery_map_view.dart';
import 'package:foodonthego/features/discovery/widgets/restaurant_preview_card.dart';
import 'package:foodonthego/shared/widgets/empty_state_view.dart';

import 'support/harness.dart';

/// The discovery screen, as a customer meets it.
void main() {
  Future<FakeDiscoveryRepository> openDiscovery(
    WidgetTester tester, {
    FakeDiscoveryRepository? discovery,
    Size size = const Size(390, 844),
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeDiscoveryRepository repository =
        discovery ?? FakeDiscoveryRepository();

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        routes: FakeRouteRepository(calculated: true),
        discovery: repository,
        initialLocation: '/trips/trip-1/route/restaurants',
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  group('a route with stops on it', () {
    testWidgets('lists the restaurants it found', (WidgetTester tester) async {
      await openDiscovery(tester);

      expect(find.text('Highway Spice Kitchen'), findsOneWidget);
      expect(find.byType(RestaurantPreviewCard), findsOneWidget);
    });

    testWidgets('leads with how far ahead and what the stop costs', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      // The two facts the decision turns on.
      expect(find.textContaining('68 km ahead'), findsOneWidget);
      expect(find.textContaining('4 min detour'), findsOneWidget);
    });

    testWidgets('says how far off the route it is, separately', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      // Proximity is a secondary signal and is never labelled as a detour.
      expect(find.textContaining('1.8 km off your route'), findsOneWidget);
    });

    testWidgets('counts the stops', (WidgetTester tester) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(id: 'a', name: 'First Stop'),
            sampleRestaurant(id: 'b', name: 'Second Stop'),
          ],
        ),
      );

      expect(find.text('2 stops on your route'), findsOneWidget);
    });

    testWidgets('shows cuisine and price, and no rating where there is none', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(find.textContaining('North Indian'), findsWidgets);
      expect(find.textContaining('₹₹'), findsOneWidget);
      // No reviews module: the card shows nothing where a rating would go
      // rather than a hopeful number.
      expect(find.textContaining('★'), findsNothing);
    });

    testWidgets('shows a rating when there really is one', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(rating: 4.5, reviewCount: 214),
          ],
        ),
      );

      expect(find.textContaining('4.5 ★'), findsOneWidget);
      expect(find.textContaining('214'), findsOneWidget);
    });

    testWidgets('shows the facilities the operator declared', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(find.textContaining('Parking'), findsWidgets);
    });
  });

  group('availability', () {
    testWidgets('an open restaurant says open', (WidgetTester tester) async {
      await openDiscovery(tester);

      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('a paused restaurant never says open', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(
              availability: RestaurantAvailability.notAcceptingOrders,
              isAcceptingOrders: false,
            ),
          ],
        ),
      );

      // Sending somebody forty kilometres for food nobody will cook is the
      // worst thing this screen could do.
      expect(find.text('Not accepting orders'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    });

    testWidgets('a closed restaurant is shown, and marked closed', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(availability: RestaurantAvailability.closed),
          ],
        ),
      );

      expect(find.text('Closed'), findsOneWidget);
      // Not hidden: "there is somewhere and it is shut" is a different and more
      // useful thing than "there is nothing here".
      expect(find.text('Highway Spice Kitchen'), findsOneWidget);
    });

    testWidgets('a closed-only result says so above the list', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(availability: RestaurantAvailability.closed),
          ],
        ),
      );

      expect(
        find.textContaining('none of them are taking orders'),
        findsOneWidget,
      );
    });
  });

  group('the detour', () {
    testWidgets('an unknown detour says so rather than showing a zero', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(
              detourDurationSeconds: null,
              detourDistanceMetres: null,
            ),
          ],
        ),
      );

      // A zero would be a claim that stopping is free.
      expect(find.text('Detour unknown'), findsOneWidget);
      expect(find.textContaining('0 min detour'), findsNothing);
    });

    testWidgets('a restaurant behind you is labelled, not hidden', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(
              distanceAheadMetres: 0,
              requiresBacktracking: true,
            ),
          ],
        ),
      );

      expect(find.text('Behind you'), findsOneWidget);
      expect(find.textContaining('0 m ahead'), findsNothing);
    });
  });

  group('map and list', () {
    testWidgets('opens on the list', (WidgetTester tester) async {
      await openDiscovery(tester);

      expect(find.byType(RestaurantPreviewCard), findsOneWidget);
      expect(find.byType(DiscoveryMapView), findsNothing);
    });

    testWidgets('switching to the map does not search again', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository discovery = await openDiscovery(tester);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      expect(find.byType(DiscoveryMapView), findsOneWidget);
      // Changing how somebody looks at results is not asking for new ones.
      expect(discovery.discoverCalls, 1);
    });

    testWidgets('switching back and forth keeps the results', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository discovery = await openDiscovery(tester);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();

      expect(find.text('Highway Spice Kitchen'), findsOneWidget);
      expect(discovery.discoverCalls, 1);
    });

    testWidgets('the map falls back to a summary when it cannot render', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      // No Maps key here, so the documented map-unavailable state — which still
      // names both ends and says how many stops were found.
      expect(find.byType(DiscoveryMapUnavailableView), findsOneWidget);
      expect(find.text('1 stop on your route'), findsWidgets);
    });

    testWidgets('tapping a card selects it', (WidgetTester tester) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(id: 'a', name: 'First Stop'),
            sampleRestaurant(id: 'b', name: 'Second Stop'),
          ],
        ),
      );

      await tester.tap(find.text('Second Stop'));
      await tester.pumpAndSettle();

      final RestaurantPreviewCard card = tester.widget(
        find.ancestor(
          of: find.text('Second Stop'),
          matching: find.byType(RestaurantPreviewCard),
        ),
      );

      expect(card.isSelected, isTrue);
    });

    testWidgets('a selection made in the list is the one the map shows', (
      WidgetTester tester,
    ) async {
      MapsConfig.debugCanRenderMap = true;
      addTearDown(() => MapsConfig.debugCanRenderMap = null);

      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(id: 'a', name: 'First Stop'),
            sampleRestaurant(id: 'b', name: 'Second Stop'),
          ],
        ),
      );

      await tester.tap(find.text('Second Stop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      // One field drives both, which is what keeps them from disagreeing.
      final DiscoveryMapView map = tester.widget(find.byType(DiscoveryMapView));
      expect(map.selectedRestaurantId, 'b');
    });
  });

  group('nothing to show', () {
    testWidgets('an empty route gets its own words, not an error', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[],
        ),
      );

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('No stops on this route yet'), findsOneWidget);
      // And it says how wide a corridor was searched, rather than leaving the
      // customer to guess what "on this route" meant.
      expect(find.textContaining('5.0 km'), findsOneWidget);
    });

    testWidgets('a route that is not ready sends them back to the route', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository()
          ..nextError = const ApiException(
            code: ApiErrorCode.routeNotReady,
            message: 'x',
            status: 409,
          ),
      );

      expect(find.text('Work out your route first'), findsOneWidget);
      expect(find.text('Go to route'), findsOneWidget);
      // Not a retry: asking again would be told the same thing.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a rate limit asks them to wait', (WidgetTester tester) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository()
          ..nextError = const ApiException(
            code: ApiErrorCode.discoveryRateLimited,
            message: 'x',
            status: 429,
          ),
      );

      expect(find.text('Just a moment'), findsOneWidget);
    });

    testWidgets('a server failure offers a retry', (WidgetTester tester) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository()
          ..nextError = const ApiException(
            code: ApiErrorCode.discoveryFailed,
            message: 'x',
            status: 500,
          ),
      );

      expect(find.textContaining("couldn't load restaurants"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('being offline with nothing stored says so', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository()
          ..nextError = const ApiException(
            code: ApiErrorCode.network,
            message: 'x',
            status: 0,
          ),
      );

      expect(find.text("You're offline"), findsOneWidget);
    });

    testWidgets('no internal error text ever reaches the screen', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository()
          ..nextError = const ApiException(
            code: ApiErrorCode.discoveryFailed,
            message: 'SQLSTATE[42S02]: Base table or view not found',
            status: 500,
          ),
      );

      expect(find.textContaining('SQLSTATE'), findsNothing);
    });
  });

  group('what the screen admits to', () {
    testWidgets('a stand-in route is labelled as one', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(provider: 'development'),
      );

      expect(
        find.textContaining('found along a stand-in route'),
        findsOneWidget,
      );
    });

    testWidgets('a real provider carries no such label', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(find.textContaining('stand-in route'), findsNothing);
    });
  });

  group('cost', () {
    testWidgets('opening the screen searches exactly once', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository discovery = await openDiscovery(tester);

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(discovery.discoverCalls, 1);
    });

    testWidgets('a rebuild does not search again', (WidgetTester tester) async {
      final FakeDiscoveryRepository discovery = await openDiscovery(tester);

      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          routes: FakeRouteRepository(calculated: true),
          discovery: discovery,
          initialLocation: '/trips/trip-1/route/restaurants',
        ),
      );
      await tester.pumpAndSettle();

      expect(discovery.discoverCalls, 1);
    });
  });

  group('layout', () {
    testWidgets('fits the smallest supported screen', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(id: 'a'),
            sampleRestaurant(id: 'b', name: 'Second Stop'),
          ],
        ),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(RestaurantPreviewCard), findsWidgets);
      // The toggle is still there, as icons with accessible names.
      expect(find.byTooltip('Map'), findsOneWidget);
    });

    testWidgets('survives a very long restaurant name', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(
              name:
                  'Shree Rajasthan Highway Family Restaurant & '
                  'Vegetarian Food Court',
            ),
          ],
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
            routes: FakeRouteRepository(calculated: true),
            discovery: FakeDiscoveryRepository(),
            initialLocation: '/trips/trip-1/route/restaurants',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The facts a traveller needs are still reachable at 1.6x.
      expect(find.textContaining('68 km ahead'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('a card reads as one sentence', (WidgetTester tester) async {
      await openDiscovery(tester);

      expect(
        find.bySemanticsLabel(
          RegExp(
            'Highway Spice Kitchen.*North Indian.*Open.*68 km ahead.*4 min',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a card is activatable by assistive technology', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Highway Spice Kitchen')),
      );

      // The Module 05 lesson: a labelled row that cannot be activated announces
      // itself as a button and does nothing.
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    });

    testWidgets('a backtracking stop reads as "behind you", not "0 m ahead"', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(
              distanceAheadMetres: 0,
              requiresBacktracking: true,
            ),
          ],
        ),
      );

      // The visible chip and the spoken label are computed from one string, so
      // they cannot disagree. They did: a screen reader was told "0 m ahead"
      // about the very restaurant the screen labelled "Behind you".
      expect(find.bySemanticsLabel(RegExp('Behind you')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('0 m ahead')), findsNothing);
    });

    testWidgets('price level is announced as a word, not as symbols', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      // "₹₹" is a visual convention. A screen reader announces it as nothing
      // useful, and a font without the glyph draws two empty boxes.
      expect(find.bySemanticsLabel(RegExp('Moderate')), findsOneWidget);
    });

    testWidgets('how far off the route is announced too', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(
        find.bySemanticsLabel(RegExp('1.8 km off your route')),
        findsOneWidget,
      );
    });

    testWidgets('availability is words, not only a colour', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(
              availability: RestaurantAvailability.notAcceptingOrders,
            ),
          ],
        ),
      );

      expect(find.text('Not accepting orders'), findsOneWidget);
    });
  });
}
