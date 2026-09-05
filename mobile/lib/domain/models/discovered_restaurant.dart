import '../../core/geo/polyline_codec.dart';
import 'discovery_facets.dart';

/// Whether a traveller can actually stop here.
///
/// Mirrors the server's enum rather than reducing it to a boolean, because the
/// six cases call for six different things on a card: "Open" is a green chip,
/// "Not accepting orders" is a warning that must never read as availability, and
/// "Opens soon" is useful to somebody an hour away in a way that "Closed" is not.
enum RestaurantAvailability {
  open('OPEN'),
  closingSoon('CLOSING_SOON'),
  openingSoon('OPENING_SOON'),
  closed('CLOSED'),
  notAcceptingOrders('NOT_ACCEPTING_ORDERS'),

  /// No opening hours on file. Not a claim that it is shut.
  unknown('UNKNOWN');

  const RestaurantAvailability(this.wire);

  final String wire;

  static RestaurantAvailability fromWire(String? value) {
    for (final RestaurantAvailability a in RestaurantAvailability.values) {
      if (a.wire == value) return a;
    }
    // A newer server naming a state this build has never heard of degrades to
    // "we do not know" rather than to a confident "Open".
    return RestaurantAvailability.unknown;
  }

  /// Whether a customer could order here now, if the rest of the app existed.
  bool get isActionable =>
      this == RestaurantAvailability.open ||
      this == RestaurantAvailability.closingSoon;
}

/// What this route says about a restaurant.
///
/// Four numbers that are easy to confuse and mean quite different things.
/// [proximityMetres] is how far it sits from the road; [detourDurationSeconds]
/// is what stopping actually costs. A restaurant can be near and expensive, and
/// treating the first as the second is the mistake this whole module exists to
/// avoid.
class RouteRelation {
  const RouteRelation({
    required this.proximityMetres,
    required this.distanceAheadMetres,
    this.detourDistanceMetres,
    this.detourDurationSeconds,
    this.timeAheadSeconds,
    this.requiresBacktracking = false,
  });

  final int proximityMetres;
  final int distanceAheadMetres;

  /// Null when no provider could say. **Not zero** — a zero would be a claim
  /// that stopping is free, and the card renders an absent badge instead.
  final int? detourDistanceMetres;
  final int? detourDurationSeconds;

  final int? timeAheadSeconds;

  /// Reaching this means driving back the way you came.
  final bool requiresBacktracking;

  bool get hasDetour => detourDurationSeconds != null;

  static RouteRelation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final int? proximity = _int(json['proximity_meters']);
    final int? ahead = _int(json['distance_ahead_meters']);

    // Both are required. A restaurant with no position on the route is not a
    // stop on the route, and rendering it with a blank "km ahead" would be a
    // card that says nothing.
    if (proximity == null || ahead == null) return null;

    return RouteRelation(
      proximityMetres: proximity,
      distanceAheadMetres: ahead,
      detourDistanceMetres: _int(json['detour_distance_meters']),
      detourDurationSeconds: _int(json['detour_duration_seconds']),
      timeAheadSeconds: _int(json['time_ahead_seconds']),
      requiresBacktracking: json['requires_backtracking'] == true,
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// A restaurant a customer could stop at, and where it is on their journey.
class DiscoveredRestaurant {
  const DiscoveredRestaurant({
    required this.id,
    required this.name,
    required this.position,
    required this.route,
    required this.availability,
    required this.cuisines,
    required this.facilities,
    this.shortName,
    this.city,
    this.priceLevel,
    this.rating,
    this.reviewCount,
    this.logoUrl,
    this.isAcceptingOrders = true,
  });

  final String id;
  final String name;
  final String? shortName;
  final String? city;
  final GeoPoint position;
  final RouteRelation route;
  final RestaurantAvailability availability;
  final List<String> cuisines;
  final List<String> facilities;

  /// 1 to 4, or null. Only ever rendered when the restaurant actually declared
  /// one — an assumed "₹₹" is a claim about somebody's prices.
  final int? priceLevel;

  /// Null until there is a reviews module. The card shows nothing rather than a
  /// hopeful 4.5.
  final double? rating;
  final int? reviewCount;

  final String? logoUrl;
  final bool isAcceptingOrders;

  String get displayName => shortName?.isNotEmpty == true ? shortName! : name;

  bool get hasRating => rating != null;

  /// Returns null for anything that cannot be drawn on a map or placed on a
  /// route. A restaurant with no id, no name or no position is not a result —
  /// it is a row the server should not have sent, and building a half one would
  /// put an unlabelled marker on the map.
  static DiscoveredRestaurant? fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] as String?) ?? '';
    final String name = (json['name'] as String?) ?? '';

    if (id.isEmpty || name.isEmpty) return null;

    final GeoPoint? position = _position(json['location']);
    if (position == null) return null;

    final RouteRelation? relation = RouteRelation.fromJson(
      json['route'] as Map<String, dynamic>?,
    );
    if (relation == null) return null;

    return DiscoveredRestaurant(
      id: id,
      name: name,
      shortName: json['short_name'] as String?,
      city: json['city'] as String?,
      position: position,
      route: relation,
      availability: RestaurantAvailability.fromWire(
        json['availability'] as String?,
      ),
      cuisines: _strings(json['cuisines']),
      facilities: _strings(json['facilities']),
      priceLevel: RouteRelation._int(json['price_level']),
      rating: _double(json['rating']),
      reviewCount: RouteRelation._int(json['review_count']),
      logoUrl: json['logo_url'] as String?,
      isAcceptingOrders: json['is_accepting_orders'] != false,
    );
  }

  static GeoPoint? _position(Object? raw) {
    if (raw is! Map) return null;

    final double? latitude = _double(raw['latitude']);
    final double? longitude = _double(raw['longitude']);

    if (latitude == null || longitude == null) return null;

    // The (0, 0) sentinel is in the Gulf of Guinea, and it is what a
    // half-populated record looks like rather than a restaurant.
    if (latitude == 0 && longitude == 0) return null;

    return GeoPoint(latitude, longitude);
  }

  static double? _double(Object? value) => switch (value) {
    final double v => v,
    final num v => v.toDouble(),
    final String v => double.tryParse(v),
    _ => null,
  };

  static List<String> _strings(Object? raw) => raw is List
      ? raw.whereType<String>().where((String s) => s.isNotEmpty).toList()
      : const <String>[];
}

