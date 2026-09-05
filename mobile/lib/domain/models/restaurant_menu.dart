import 'money.dart';
import 'restaurant_detail.dart' show RestaurantOrderingState;

/// What a kitchen says about an item's diet.
///
/// Read from a structured field and never inferred. "Paneer Tikka" is
/// vegetarian to a reader and unknown to this app, because the one time the
/// guess is wrong it is served to somebody whose religion or health depended on
/// it. [unknown] renders nothing at all rather than a hedge.
enum MenuItemDietaryType {
  // The wire strings are the server's `App\Enums\MenuItemDietaryType` values,
  // spelled exactly. An abbreviation here would compile, pass every widget
  // test built on fixtures, and silently drop every badge in production.
  vegetarian('VEGETARIAN'),
  nonVegetarian('NON_VEGETARIAN'),
  vegan('VEGAN'),
  egg('EGG'),
  unknown('');

  const MenuItemDietaryType(this.wire);

  final String wire;

  bool get isKnown => this != MenuItemDietaryType.unknown;

  static MenuItemDietaryType fromWire(Object? value) {
    if (value is! String || value.isEmpty) return MenuItemDietaryType.unknown;

    for (final MenuItemDietaryType type in MenuItemDietaryType.values) {
      if (type.wire == value) return type;
    }

    // A newer server naming a diet this build has not heard of. Shown as
    // nothing, which is the honest answer, rather than as one of the four it
    // does know.
    return MenuItemDietaryType.unknown;
  }
}

/// Whether the kitchen still has it.
enum MenuItemStockStatus {
  inStock('IN_STOCK'),
  soldOut('SOLD_OUT');

  const MenuItemStockStatus(this.wire);

  final String wire;

  static MenuItemStockStatus fromWire(Object? value) {
    for (final MenuItemStockStatus status in MenuItemStockStatus.values) {
      if (status.wire == value) return status;
    }

    // Unknown means not orderable. The failure that matters here is taking
    // money for something the kitchen cannot make.
    return MenuItemStockStatus.soldOut;
  }
}

/// One dish.
///
/// Every optional field is genuinely optional, and a missing one renders
/// nothing. There is no placeholder description, no stock photograph standing
/// in for a dish nobody photographed, no inferred spice level and no invented
/// allergen list. A menu that says less than it knows is a menu a customer can
/// trust.
class MenuItem {
  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.stockStatus,
    required this.isOrderable,
    this.description,
    this.imageUrl,
    this.thumbnailUrl,
    this.preparationMinutes,
    this.dietaryType = MenuItemDietaryType.unknown,
    this.spiceLevel,
  });

  final String id;
  final String categoryId;
  final String name;

  final Money price;

  /// The operator's own words, or null. Never generated.
  final String? description;

  final String? imageUrl;
  final String? thumbnailUrl;

  /// How long the kitchen says this dish takes.
  ///
  /// Item metadata, and **not** a pickup time: it says nothing about the queue
  /// ahead of the customer, the drive to the restaurant, or when an order
  /// placed now would be ready. The screen labels it accordingly.
  final int? preparationMinutes;

  final MenuItemDietaryType dietaryType;

  /// 0–3 as the operator set it, or null. Never inferred from a name: a dish
  /// called "Fiery Chicken" may be mild, and a customer who cannot eat chilli
  /// deserves a blank rather than a guess.
  final int? spiceLevel;

  final MenuItemStockStatus stockStatus;

  /// The server's own verdict. Trusted over any reconstruction from the fields
  /// above, so a future reason to withhold an item needs no client release.
  final bool isOrderable;

  bool get isSoldOut => stockStatus == MenuItemStockStatus.soldOut;

  bool get hasDescription => (description?.isNotEmpty ?? false);

  /// The image to draw in a list. Falls back to the full one; null means the
  /// dish has no photograph and the card shows a monogram instead of somebody
  /// else's food.
  String? get listImageUrl {
    final String? thumb = thumbnailUrl;

    if (thumb != null && thumb.isNotEmpty) return thumb;

    final String? full = imageUrl;

    return (full != null && full.isNotEmpty) ? full : null;
  }

  static MenuItem? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;
    final Money? price = Money.fromJson(json['price']);

    // An item with no id, no name or no readable price is dropped rather than
    // half-drawn. A row reading "— · ₹0" invites a customer to order something
    // nobody can price.
    if (id == null || id.isEmpty) return null;
    if (name == null || name.trim().isEmpty) return null;
    if (price == null) return null;

    final String? description = (json['description'] as String?)?.trim();

    return MenuItem(
      id: id,
      categoryId: (json['category_id'] as String?) ?? '',
      name: name.trim(),
      price: price,
      description: (description?.isNotEmpty ?? false) ? description : null,
      imageUrl: _url(json['image_url']),
      thumbnailUrl: _url(json['thumbnail_url']),
      preparationMinutes: _positiveInt(json['preparation_minutes']),
      dietaryType: MenuItemDietaryType.fromWire(json['dietary_type']),
      spiceLevel: _spiceLevel(json['spice_level']),
      stockStatus: MenuItemStockStatus.fromWire(json['stock_status']),
      isOrderable: json['is_orderable'] == true,
    );
  }

  static String? _url(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;

    return value.trim();
  }

  static int? _positiveInt(Object? value) {
    final int? parsed = switch (value) {
      final int v => v,
      final num v => v.round(),
      final String v => int.tryParse(v),
      _ => null,
    };

    return (parsed != null && parsed > 0) ? parsed : null;
  }

  static int? _spiceLevel(Object? value) {
    final int? parsed = switch (value) {
      final int v => v,
      final num v => v.round(),
      final String v => int.tryParse(v),
      _ => null,
    };

    // Outside the scale the app can draw. Shown as nothing rather than clamped
    // to "mild", which would be a claim about the dish.
    if (parsed == null || parsed < 0 || parsed > 3) return null;

    return parsed;
  }
}

