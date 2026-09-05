import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/discovery_facets.dart';
import 'package:foodonthego/domain/models/discovery_query.dart';
import 'package:foodonthego/shared/state/discovery_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Searching, filtering and sorting, as the controller runs them.
///
/// The two things being defended here are the customer's rate-limit budget —
/// the discovery endpoint allows only a handful of calls a minute — and the
/// order results land in. Both are invisible when they work and both produce
/// baffling behaviour when they do not.
void main() {
  late FakeDiscoveryRepository discovery;
  late ProviderContainer container;

  ProviderContainer build(FakeDiscoveryRepository repository) {
    final ProviderContainer c = ProviderContainer(
      overrides: [discoveryRepositoryProvider.overrideWithValue(repository)],
    );

    c.listen(
      discoveryControllerProvider,
      (DiscoveryState? _, DiscoveryState _) {},
      fireImmediately: true,
    );

    addTearDown(c.dispose);

    return c;
  }

  DiscoveryController controller() =>
      container.read(discoveryControllerProvider.notifier);

  DiscoveryState state() => container.read(discoveryControllerProvider);

  Future<void> settle() =>
      Future<void>.delayed(DiscoveryController.searchDebounce * 2);

  Future<void> openTrip([FakeDiscoveryRepository? repository]) async {
    discovery = repository ?? FakeDiscoveryRepository();
    container = build(discovery);
    await controller().open('trip-1');
  }

  group('typing', () {
    test('the field updates immediately and the request does not', () async {
      await openTrip();

      controller().searchChanged('spi');

      expect(state().searchText, 'spi');
      // Still just the one call from opening the screen.
      expect(discovery.discoverCalls, 1);
    });

    test('a word typed at speed is one request, not six', () async {
      await openTrip();

      for (final String typed in <String>['s', 'sp', 'spi', 'spic', 'spice']) {
        controller().searchChanged(typed);
      }

      await settle();

      // The debounce exists because the endpoint's rate limit is exhausted
      // inside one word otherwise.
      expect(discovery.discoverCalls, 2);
      expect(discovery.lastQuery!.search, 'spice');
    });

    test('one letter is not a search', () async {
      await openTrip();

      controller().searchChanged('s');
      await settle();

      // It would match most of the corridor and tell the customer nothing.
      expect(discovery.discoverCalls, 1);
      expect(state().query.hasSearch, isFalse);
    });

    test('submitting skips the wait', () async {
      await openTrip();

      controller().searchChanged('spice');
      controller().submitSearch();

      await Future<void>.delayed(Duration.zero);

      expect(discovery.discoverCalls, 2);
      expect(discovery.lastQuery!.search, 'spice');
    });

    test('clearing the field drops the term from the request', () async {
      await openTrip();

      controller().searchChanged('spice');
      await settle();

      controller().clearSearch();
      await Future<void>.delayed(Duration.zero);

      expect(state().searchText, '');
      expect(state().query.hasSearch, isFalse);
      expect(
        discovery.lastQuery!.toQueryParameters().containsKey('search'),
        isFalse,
      );
    });

    test('clearing an already-empty field costs nothing', () async {
      await openTrip();

      controller().clearSearch();
      await settle();

      expect(discovery.discoverCalls, 1);
    });

    test('the old list stays visible while a search runs', () async {
      await openTrip(
        FakeDiscoveryRepository()..delay = const Duration(milliseconds: 40),
      );

      controller().searchChanged('spice');
      controller().submitSearch();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // A list that empties on every keystroke cannot be read while typing.
      expect(state().isRefining, isTrue);
      expect(state().isLoading, isFalse);
      expect(state().hasResults, isTrue);
    });
  });

  group('answers arriving out of order', () {
    test('a slow early answer never overwrites a fast later one', () async {
      final DiscoveredRestaurant slow = sampleRestaurant(
        id: 'slow',
        name: 'Slow Answer',
      );
      final DiscoveredRestaurant fast = sampleRestaurant(
        id: 'fast',
        name: 'Fast Answer',
      );

      final FakeDiscoveryRepository repository =
          FakeDiscoveryRepository(
              responder: (DiscoveryQuery query) => sampleDiscovery(
                restaurants: <DiscoveredRestaurant>[
                  query.search == 'spi' ? slow : fast,
                ],
              ),
            )
            ..delayFor = (DiscoveryQuery query) => query.search == 'spi'
                ? const Duration(milliseconds: 80)
                : const Duration(milliseconds: 10);

      await openTrip(repository);

      controller().searchChanged('spi');
      controller().submitSearch();

      controller().searchChanged('spice');
      controller().submitSearch();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Without the generation check, "spi" lands last and the customer reads
      // the results for a word they have already finished typing.
      expect(state().restaurants.single.name, 'Fast Answer');
      expect(state().isRefining, isFalse);
    });

    test('a stale failure does not put an error over a good list', () async {
      final FakeDiscoveryRepository repository = FakeDiscoveryRepository()
        ..delayFor = ((DiscoveryQuery query) => query.search == 'spi'
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 10))
        // Only the request the customer has moved on from fails.
        ..errorFor = ((DiscoveryQuery query) => query.search == 'spi'
            ? ApiException(code: ApiErrorCode.serverError, message: 'boom')
            : null);

      await openTrip(repository);

      controller().searchChanged('spi');
      controller().submitSearch();

      controller().searchChanged('spice');
      controller().submitSearch();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(state().failure, isNull);
      expect(state().hasResults, isTrue);
    });
  });

  group('filters', () {
    test('applying a query sends it', () async {
      await openTrip();

      controller().applyQuery(
        const DiscoveryQuery(cuisines: <String>{'north_indian'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(discovery.lastQuery!.cuisines, <String>{'north_indian'});
      expect(state().query.filterCount, 1);
    });

    test('applying the query already in force costs nothing', () async {
      await openTrip();

      controller().applyQuery(
        const DiscoveryQuery(cuisines: <String>{'north_indian'}),
      );
      await Future<void>.delayed(Duration.zero);

      controller().applyQuery(
        const DiscoveryQuery(cuisines: <String>{'north_indian'}),
      );
      await Future<void>.delayed(Duration.zero);

      // "Apply" on an untouched sheet is not a request against the rate limit.
      expect(discovery.discoverCalls, 2);
    });

    test('removing one chip leaves the rest of its group', () async {
      await openTrip();

      controller().applyQuery(
        const DiscoveryQuery(cuisines: <String>{'north_indian', 'cafe'}),
      );
      await Future<void>.delayed(Duration.zero);

      controller().removeCuisine('cafe');
      await Future<void>.delayed(Duration.zero);

      expect(state().query.cuisines, <String>{'north_indian'});
    });

    test('clear all keeps the search', () async {
      await openTrip();

      controller().searchChanged('spice');
      controller().submitSearch();
      await Future<void>.delayed(Duration.zero);

      controller().applyQuery(
        state().query.copyWith(facilities: <String>{'parking'}),
      );
      await Future<void>.delayed(Duration.zero);

      controller().clearFilters();
      await Future<void>.delayed(Duration.zero);

      expect(state().query.hasFilters, isFalse);
      expect(state().query.search, 'spice');
    });

    test('a sort is sent and is not counted as a filter', () async {
      await openTrip();

      controller().sortBy(DiscoverySort.lowestDetour);
      await Future<void>.delayed(Duration.zero);

      expect(discovery.lastQuery!.sort, DiscoverySort.lowestDetour);
      expect(state().query.filterCount, 0);
    });

    test('the server refusing a filter is reported as ours to fix', () async {
      await openTrip();

      discovery.nextError = ApiException(
        code: ApiErrorCode.validationFailed,
        message: 'The filters could not be understood.',
      );

      controller().applyQuery(
        const DiscoveryQuery(cuisines: <String>{'north_indian'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(state().failure, DiscoveryFailure.filtersRejected);
    });

    test('resetting puts everything back', () async {
      await openTrip();

      controller().searchChanged('spice');
      controller().submitSearch();
      await Future<void>.delayed(Duration.zero);

      controller().resetAll();
      await Future<void>.delayed(Duration.zero);

      expect(state().searchText, '');
      expect(state().query, DiscoveryQuery.unfiltered);
    });
  });

  group('paging', () {
    FakeDiscoveryRepository paged() => FakeDiscoveryRepository(
      responder: (DiscoveryQuery query) => sampleDiscovery(
        restaurants: <DiscoveredRestaurant>[
          sampleRestaurant(id: 'r${query.page}', name: 'Stop ${query.page}'),
        ],
        total: 3,
        page: query.page,
        perPage: 1,
        lastPage: 3,
        hasMore: query.page < 3,
      ),
    );

    test('the next page is appended, not swapped in', () async {
      await openTrip(paged());

      await controller().loadMore();

      // Replacing the list would take away what the customer already scrolled
      // past to show them the next twenty.
      expect(
        state().restaurants.map((DiscoveredRestaurant r) => r.name),
        <String>['Stop 1', 'Stop 2'],
      );
      expect(state().query.page, 2);
    });

    test('a duplicate across a page boundary appears once', () async {
      final FakeDiscoveryRepository repository = FakeDiscoveryRepository(
        responder: (DiscoveryQuery query) => sampleDiscovery(
          restaurants: <DiscoveredRestaurant>[
            sampleRestaurant(id: 'same', name: 'Same Stop'),
          ],
          total: 2,
          page: query.page,
          perPage: 1,
          lastPage: 2,
          hasMore: query.page < 2,
        ),
      );

      await openTrip(repository);
      await controller().loadMore();

      // Pages are computed from a snapshot that can shift under them.
      expect(state().restaurants, hasLength(1));
    });

    test('there is no next page to ask for at the end', () async {
      await openTrip(paged());

      await controller().loadMore();
      await controller().loadMore();

      final int calls = discovery.discoverCalls;
      await controller().loadMore();

      expect(state().hasMore, isFalse);
      expect(discovery.discoverCalls, calls);
    });

    test('a filter change starts again at page one', () async {
      await openTrip(paged());

      await controller().loadMore();
      controller().sortBy(DiscoverySort.lowestDetour);
      await Future<void>.delayed(Duration.zero);

      // Answering a new question with its third page is how a filter appears
      // to return nothing.
      expect(discovery.lastQuery!.page, 1);
      expect(state().restaurants, hasLength(1));
    });

    test('a failed page keeps the customer where they were', () async {
      await openTrip(paged());

      discovery.nextError = ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
      );

      await controller().loadMore();

      expect(state().restaurants, hasLength(1));
      expect(state().isLoadingMore, isFalse);
      expect(state().failure, DiscoveryFailure.network);
    });
  });

  group('what the screen can tell apart', () {
    test('filters hiding everything is not an empty road', () async {
      await openTrip(
        FakeDiscoveryRepository(
          responder: (DiscoveryQuery query) => sampleDiscovery(
            restaurants: query.isRefined
                ? const <DiscoveredRestaurant>[]
                : <DiscoveredRestaurant>[sampleRestaurant()],
            total: query.isRefined ? 0 : 1,
            eligibleTotal: 6,
            filteredEmpty: query.isRefined,
          ),
        ),
      );

      controller().applyQuery(
        const DiscoveryQuery(facilities: <String>{'charging'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(state().isEmptyResult, isTrue);
      expect(state().isFilteredEmpty, isTrue);
      expect(state().isSearchEmpty, isFalse);
      expect(state().eligibleCount, 6);
    });

    test('a search that found nothing says so in its own words', () async {
      await openTrip(
        FakeDiscoveryRepository(
          responder: (DiscoveryQuery query) => sampleDiscovery(
            restaurants: const <DiscoveredRestaurant>[],
            total: 0,
            eligibleTotal: 4,
            filteredEmpty: true,
          ),
        ),
      );

      controller().searchChanged('sushi');
      controller().submitSearch();
      await Future<void>.delayed(Duration.zero);

      expect(state().isSearchEmpty, isTrue);
    });

    test('an empty road is still an empty road', () async {
      await openTrip(
        FakeDiscoveryRepository(restaurants: const <DiscoveredRestaurant>[]),
      );

      expect(state().isEmptyResult, isTrue);
      expect(state().isFilteredEmpty, isFalse);
    });
  });

  group('facets', () {
    test('the options come from the server, not from this build', () async {
      await openTrip(
        FakeDiscoveryRepository(
          facets: const DiscoveryFacets(
            cuisines: <FilterOption>[
              FilterOption(slug: 'cafe', label: 'Cafe', count: 2),
            ],
            ratingAvailable: false,
          ),
        ),
      );

      expect(state().facets.cuisines.single.slug, 'cafe');
      expect(state().facets.ratingAvailable, isFalse);
    });
  });
}
