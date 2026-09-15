import 'discovered_restaurant.dart';

/// Whether a customer can proceed towards ordering, and why not if not.
///
/// Mirrors the server's `RestaurantOrderingState`. Deliberately not a boolean:
/// "you can't order" covers a restaurant shut until tomorrow, one that is open
/// with its kitchen paused, and one that has closed for good — three different
/// sentences and three different buttons.
enum RestaurantOrderingState {
  openAccepting('OPEN_ACCEPTING'),
  openPaused('OPEN_PAUSED'),
  closed('CLOSED'),
  closedPermanently('CLOSED_PERMANENTLY'),
  unavailable('UNAVAILABLE');

  const RestaurantOrderingState(this.wire);

  final String wire;

  static RestaurantOrderingState fromWire(String? value) {
    for (final RestaurantOrderingState s in RestaurantOrderingState.values) {
      if (s.wire == value) return s;
    }
    // A newer server naming a state this build has never heard of degrades to
    // "we do not know" rather than to a confident "go ahead and order".
    return RestaurantOrderingState.unavailable;
  }
}

/// One photograph of a restaurant.
class RestaurantImage {
  const RestaurantImage({
    required this.id,
    required this.url,
    required this.thumbnailUrl,
    this.altText,
    this.width,
    this.height,
  });

  final String id;
  final String url;
  final String thumbnailUrl;

  /// The operator's own caption, or null. A screen reader announcing "image 2
  /// of 5" tells a blind customer nothing about whether they want to eat here;
  /// an invented caption would be worse than the honest generic the screen
  /// falls back to.
  final String? altText;

  /// Intrinsic size where known, so the page can reserve the right box before
  /// the bytes arrive and does not jump when they do.
  final int? width;
  final int? height;

  double? get aspectRatio {
    final int? w = width;
    final int? h = height;

    if (w == null || h == null || w <= 0 || h <= 0) return null;

    return w / h;
  }

  static RestaurantImage? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    final String? url = json['url'] as String?;

    // An image with no address is not an image. Rendering it would put a
    // broken box on the screen.
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;

