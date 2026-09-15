/// How the customer has narrowed the restaurants on their route.
///
/// The client's half of the server's `DiscoveryQuery`. Deliberately the same
/// shape and the same vocabulary — slugs, not labels; seconds, not minutes;
/// `price_levels`, not "₹₹" — so that what the screen holds is exactly what the
/// server is asked for, and a mismatch between them is a compile error rather
/// than a filter that silently does nothing.
///
/// Immutable, and compared by value. That is what lets the controller ask "is
/// this actually different from what is on screen?" before spending a request.
library;

/// The orders the server can sort by.
///
/// Stable identifiers, never display labels: `highest_rated` is what goes on
/// the wire whatever the interface calls it, and a translated string can never
/// become a sort the server does not recognise.
enum DiscoverySort {
  recommended('recommended'),
  lowestDetour('lowest_detour'),
  soonestAlongRoute('soonest_along_route'),
  highestRated('highest_rated'),
  priceLowToHigh('price_low_to_high');

  const DiscoverySort(this.wire);

  final String wire;

  static DiscoverySort fromWire(String? value) {
    for (final DiscoverySort s in DiscoverySort.values) {
      if (s.wire == value) return s;
    }
    return DiscoverySort.recommended;
  }
}

/// The two availability questions, which are not the same question.
///
/// "Open" includes a restaurant that has paused its own orders — it is open,
/// the lights are on — while "taking orders" does not. Collapsing them would
/// send somebody to a counter that cannot serve them.
enum AvailabilityFilter {
  openNow('open_now'),
  acceptingOrders('accepting_orders');

  const AvailabilityFilter(this.wire);

  final String wire;

  static AvailabilityFilter? fromWire(String? value) {
    for (final AvailabilityFilter a in AvailabilityFilter.values) {
      if (a.wire == value) return a;
    }
    return null;
  }
}

/// A search, a set of filters, a sort and a page.
class DiscoveryQuery {
  const DiscoveryQuery({
    this.search,
    this.cuisines = const <String>{},
    this.facilities = const <String>{},
    this.priceLevels = const <int>{},
    this.availability,
    this.maxDetourSeconds,
    this.maxDistanceAheadMetres,
    this.minRating,
    this.sort = DiscoverySort.recommended,
    this.page = 1,
  });

  /// Nothing asked for: every eligible stop, in recommended order.
  static const DiscoveryQuery unfiltered = DiscoveryQuery();

  /// Below this many characters the search is not sent at all — it would match
  /// most of the corridor and cost a request per keystroke. The server applies
  /// the same rule; this one exists so the request is never made.
  static const int minSearchLength = 2;

  static const int maxSearchLength = 100;

  final String? search;

  /// Slugs. Any of them will do.
  final Set<String> cuisines;

  /// Slugs. All of them are required — a customer who asked for parking *and* a
  /// restroom has not asked for either.
  final Set<String> facilities;

  final Set<int> priceLevels;
  final AvailabilityFilter? availability;
  final int? maxDetourSeconds;
  final int? maxDistanceAheadMetres;
  final double? minRating;
  final DiscoverySort sort;
  final int page;

  bool get hasSearch {
    final String? s = search;
    return s != null && s.trim().length >= minSearchLength;
  }

  /// Whether anything other than the search narrows the list.
  ///
  /// The sort is not a filter: reordering the same restaurants is not the same
  /// act as removing some of them, and a "3 filters" badge that counted the
  /// sort would tell the customer they had hidden something when they had not.
  bool get hasFilters =>
      cuisines.isNotEmpty ||
      facilities.isNotEmpty ||
      priceLevels.isNotEmpty ||
      availability != null ||
      maxDetourSeconds != null ||
      maxDistanceAheadMetres != null ||
      minRating != null;

  bool get isRefined => hasSearch || hasFilters;

  /// How many filters to show on the badge.
  ///
  /// One per *value*, not one per group: "North Indian, Cafe" is two things the
  /// customer chose, and calling it one understates what they have hidden.
  int get filterCount =>
      cuisines.length +
      facilities.length +
      priceLevels.length +
      (availability == null ? 0 : 1) +
      (maxDetourSeconds == null ? 0 : 1) +
      (maxDistanceAheadMetres == null ? 0 : 1) +
      (minRating == null ? 0 : 1);