/// One section of a menu, with the items a customer may see in it.
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    required this.items,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final List<MenuItem> items;

  bool get isEmpty => items.isEmpty;

  static MenuCategory? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;

    if (id == null || id.isEmpty) return null;
    if (name == null || name.trim().isEmpty) return null;

    final List<MenuItem> items = <MenuItem>[
      for (final Object? raw in (json['items'] as List<Object?>? ?? const []))
        if (raw is Map<String, dynamic>)
          if (MenuItem.fromJson(raw) case final MenuItem item) item,
    ];

    final String? description = (json['description'] as String?)?.trim();

    return MenuCategory(
      id: id,
      name: name.trim(),
      description: (description?.isNotEmpty ?? false) ? description : null,
      items: items,
    );
  }
}

/// The header the menu screen draws: who this menu belongs to, and whether an
/// order could be placed with them right now.
class MenuRestaurantHeader {
  const MenuRestaurantHeader({
    required this.id,
    required this.name,
    required this.ordering,
    this.canOrder = false,
    this.canBrowseMenu = true,
  });

  final String id;
  final String name;
  final RestaurantOrderingState ordering;

  /// Whether the server would accept an order. Module 10 places none — this
  /// drives what the screen *says*, so a customer browsing a closed kitchen at
  /// midnight is told before they have chosen a meal rather than after.
  final bool canOrder;

  final bool canBrowseMenu;

  static MenuRestaurantHeader? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;

    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;

    final Object? ordering = json['ordering'];
    final Map<String, dynamic> o = ordering is Map<String, dynamic>
        ? ordering
        : const <String, dynamic>{};

    return MenuRestaurantHeader(
      id: id,
      name: name,
      ordering: RestaurantOrderingState.fromWire(o['state'] as String?),
      canOrder: o['can_order'] == true,
      canBrowseMenu: o['can_browse_menu'] != false,
    );
  }
}

/// A whole menu, as one restaurant serves it now.
class RestaurantMenu {
  const RestaurantMenu({
    required this.restaurant,
    required this.categories,
    required this.itemCount,
    required this.visibleItemCount,
    required this.generatedAt,
    this.appliedSearch,
  });

