import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/discovery_facets.dart';
import 'package:foodonthego/domain/models/discovery_query.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/features/discovery/widgets/discovery_filter_sheet.dart';
import 'package:foodonthego/shared/state/discovery_controller.dart';
import 'package:foodonthego/shared/widgets/empty_state_view.dart';

import 'support/harness.dart';

/// Searching and filtering, as a customer meets them.
void main() {
  const DiscoveryFacets facets = DiscoveryFacets(
    cuisines: <FilterOption>[
      FilterOption(slug: 'north_indian', label: 'North Indian', count: 3),
      FilterOption(slug: 'cafe', label: 'Cafe', count: 1),
    ],
    facilities: <FilterOption>[
      FilterOption(slug: 'parking', label: 'Parking', count: 3),
      FilterOption(slug: 'restroom', label: 'Restroom', count: 2),
    ],
    priceLevels: <PriceOption>[
      PriceOption(level: 1, count: 1),
      PriceOption(level: 2, count: 3),
    ],
    availability: <AvailabilityOption>[
      AvailabilityOption(
        value: AvailabilityFilter.openNow,
        label: 'Open now',
        count: 3,
      ),
      AvailabilityOption(
        value: AvailabilityFilter.acceptingOrders,
        label: 'Taking orders',
        count: 2,
      ),
    ],
    sorts: <SortOption>[
      SortOption(
        sort: DiscoverySort.recommended,
        label: 'Recommended',
        isAvailable: true,
      ),
      SortOption(
        sort: DiscoverySort.lowestDetour,
        label: 'Shortest detour',
        isAvailable: true,
      ),
      SortOption(
        sort: DiscoverySort.highestRated,
        label: 'Highest rated',
        isAvailable: false,
        unavailableReason: 'No restaurant on this route has a rating yet.',
      ),
    ],
    ratingAvailable: false,
    maxDetourSeconds: 900,
  );

  Future<FakeDiscoveryRepository> openDiscovery(
    WidgetTester tester, {
    FakeDiscoveryRepository? discovery,
    Size size = const Size(390, 844),
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeDiscoveryRepository repository =
        discovery ?? FakeDiscoveryRepository(facets: facets);

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

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    // Past the debounce, and then let the response land.
    await tester.pump(DiscoveryController.searchDebounce);
    await tester.pumpAndSettle();
  }

  group('the search field', () {
    testWidgets('is offered above the stops', (WidgetTester tester) async {
      await openDiscovery(tester);

      expect(find.text('Search restaurants or cuisines'), findsOneWidget);
    });

    testWidgets('sends what was typed, once', (WidgetTester tester) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await type(tester, 'spice');

      expect(repository.discoverCalls, 2);
      expect(repository.lastQuery!.search, 'spice');
    });

    testWidgets('a single letter is not sent at all', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await type(tester, 's');

      expect(repository.discoverCalls, 1);
    });

    testWidgets('offers a way to clear itself only when there is something '
        'to clear', (WidgetTester tester) async {
      await openDiscovery(tester);

      expect(find.byTooltip('Clear search'), findsNothing);

      await type(tester, 'spice');

      expect(find.byTooltip('Clear search'), findsOneWidget);
    });

    testWidgets('clearing drops the term', (WidgetTester tester) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await type(tester, 'spice');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(repository.lastQuery!.hasSearch, isFalse);
    });
  });

  group('the filter sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Filter these stops'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers only what this route actually has', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);
      await openSheet(tester);

      // From the server's facets. A cuisine no partner on this road serves is
      // a filter whose only outcome is an empty screen.
      expect(find.text('North Indian (3)'), findsOneWidget);
      expect(find.text('Cafe (1)'), findsOneWidget);
      expect(find.text('Chinese (0)'), findsNothing);
    });

    testWidgets('says which groups are any-of and which are all-of', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);
      await openSheet(tester);

      // A customer who assumes the wrong one is sent to a restaurant without
      // the facility they needed.
      expect(find.text('Any of these'), findsWidgets);
      expect(find.text('All of these'), findsOneWidget);
    });

    testWidgets('offers no rating control while nothing is rated', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);
      await openSheet(tester);

      // Worse than absent: a control that can only ever return nothing implies
      // the ratings exist and the restaurants fall short of them.
      expect(find.text('3.0+'), findsNothing);
      expect(find.text('4.0+'), findsNothing);
    });

    testWidgets('changes nothing until it is applied', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await openSheet(tester);
      await tester.tap(find.text('North Indian (3)'));
      await tester.pump();
      await tester.tap(find.text('Parking (3)'));
      await tester.pumpAndSettle();

      // Two taps, no requests: the sheet edits a draft.
      expect(repository.discoverCalls, 1);

      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(repository.discoverCalls, 2);
      expect(repository.lastQuery!.cuisines, <String>{'north_indian'});
      expect(repository.lastQuery!.facilities, <String>{'parking'});
    });

    testWidgets('dismissing it discards the draft', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await openSheet(tester);
      await tester.tap(find.text('Cafe (1)'));
      await tester.pump();

      Navigator.of(tester.element(find.text('Show results'))).pop();
      await tester.pumpAndSettle();

      expect(repository.discoverCalls, 1);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('a detour ceiling comes from the server, not this build', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);
      await openSheet(tester);

      await tester.scrollUntilVisible(
        find.text('Any detour'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(DiscoveryFilterSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Any detour'), findsOneWidget);
      // 900 seconds, as the facets declared.
      expect(find.text('Under 15 min'), findsOneWidget);
    });
  });

  group('the chips', () {
    Future<void> applyCuisines(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Filter these stops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('North Indian (3)'));
      await tester.pump();
      await tester.tap(find.text('Cafe (1)'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
    }

    testWidgets('show what is filtering the list', (WidgetTester tester) async {
      await openDiscovery(tester);
      await applyCuisines(tester);

      // A list of two restaurants with nothing on screen explaining why is a
      // list that looks like a road with two restaurants on it.
      expect(find.widgetWithText(InputChip, 'North Indian'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Cafe'), findsOneWidget);
    });

    testWidgets('use the label the customer chose, not the slug', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);
      await applyCuisines(tester);

      expect(find.text('north_indian'), findsNothing);
    });

    testWidgets('removing one leaves the rest of its group', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);
      await applyCuisines(tester);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Cafe'),
          matching: find.byTooltip('Remove this filter'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.lastQuery!.cuisines, <String>{'north_indian'});
      expect(find.widgetWithText(InputChip, 'North Indian'), findsOneWidget);
    });

    testWidgets('clear all removes every filter at once', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);
      await applyCuisines(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Clear all'));
      await tester.pumpAndSettle();

      expect(repository.lastQuery!.hasFilters, isFalse);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('the filter button carries a count', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);
      await applyCuisines(tester);

      expect(find.byTooltip('Filter these stops, 2 filters'), findsOneWidget);
    });
  });

  group('the sort sheet', () {
    Future<void> openSort(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Sorted by Recommended'));
      await tester.pumpAndSettle();
    }

    testWidgets('applies the order that was chosen', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await openSort(tester);
      await tester.tap(find.text('Shortest detour'));
      await tester.pumpAndSettle();

      expect(repository.lastQuery!.sort, DiscoverySort.lowestDetour);
    });

    testWidgets('shows an unavailable order with the reason it cannot be '
        'used', (WidgetTester tester) async {
      await openDiscovery(tester);
      await openSort(tester);

      // A greyed-out row with no explanation reads as a bug; a missing row
      // reads as a lost feature.
      expect(find.text('Highest rated'), findsOneWidget);
      expect(
        find.text('No restaurant on this route has a rating yet.'),
        findsOneWidget,
      );
    });

    testWidgets('an unavailable order cannot be picked', (
      WidgetTester tester,
    ) async {
      final FakeDiscoveryRepository repository = await openDiscovery(tester);

      await openSort(tester);
      await tester.tap(find.text('Highest rated'));
      await tester.pumpAndSettle();

      expect(repository.discoverCalls, 1);
    });

    testWidgets('the current order is named on screen', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(find.text('Sorted by Recommended'), findsOneWidget);
    });
  });

  group('the empty screens, told apart', () {
    FakeDiscoveryRepository refusing({required bool searching}) =>
        FakeDiscoveryRepository(
          facets: facets,
          responder: (DiscoveryQuery query) => sampleDiscovery(
            facets: facets,
            restaurants: query.isRefined
                ? const <DiscoveredRestaurant>[]
                : <DiscoveredRestaurant>[sampleRestaurant()],
            total: query.isRefined ? 0 : 1,
            eligibleTotal: 6,
            filteredEmpty: query.isRefined,
          ),
        );

    testWidgets('a search that matched nothing offers to clear the search', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester, discovery: refusing(searching: true));

      await type(tester, 'sushi');

      expect(find.text('Nothing matched your search'), findsOneWidget);
      expect(find.textContaining('"sushi"'), findsOneWidget);
      expect(
        find.widgetWithText(EmptyStateView, 'Clear search'),
        findsOneWidget,
      );
    });

    testWidgets('filters that hid everything say so, and how many there are', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester, discovery: refusing(searching: false));

      await tester.tap(find.byTooltip('Filter these stops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cafe (1)'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      // Not "no stops on this route": there are six, and saying otherwise
      // tells a customer there is no food on a road that has some.
      expect(find.text('No stops match your filters'), findsOneWidget);
      expect(find.textContaining('There are 6 stops'), findsOneWidget);
      expect(find.text('No stops on this route yet'), findsNothing);
    });

    testWidgets('the filters stay on screen when they hid everything', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester, discovery: refusing(searching: false));

      await tester.tap(find.byTooltip('Filter these stops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cafe (1)'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      // A screen that swaps its whole body for an empty state takes away the
      // only way out of the state it is in.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Cafe'), findsOneWidget);
    });

    testWidgets('an empty road still reads as an empty road', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          facets: facets,
          restaurants: const <DiscoveredRestaurant>[],
        ),
      );

      expect(find.text('No stops on this route yet'), findsOneWidget);
    });
  });

  group('the count above the list', () {
    testWidgets('says how many, plainly, when nothing is filtering', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(find.text('1 stop on your route'), findsOneWidget);
    });

    testWidgets('says how many of how many once something is', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          facets: facets,
          responder: (DiscoveryQuery query) => sampleDiscovery(
            facets: facets,
            restaurants: <DiscoveredRestaurant>[sampleRestaurant()],
            total: 1,
            eligibleTotal: 6,
          ),
        ),
      );

      await type(tester, 'spice');

      expect(find.text('1 of 6 stops'), findsOneWidget);
    });
  });

  group('paging', () {
    testWidgets('offers more only when there is more', (
      WidgetTester tester,
    ) async {
      await openDiscovery(tester);

      expect(find.text('Show more stops'), findsNothing);
    });

    testWidgets('appends the next page to what is already read', (
      WidgetTester tester,
    ) async {
      await openDiscovery(
        tester,
        discovery: FakeDiscoveryRepository(
          facets: facets,
          responder: (DiscoveryQuery query) => sampleDiscovery(
            facets: facets,
            restaurants: <DiscoveredRestaurant>[
              sampleRestaurant(
                id: 'r${query.page}',
                name: 'Stop ${query.page}',
              ),
            ],
            total: 2,
            page: query.page,
            perPage: 1,
            lastPage: 2,
            hasMore: query.page < 2,
          ),
        ),
      );

      await tester.tap(find.text('Show more stops'));
      await tester.pumpAndSettle();

      expect(find.text('Stop 1'), findsOneWidget);
      expect(find.text('Stop 2'), findsOneWidget);
    });
  });

  group('narrow screens', () {
    testWidgets('the controls fit at 320dp', (WidgetTester tester) async {
      await openDiscovery(tester, size: const Size(320, 720));

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Filter these stops'), findsOneWidget);
    });
  });
}