  /// The query as URL parameters, omitting everything unset.
  ///
  /// Sets are sorted on the way out. Two customers who picked the same two
  /// cuisines in a different order produce the same query string, which is what
  /// lets the server's cache treat them as the same question.
  Map<String, String> toQueryParameters() {
    final Map<String, String> params = <String, String>{};

    if (hasSearch) params['search'] = search!.trim();
    if (cuisines.isNotEmpty) params['cuisines'] = _joined(cuisines);
    if (facilities.isNotEmpty) params['facilities'] = _joined(facilities);
    if (priceLevels.isNotEmpty) {
      params['price_levels'] = (priceLevels.toList()..sort()).join(',');
    }
    if (availability != null) params['availability'] = availability!.wire;
    if (maxDetourSeconds != null) {
      params['max_detour_seconds'] = '$maxDetourSeconds';
    }
    if (maxDistanceAheadMetres != null) {
      params['max_distance_ahead_meters'] = '$maxDistanceAheadMetres';
    }
    if (minRating != null) params['min_rating'] = '$minRating';

    params['sort'] = sort.wire;
    if (page > 1) params['page'] = '$page';

    return params;
  }

  static String _joined(Set<String> values) =>
      (values.toList()..sort()).join(',');

  /// A copy with one thing changed.
  ///
  /// Every change but an explicit page returns to page 1. A customer who adds a
  /// cuisine while on page 3 is asking a new question, and answering it with
  /// the third page of it is how a filter appears to return nothing.
  DiscoveryQuery copyWith({
    String? search,
    bool clearSearch = false,
    Set<String>? cuisines,
    Set<String>? facilities,
    Set<int>? priceLevels,
    AvailabilityFilter? availability,
    bool clearAvailability = false,
    int? maxDetourSeconds,
    bool clearMaxDetour = false,
    int? maxDistanceAheadMetres,
    bool clearMaxDistanceAhead = false,
    double? minRating,
    bool clearMinRating = false,
    DiscoverySort? sort,
    int? page,
  }) => DiscoveryQuery(
    search: clearSearch ? null : (search ?? this.search),
    cuisines: cuisines ?? this.cuisines,
    facilities: facilities ?? this.facilities,
    priceLevels: priceLevels ?? this.priceLevels,
    availability: clearAvailability
        ? null
        : (availability ?? this.availability),
    maxDetourSeconds: clearMaxDetour
        ? null
        : (maxDetourSeconds ?? this.maxDetourSeconds),
    maxDistanceAheadMetres: clearMaxDistanceAhead
        ? null
        : (maxDistanceAheadMetres ?? this.maxDistanceAheadMetres),
    minRating: clearMinRating ? null : (minRating ?? this.minRating),
    sort: sort ?? this.sort,
    page: page ?? 1,
  );

  /// Everything the customer chose, dropped. The search and the sort survive:
  /// "clear filters" is a button under the filter chips, not an undo for the
  /// text somebody is still typing.
  DiscoveryQuery cleared() =>
      DiscoveryQuery(search: search, sort: sort, page: 1);

  /// Toggles one value in a multi-select group.
  DiscoveryQuery toggleCuisine(String slug) =>
      copyWith(cuisines: _toggled(cuisines, slug));

  DiscoveryQuery toggleFacility(String slug) =>
      copyWith(facilities: _toggled(facilities, slug));

  DiscoveryQuery togglePriceLevel(int level) =>
      copyWith(priceLevels: _toggled(priceLevels, level));

  static Set<T> _toggled<T>(Set<T> values, T value) {
    final Set<T> next = Set<T>.of(values);

    if (!next.remove(value)) next.add(value);

    return next;
  }

  /// Value equality, ignoring the page.
  ///
  /// Used to decide whether a request is worth making at all. Two queries that
  /// differ only in their page are different requests, so [page] is part of
  /// [==]; this is the narrower question the filter sheet asks when deciding
  /// whether "Apply" would change anything.
  bool sameFilters(DiscoveryQuery other) =>
      search == other.search &&
      _setEquals(cuisines, other.cuisines) &&
      _setEquals(facilities, other.facilities) &&
      _setEquals(priceLevels, other.priceLevels) &&
      availability == other.availability &&
      maxDetourSeconds == other.maxDetourSeconds &&
      maxDistanceAheadMetres == other.maxDistanceAheadMetres &&
      minRating == other.minRating &&
      sort == other.sort;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiscoveryQuery && sameFilters(other) && page == other.page);

  @override
  int get hashCode => Object.hash(
    search,
    Object.hashAllUnordered(cuisines),
    Object.hashAllUnordered(facilities),
    Object.hashAllUnordered(priceLevels),
    availability,
    maxDetourSeconds,
    maxDistanceAheadMetres,
    minRating,
    sort,
    page,
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