  final MenuRestaurantHeader restaurant;
  final List<MenuCategory> categories;

  /// How many items came back — after any search.
  final int itemCount;

  /// How many the restaurant is showing in total, before the search.
  ///
  /// The pair is what tells the two empty states apart, and they need
  /// different words: "this restaurant has not published a menu" sends the
  /// customer back to the list, while "nothing matched 'pizza'" asks them to
  /// clear the box.
  final int visibleItemCount;

  final String? appliedSearch;

  final DateTime generatedAt;

  /// The restaurant has published nothing a customer may see.
  bool get isMenuEmpty => visibleItemCount == 0;

  /// There is a menu; this search found none of it.
  bool get isSearchEmpty => visibleItemCount > 0 && itemCount == 0;

  bool get hasItems => itemCount > 0;

  /// Every visible item, in menu order. Used by the search-result count and by
  /// tests; the screen itself draws sections.
  List<MenuItem> get allItems => <MenuItem>[
    for (final MenuCategory category in categories) ...category.items,
  ];

  /// Reads the payload the API client hands over — which is the contents of
  /// the envelope's `data`, already unwrapped.
  static RestaurantMenu? fromJson(Map<String, dynamic> data) {
    final MenuRestaurantHeader? restaurant = MenuRestaurantHeader.fromJson(
      data['restaurant'],
    );

    if (restaurant == null) return null;

    final List<MenuCategory> categories = <MenuCategory>[
      for (final Object? raw
          in (data['categories'] as List<Object?>? ?? const []))
        if (raw is Map<String, dynamic>)
          if (MenuCategory.fromJson(raw) case final MenuCategory c)
            // A category the server sent with nothing readable in it is not
            // drawn: an empty heading answers a question nobody asked.
            if (!c.isEmpty) c,
    ];

    final Object? meta = data['meta'];
    final Map<String, dynamic> m = meta is Map<String, dynamic>
        ? meta
        : const <String, dynamic>{};

    final Object? applied = m['applied'];
    final String? search = applied is Map<String, dynamic>
        ? (applied['search'] as String?)
        : null;

    return RestaurantMenu(
      restaurant: restaurant,
      categories: categories,
      itemCount: _int(m['item_count']) ?? _countOf(categories),
      visibleItemCount: _int(m['visible_item_count']) ?? _countOf(categories),
      appliedSearch: (search?.isNotEmpty ?? false) ? search : null,
      generatedAt:
          DateTime.tryParse((m['generated_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  static int _countOf(List<MenuCategory> categories) =>
      categories.fold(0, (int sum, MenuCategory c) => sum + c.items.length);

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// One item, read on its own.
///
/// Fetched fresh rather than carried over from the list: a customer may have
/// had the menu open for ten minutes, and a preview echoing the payload it was
/// opened from would show a price that has since changed.
class MenuItemPreview {
  const MenuItemPreview({
    required this.item,
    required this.restaurant,
    required this.categoryName,
    required this.generatedAt,
  });

  final MenuItem item;
  final MenuRestaurantHeader restaurant;
  final String categoryName;
  final DateTime generatedAt;

  static MenuItemPreview? fromJson(Map<String, dynamic> data) {
    final Object? rawItem = data['item'];

    if (rawItem is! Map<String, dynamic>) return null;

    final MenuItem? item = MenuItem.fromJson(rawItem);
    final MenuRestaurantHeader? restaurant = MenuRestaurantHeader.fromJson(
      data['restaurant'],
    );

    if (item == null || restaurant == null) return null;

    final Object? category = data['category'];
    final String name = category is Map<String, dynamic>
        ? ((category['name'] as String?) ?? '')
        : '';

    return MenuItemPreview(
      item: item,
      restaurant: restaurant,
      categoryName: name,
      generatedAt:
          DateTime.tryParse(
            (data['generated_at'] as String?) ?? '',
          )?.toLocal() ??
          DateTime.now(),
    );
  }
}