/// A discovery result: the route it was run against, and what it found.
class RestaurantDiscovery {
  const RestaurantDiscovery({
    required this.restaurants,
    required this.routeId,
    required this.corridorMetres,
    this.provider,
    this.closedOnly = false,
    this.fromCache = false,
    this.candidatesConsidered = 0,
    this.facets = const DiscoveryFacets(),
    this.total = 0,
    this.eligibleTotal = 0,
    this.page = 1,
    this.perPage = 0,
    this.lastPage = 1,
    this.hasMore = false,
    this.filteredEmpty = false,
  });

  final List<DiscoveredRestaurant> restaurants;
  final String routeId;

  /// How wide a corridor was searched, so an empty state can say "within 5 km
  /// of your route" rather than guessing at it.
  final int corridorMetres;

  /// Which provider produced the route these were found along. A non-real one
  /// is labelled on screen exactly as it is on the route screen.
  final String? provider;

  /// There are restaurants, and none of them can take an order. A different
  /// thing from "there are none", and it gets different words.
  final bool closedOnly;

  final bool fromCache;
  final int candidatesConsidered;

  /// The filter options this route can actually offer, with counts.
  final DiscoveryFacets facets;

  /// How many restaurants match what the customer asked for, across every page.
  final int total;

  /// How many are on this route at all, before the customer narrowed it.
  ///
  /// The distinction the empty screen turns on. `eligibleTotal == 0` means
  /// there is nothing on this road; `eligibleTotal > 0` with `total == 0` means
  /// the customer's own filters removed everything, and those two need
  /// different words and different buttons.
  final int eligibleTotal;

  final int page;
  final int perPage;
  final int lastPage;
  final bool hasMore;

  /// The server's own verdict on the distinction above, so the client is not
  /// re-deriving it from two counts and reaching a different answer.
  final bool filteredEmpty;

  bool get isEmpty => restaurants.isEmpty;

  /// There are stops on this route; the filters hid all of them.
  bool get isFilteredEmpty => filteredEmpty;

  bool get isFromRealProvider => provider != null && provider != 'development';

  /// This page, with the pages already read in front of it.
  ///
  /// The counts and facets come from *this* response rather than the earlier
  /// one: a restaurant that closed between page one and page two changes the
  /// availability counts, and showing the older figures beside the newer rows
  /// would put a total on screen that no page agrees with.
  ///
  /// Anything already present is not added twice. Pages are computed from a
  /// snapshot that can shift under them, and a restaurant appearing on both
  /// page one and page two must not appear twice in the list.
  RestaurantDiscovery appendedTo(List<DiscoveredRestaurant> earlier) {
    final Set<String> seen = earlier
        .map((DiscoveredRestaurant r) => r.id)
        .toSet();

    return RestaurantDiscovery(
      restaurants: <DiscoveredRestaurant>[
        ...earlier,
        ...restaurants.where((DiscoveredRestaurant r) => seen.add(r.id)),
      ],
      routeId: routeId,
      corridorMetres: corridorMetres,
      provider: provider,
      closedOnly: closedOnly,
      fromCache: fromCache,
      candidatesConsidered: candidatesConsidered,
      facets: facets,
      total: total,
      eligibleTotal: eligibleTotal,
      page: page,
      perPage: perPage,
      lastPage: lastPage,
      hasMore: hasMore,
      filteredEmpty: filteredEmpty,
    );
  }

  static RestaurantDiscovery fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> route =
        (json['route'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, dynamic> meta =
        (json['meta'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    final List<dynamic> raw =
        (json['restaurants'] as List<dynamic>?) ?? const <dynamic>[];

    return RestaurantDiscovery(
      // Anything unreadable is dropped rather than half-built.
      restaurants: raw
          .whereType<Map<String, dynamic>>()
          .map(DiscoveredRestaurant.fromJson)
          .whereType<DiscoveredRestaurant>()
          .toList(growable: false),
      routeId: (route['route_id'] as String?) ?? '',
      provider: route['provider'] as String?,
      corridorMetres: RouteRelation._int(meta['corridor_meters']) ?? 0,
      closedOnly: meta['closed_only'] == true,
      fromCache: meta['from_cache'] == true,
      candidatesConsidered:
          RouteRelation._int(meta['candidates_considered']) ?? 0,
      facets: DiscoveryFacets.fromJson(
        json['filters'] as Map<String, dynamic>?,
      ),
      // A server that predates Module 08 sends no totals. Falling back to the
      // page's own length keeps the count on screen honest rather than showing
      // "0 stops" above a list of six.
      total: RouteRelation._int(meta['total']) ?? raw.length,
      eligibleTotal:
          RouteRelation._int(meta['eligible_total']) ??
          RouteRelation._int(meta['total']) ??
          raw.length,
      page: RouteRelation._int(meta['page']) ?? 1,
      perPage: RouteRelation._int(meta['per_page']) ?? raw.length,
      lastPage: RouteRelation._int(meta['last_page']) ?? 1,
      hasMore: meta['has_more'] == true,
      filteredEmpty: meta['filtered_empty'] == true,
    );
  }
}
