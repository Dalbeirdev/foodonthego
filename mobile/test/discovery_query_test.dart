import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/discovery_facets.dart';
import 'package:foodonthego/domain/models/discovery_query.dart';

/// The client's query object, and the facets it renders itself from.
void main() {
  group('what goes on the wire', () {
    test('an unfiltered query asks for nothing but an order', () {
      expect(DiscoveryQuery.unfiltered.toQueryParameters(), <String, String>{
        'sort': 'recommended',
      });
    });

    test('slugs go on the wire, never labels', () {
      const DiscoveryQuery query = DiscoveryQuery(
        cuisines: <String>{'north_indian', 'cafe'},
        facilities: <String>{'parking'},
      );

      final Map<String, String> params = query.toQueryParameters();

      expect(params['cuisines'], 'cafe,north_indian');
      expect(params['facilities'], 'parking');
    });

    test('the same choices in a different order are the same request', () {
      const DiscoveryQuery a = DiscoveryQuery(
        facilities: <String>{'restroom', 'parking'},
      );
      const DiscoveryQuery b = DiscoveryQuery(
        facilities: <String>{'parking', 'restroom'},
      );

      // Which is what lets the server's cache treat them as one question.
      expect(a.toQueryParameters(), b.toQueryParameters());
      expect(a, b);
    });

    test('a search shorter than the minimum is not sent', () {
      const DiscoveryQuery query = DiscoveryQuery(search: 'a');

      expect(query.hasSearch, isFalse);
      expect(query.toQueryParameters().containsKey('search'), isFalse);
    });

    test('a search is trimmed rather than sent with its whitespace', () {
      expect(
        const DiscoveryQuery(search: '  spice  ').toQueryParameters()['search'],
        'spice',
      );
    });

    test('page one is implied rather than stated', () {
      expect(
        DiscoveryQuery.unfiltered.toQueryParameters().containsKey('page'),
        isFalse,
      );
      expect(const DiscoveryQuery(page: 3).toQueryParameters()['page'], '3');
    });

    test('every filter reaches the query string under its own name', () {
      const DiscoveryQuery query = DiscoveryQuery(
        search: 'spice',
        cuisines: <String>{'cafe'},
        facilities: <String>{'parking'},
        priceLevels: <int>{2, 1},
        availability: AvailabilityFilter.acceptingOrders,
        maxDetourSeconds: 600,
        maxDistanceAheadMetres: 120000,
        minRating: 4.0,
        sort: DiscoverySort.lowestDetour,
      );

      expect(query.toQueryParameters(), <String, String>{
        'search': 'spice',
        'cuisines': 'cafe',
        'facilities': 'parking',
        'price_levels': '1,2',
        'availability': 'accepting_orders',
        'max_detour_seconds': '600',
        'max_distance_ahead_meters': '120000',
        'min_rating': '4.0',
        'sort': 'lowest_detour',
      });
    });
  });

  group('counting what is on', () {
    test('the sort is not a filter', () {
      const DiscoveryQuery query = DiscoveryQuery(
        sort: DiscoverySort.priceLowToHigh,
      );

      // Reordering a list is not hiding part of it, and a badge saying "1
      // filter" over a complete list would say the customer had hidden
      // something they had not.
      expect(query.hasFilters, isFalse);
      expect(query.filterCount, 0);
    });

    test('a search is not a filter either, but it does refine', () {
      const DiscoveryQuery query = DiscoveryQuery(search: 'spice');

      expect(query.hasFilters, isFalse);
      expect(query.isRefined, isTrue);
    });

    test('the badge counts values, not groups', () {
      const DiscoveryQuery query = DiscoveryQuery(
        cuisines: <String>{'cafe', 'north_indian'},
        facilities: <String>{'parking'},
        availability: AvailabilityFilter.openNow,
      );

      expect(query.filterCount, 4);
    });
  });

  group('changing it', () {
    test('any change but a page returns to page one', () {
      const DiscoveryQuery onPageThree = DiscoveryQuery(page: 3);

      // A customer who adds a cuisine on page 3 is asking a new question, and
      // answering it with the third page of it is how a filter appears to
      // return nothing.
      expect(onPageThree.toggleCuisine('cafe').page, 1);
      expect(onPageThree.copyWith(sort: DiscoverySort.lowestDetour).page, 1);
      expect(onPageThree.copyWith(page: 4).page, 4);
    });

    test('a toggle adds and then removes', () {
      final DiscoveryQuery once = DiscoveryQuery.unfiltered.toggleCuisine(
        'cafe',
      );
      final DiscoveryQuery twice = once.toggleCuisine('cafe');

      expect(once.cuisines, <String>{'cafe'});
      expect(twice.cuisines, isEmpty);
    });

    test('clearing keeps the search and the order', () {
      const DiscoveryQuery query = DiscoveryQuery(
        search: 'spice',
        cuisines: <String>{'cafe'},
        sort: DiscoverySort.lowestDetour,
      );

      final DiscoveryQuery cleared = query.cleared();

      // "Clear all" sits under the filter chips. It is not an undo for the text
      // the customer is still looking at.
      expect(cleared.search, 'spice');
      expect(cleared.sort, DiscoverySort.lowestDetour);
      expect(cleared.hasFilters, isFalse);
    });

    test('a filter can be cleared as well as set', () {
      const DiscoveryQuery query = DiscoveryQuery(
        availability: AvailabilityFilter.openNow,
        maxDetourSeconds: 600,
        minRating: 4,
      );

      expect(query.copyWith(clearAvailability: true).availability, isNull);
      expect(query.copyWith(clearMaxDetour: true).maxDetourSeconds, isNull);
      expect(query.copyWith(clearMinRating: true).minRating, isNull);
    });
  });

  group('reading the facets the server sent', () {
    test('options carry their slug, label and count', () {
      final DiscoveryFacets facets = DiscoveryFacets.fromJson(<String, dynamic>{
        'cuisines': <dynamic>[
          <String, dynamic>{
            'slug': 'north_indian',
            'label': 'North Indian',
            'count': 3,
          },
        ],
        'facilities': <dynamic>[
          <String, dynamic>{'slug': 'parking', 'label': 'Parking', 'count': 2},
        ],
        'price_levels': <dynamic>[
          <String, dynamic>{'level': 2, 'count': 4},
        ],
        'availability': <dynamic>[
          <String, dynamic>{
            'value': 'open_now',
            'label': 'Open now',
            'count': 3,
          },
        ],
        'rating_available': false,
        'max_detour_seconds': 900,
      });

      expect(facets.cuisines.single.slug, 'north_indian');
      expect(facets.cuisines.single.label, 'North Indian');
      expect(facets.cuisines.single.count, 3);
      expect(facets.priceLevels.single.level, 2);
      expect(facets.availability.single.value, AvailabilityFilter.openNow);
      expect(facets.maxDetourSeconds, 900);
    });

    test('a rating filter is unavailable until something is rated', () {
      expect(
        DiscoveryFacets.fromJson(const <String, dynamic>{}).ratingAvailable,
        isFalse,
      );
    });

    test('an unavailable sort keeps its reason rather than disappearing', () {
      final DiscoveryFacets facets = DiscoveryFacets.fromJson(<String, dynamic>{
        'sorts': <dynamic>[
          <String, dynamic>{
            'value': 'recommended',
            'label': 'Recommended',
            'available': true,
          },
          <String, dynamic>{
            'value': 'highest_rated',
            'label': 'Highest rated',
            'available': false,
            'unavailable_reason': 'No restaurant has a rating yet.',
          },
        ],
      });

      expect(facets.sorts, hasLength(2));
      expect(facets.availableSorts, hasLength(1));
      expect(
        facets.optionFor(DiscoverySort.highestRated)!.unavailableReason,
        'No restaurant has a rating yet.',
      );
    });

    test('a sort this build has never heard of is dropped, not blank', () {
      final DiscoveryFacets facets = DiscoveryFacets.fromJson(<String, dynamic>{
        'sorts': <dynamic>[
          <String, dynamic>{'value': 'most_haunted', 'label': 'Most haunted'},
        ],
      });

      expect(facets.sorts, isEmpty);
    });

    test('an option with no slug is not an option', () {
      final DiscoveryFacets facets = DiscoveryFacets.fromJson(<String, dynamic>{
        'cuisines': <dynamic>[
          <String, dynamic>{'label': 'North Indian', 'count': 3},
        ],
      });

      expect(facets.cuisines, isEmpty);
    });
  });

  group('reading the page the server sent', () {
    RestaurantDiscovery parse(Map<String, dynamic> meta) =>
        RestaurantDiscovery.fromJson(<String, dynamic>{
          'route': <String, dynamic>{
            'route_id': 'route-1',
            'provider': 'google',
          },
          'restaurants': <dynamic>[],
          'meta': meta,
        });

    test('the two totals are kept apart', () {
      final RestaurantDiscovery page = parse(<String, dynamic>{
        'total': 0,
        'eligible_total': 6,
        'filtered_empty': true,
      });

      // Which is the whole basis of telling "your filters hid everything" from
      // "there is nothing on this road".
      expect(page.total, 0);
      expect(page.eligibleTotal, 6);
      expect(page.isFilteredEmpty, isTrue);
    });

    test('a response with no totals falls back to what it carries', () {
      final RestaurantDiscovery page = parse(const <String, dynamic>{});

      expect(page.total, 0);
      expect(page.eligibleTotal, 0);
      expect(page.page, 1);
      expect(page.hasMore, isFalse);
    });
  });
}
