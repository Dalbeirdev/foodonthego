import 'discovery_query.dart';

/// The filter options worth offering for *this* route, as the server counted
/// them.
///
/// The client does not invent this list. Offering "Chinese" on a road where no
/// partner serves it produces a filter whose only outcome is an empty screen,
/// and offering a rating control where nothing is rated is worse: it implies
/// the ratings exist. Both lists come from the results themselves.
class DiscoveryFacets {
  const DiscoveryFacets({
    this.cuisines = const <FilterOption>[],
    this.facilities = const <FilterOption>[],
    this.priceLevels = const <PriceOption>[],
    this.availability = const <AvailabilityOption>[],
    this.sorts = const <SortOption>[],
    this.ratingAvailable = false,
    this.maxDetourSeconds = 0,
  });

  final List<FilterOption> cuisines;
  final List<FilterOption> facilities;
  final List<PriceOption> priceLevels;
  final List<AvailabilityOption> availability;
  final List<SortOption> sorts;

  /// False until something on this route actually has a rating. The rating
  /// control is not rendered at all while it is false — not greyed out, not
  /// shown with zero stars. It appears on its own the day a reviews module
  /// writes the first one.
  final bool ratingAvailable;

  /// The widest detour the server will consider, which is the ceiling of any
  /// detour slider the client offers.
  final int maxDetourSeconds;

  bool get isEmpty =>
      cuisines.isEmpty && facilities.isEmpty && priceLevels.isEmpty;

  /// The sorts a customer may actually pick. A sort the server has declared
  /// unavailable is kept in [sorts] so the sheet can explain why, rather than
  /// quietly dropped as though it never existed.
  List<SortOption> get availableSorts =>
      sorts.where((SortOption s) => s.isAvailable).toList(growable: false);

  SortOption? optionFor(DiscoverySort sort) {
    for (final SortOption s in sorts) {
      if (s.sort == sort) return s;
    }
    return null;
  }

  static DiscoveryFacets fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DiscoveryFacets();

    return DiscoveryFacets(
      cuisines: _list(json['cuisines'], FilterOption.fromJson),
      facilities: _list(json['facilities'], FilterOption.fromJson),
      priceLevels: _list(json['price_levels'], PriceOption.fromJson),
      availability: _list(json['availability'], AvailabilityOption.fromJson),
      sorts: _list(json['sorts'], SortOption.fromJson),
      ratingAvailable: json['rating_available'] == true,
      maxDetourSeconds: _int(json['max_detour_seconds']) ?? 0,
    );
  }

  static List<T> _list<T>(
    Object? raw,
    T? Function(Map<String, dynamic>) build,
  ) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map(build)
            .whereType<T>()
            .toList(growable: false)
      : const <Never>[];

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// One cuisine or facility, with how many stops on this route have it.
class FilterOption {
  const FilterOption({
    required this.slug,
    required this.label,
    required this.count,
  });

  /// The stable identifier that goes on the wire. The [label] is for reading;
  /// filtering by it would break the moment the interface is translated or an
  /// operator renames "Restroom" to "Toilets".
  final String slug;
  final String label;
  final int count;

  static FilterOption? fromJson(Map<String, dynamic> json) {
    final String? slug = json['slug'] as String?;
    final String? label = json['label'] as String?;

    if (slug == null || slug.isEmpty || label == null || label.isEmpty) {
      return null;
    }

    return FilterOption(
      slug: slug,
      label: label,
      count: DiscoveryFacets._int(json['count']) ?? 0,
    );
  }
}

/// A price band, 1 to 4, and how many stops declared it.
class PriceOption {
  const PriceOption({required this.level, required this.count});

  final int level;
  final int count;

  static PriceOption? fromJson(Map<String, dynamic> json) {
    final int? level = DiscoveryFacets._int(json['level']);

    if (level == null || level < 1 || level > 4) return null;

    return PriceOption(
      level: level,
      count: DiscoveryFacets._int(json['count']) ?? 0,
    );
  }
}

/// "Open now" or "Taking orders", with its count on this route.
class AvailabilityOption {
  const AvailabilityOption({
    required this.value,
    required this.label,
    required this.count,
  });

  final AvailabilityFilter value;
  final String label;
  final int count;

  static AvailabilityOption? fromJson(Map<String, dynamic> json) {
    final AvailabilityFilter? value = AvailabilityFilter.fromWire(
      json['value'] as String?,
    );

    if (value == null) return null;

    return AvailabilityOption(
      value: value,
      label: (json['label'] as String?) ?? '',
      count: DiscoveryFacets._int(json['count']) ?? 0,
    );
  }
}

/// A sort order, and whether it can be used yet.
class SortOption {
  const SortOption({
    required this.sort,
    required this.label,
    required this.isAvailable,
    this.unavailableReason,
  });

  final DiscoverySort sort;
  final String label;

  /// False for a sort the data cannot support — today, "highest rated", because
  /// nothing has a rating.
  final bool isAvailable;

  /// The server's own words for why. Shown beside the disabled option, because
  /// a greyed-out row with no explanation reads as a bug.
  final String? unavailableReason;

  static SortOption? fromJson(Map<String, dynamic> json) {
    final String? wire = json['value'] as String?;

    if (wire == null) return null;

    // An order this build has never heard of is dropped rather than rendered
    // with a blank label.
    final DiscoverySort sort = DiscoverySort.fromWire(wire);
    if (sort.wire != wire) return null;

    return SortOption(
      sort: sort,
      label: (json['label'] as String?) ?? '',
      isAvailable: json['available'] != false,
      unavailableReason: json['unavailable_reason'] as String?,
    );
  }
}