    return RestaurantImage(
      id: id,
      url: url,
      thumbnailUrl: (json['thumbnail_url'] as String?)?.isNotEmpty == true
          ? json['thumbnail_url'] as String
          : url,
      altText: (json['alt_text'] as String?)?.trim().isNotEmpty == true
          ? (json['alt_text'] as String).trim()
          : null,
      width: _int(json['width']),
      height: _int(json['height']),
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// One opening window, in the restaurant's own local time.
class OpeningWindow {
  const OpeningWindow({
    required this.opensAt,
    required this.closesAt,
    this.isOvernight = false,
  });

  /// `HH:mm:ss` as the restaurant wrote it. Formatted for display by the
  /// widget, never by the server: "8:00 AM" is a locale decision.
  final String opensAt;
  final String closesAt;

  /// Runs past midnight — 18:00 to 02:00. Worth saying out loud on the screen,
  /// because "18:00 – 02:00" read quickly looks like a typo.
  final bool isOvernight;

  static OpeningWindow? fromJson(Map<String, dynamic> json) {
    final String? opens = json['opens_at'] as String?;
    final String? closes = json['closes_at'] as String?;

    if (opens == null || closes == null) return null;

    return OpeningWindow(
      opensAt: opens,
      closesAt: closes,
      isOvernight: json['is_overnight'] == true,
    );
  }
}

/// One day of the week, and when the restaurant is open on it.
class DayHours {
  const DayHours({
    required this.dayOfWeek,
    required this.windows,
    this.isToday = false,
  });

  /// 0 = Monday … 6 = Sunday, matching the server's column.
  final int dayOfWeek;

  /// Empty means shut that day. A closed day is a row that says "Closed", not
  /// a row that is missing.
  final List<OpeningWindow> windows;

  final bool isToday;

  bool get isClosed => windows.isEmpty;

  static DayHours? fromJson(Map<String, dynamic> json) {
    final int? day = RestaurantImage._int(json['day_of_week']);

    if (day == null || day < 0 || day > 6) return null;

    return DayHours(
      dayOfWeek: day,
      isToday: json['is_today'] == true,
      windows: _windows(json['windows']),
    );
  }

  static List<OpeningWindow> _windows(Object? raw) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map(OpeningWindow.fromJson)
            .whereType<OpeningWindow>()
            .toList(growable: false)
      : const <OpeningWindow>[];
}

/// The opening schedule, as a customer reads it.
class RestaurantHours {
  const RestaurantHours({
    required this.timezone,
    this.today = const <OpeningWindow>[],
    this.week = const <DayHours>[],
    this.closesAt,
    this.nextOpenAt,
  });

  /// The restaurant's own zone. Shown when it differs from the device's, so a
  /// customer in another state is not misled by "opens at 8".
  final String timezone;

  final List<OpeningWindow> today;
  final List<DayHours> week;

  /// When the current window ends, if it is open. A real instant, so an
  /// overnight window closing at 02:00 means tomorrow morning.
  final DateTime? closesAt;

  /// When it opens again, if it is shut. Null also means "we don't know" — no
  /// hours on file — and the screen says nothing rather than guessing.
  final DateTime? nextOpenAt;

  bool get isOpenNow => closesAt != null;

  bool get hasSchedule => week.any((DayHours d) => d.windows.isNotEmpty);

  static RestaurantHours fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RestaurantHours(timezone: '');

    final Map<String, dynamic>? current =
        json['current_window'] as Map<String, dynamic>?;

    return RestaurantHours(
      timezone: (json['timezone'] as String?) ?? '',
      today: DayHours._windows(
        (json['today'] as Map<String, dynamic>?)?['windows'],
      ),
      week: _week(json['week']),
      closesAt: _time(current?['closes_at_utc']),
      nextOpenAt: _time(json['next_open_at']),
    );
  }

  static List<DayHours> _week(Object? raw) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map(DayHours.fromJson)
            .whereType<DayHours>()
            .toList(growable: false)
      : const <DayHours>[];

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// One restaurant, as a customer travelling a particular route sees it.
///
/// Two halves. The **profile** — name, description, photographs, cuisines,
/// facilities, hours — describes the business. The **route context**, carried
/// on [discovered], describes its relationship to this journey: how far ahead,
/// what stopping costs. The second is what makes this screen FoodOnTheGo's
/// rather than a generic restaurant page.
class RestaurantDetail {
  const RestaurantDetail({
    required this.restaurant,
    required this.ordering,
    required this.hours,
    required this.generatedAt,
    this.description,
    this.publicPhone,
    this.media = const <RestaurantImage>[],
    this.routeFromCache = false,
  });

  /// Everything the discovery card already knew, unchanged. Reusing it is what
  /// stops a card saying "4 min detour" and this screen saying "9 min".
  final DiscoveredRestaurant restaurant;

  final RestaurantOrderingState ordering;
  final RestaurantHours hours;

  /// When the server built this. What an offline screen uses to say how old
  /// what it is showing is, instead of implying the open sign is live.
  final DateTime generatedAt;

  /// The operator's own words, or null. Never generated, never inferred.
  final String? description;

  /// A published business number, if the operator has one. Never the owner's
  /// personal mobile, which is a different column and is not sent at all.
  final String? publicPhone;

  final List<RestaurantImage> media;

  /// Whether the route figures came from the discovery cache. True is the
  /// normal, cheap case; it is surfaced for the integration run rather than
  /// for the screen.
  final bool routeFromCache;

  String get id => restaurant.id;

  String get name => restaurant.name;

  bool get canOrder => ordering == RestaurantOrderingState.openAccepting;

  bool get hasMedia => media.isNotEmpty;

  bool get hasDescription => description != null;

  static RestaurantDetail? fromJson(Map<String, dynamic> json) {
    // The route relation is required. A restaurant with no position on this
    // journey is not something this screen can render honestly.
    final DiscoveredRestaurant? found = DiscoveredRestaurant.fromJson(json);

    if (found == null) return null;

    return RestaurantDetail(
      restaurant: found,
      ordering: RestaurantOrderingState.fromWire(
        (json['ordering'] as Map<String, dynamic>?)?['state'] as String?,
      ),
      hours: RestaurantHours.fromJson(json['hours'] as Map<String, dynamic>?),
      generatedAt:
          DateTime.tryParse((json['generated_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
      description: _text(json['description']),
      publicPhone: _text(json['public_phone']),
      media: _media(json['media']),
      routeFromCache: json['route_from_cache'] == true,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;

    final String trimmed = value.trim();

    return trimmed.isEmpty ? null : trimmed;
  }

  static List<RestaurantImage> _media(Object? raw) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map(RestaurantImage.fromJson)
            .whereType<RestaurantImage>()
            .toList(growable: false)
      : const <RestaurantImage>[];
}
