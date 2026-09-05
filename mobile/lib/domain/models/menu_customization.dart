import 'money.dart';

/// One size or form of a dish.
///
/// The price is **absolute** — "Large ₹329" is what the dish costs, not what
/// it costs extra — which matches the server's column and means the screen
/// never has to add a base price to a delta to know what to show.
class MenuItemVariant {
  const MenuItemVariant({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.preparationMinutes,
    this.isDefault = false,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final String? description;

  final Money price;

  /// The kitchen may say a large one takes longer. Null means "same as the
  /// dish" — never a guess.
  final int? preparationMinutes;

  /// Preselected when the screen opens. Only where an operator configured it:
  /// the first row is not a default.
  final bool isDefault;

  /// False means sold out today. Shown, disabled — a customer who came for the
  /// family size learns why rather than wondering whether they misremembered.
  final bool isAvailable;

  static MenuItemVariant? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;
    final Money? price = Money.fromJson(json['price']);

    // A size with no price cannot be offered: the customer would be choosing
    // something nobody can quote.
    if (id == null || id.isEmpty) return null;
    if (name == null || name.trim().isEmpty) return null;
    if (price == null) return null;

    final String? description = (json['description'] as String?)?.trim();

    return MenuItemVariant(
      id: id,
      name: name.trim(),
      description: (description?.isNotEmpty ?? false) ? description : null,
      price: price,
      preparationMinutes: _positiveInt(json['preparation_minutes']),
      isDefault: json['is_default'] == true,
      isAvailable: json['is_available'] != false,
    );
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
}

/// One answer to a group's question.
///
/// The price is a **delta** — what choosing it adds — and never negative.
class MenuModifierOption {
  const MenuModifierOption({
    required this.id,
    required this.name,
    required this.priceDelta,
    this.description,
    this.isDefault = false,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final String? description;

  final Money priceDelta;

  /// Preselected when the screen opens.
  ///
  /// The server never marks a paid option as a default, whatever its column
  /// says — starting a customer at "Extra Cheese +₹40" and letting them find
  /// it at the total is a dark pattern. The client trusts that and does not
  /// re-derive it.
  final bool isDefault;

  final bool isAvailable;

  bool get isFree => priceDelta.isZero;

  static MenuModifierOption? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;
    final Money? delta = Money.fromJson(json['price_delta']);

    if (id == null || id.isEmpty) return null;
    if (name == null || name.trim().isEmpty) return null;
    if (delta == null) return null;

    final String? description = (json['description'] as String?)?.trim();

    return MenuModifierOption(
      id: id,
      name: name.trim(),
      description: (description?.isNotEmpty ?? false) ? description : null,
      priceDelta: delta,
      isDefault: json['is_default'] == true,
      isAvailable: json['is_available'] != false,
    );
  }
}

/// A question the kitchen asks about a dish, and its rule.
///
/// The rule arrives as two numbers rather than as prose, so the screen enforces
/// it without parsing English and a future locale does not have to translate a
/// rule to make it work.
class MenuModifierGroup {
  const MenuModifierGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
    this.description,
  });

  final String id;
  final String name;
  final String? description;

  /// How many must be chosen. Zero means the group may be left alone.
  final int minSelect;

  /// How many may be chosen.
  final int maxSelect;

  final List<MenuModifierOption> options;

  bool get isRequired => minSelect >= 1;

  /// Radios rather than checkboxes.
  bool get isSingleSelect => maxSelect <= 1;

  /// True when a customer must choose more than one — "choose 2 to 4".
  bool get hasRangeRule => minSelect > 1;

  /// The options the screen should start with chosen.
  List<String> get defaultOptionIds => <String>[
    for (final MenuModifierOption option in options)
      if (option.isDefault && option.isAvailable) option.id,
  ];

  static MenuModifierGroup? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;

    if (id == null || id.isEmpty) return null;
    if (name == null || name.trim().isEmpty) return null;

    final List<MenuModifierOption> options = <MenuModifierOption>[
      for (final Object? raw in (json['options'] as List<Object?>? ?? const []))
        if (raw is Map<String, dynamic>)
          if (MenuModifierOption.fromJson(raw) case final MenuModifierOption o)
            o,
    ];

    // A question with no answers is not a question. Drawing the heading would
    // leave a customer looking for controls that are not there.
    if (options.isEmpty) return null;

    final int min = _int(json['min_select']) ?? 0;
    final int max = _int(json['max_select']) ?? 1;

    final String? description = (json['description'] as String?)?.trim();

    return MenuModifierGroup(
      id: id,
      name: name.trim(),
      description: (description?.isNotEmpty ?? false) ? description : null,
      minSelect: min,
      // Never below the minimum. A group configured "at least 2, at most 1" is
      // unsatisfiable; raising the ceiling to meet the floor makes the screen
      // usable rather than permanently refusing.
      maxSelect: max < min ? min : max,
      options: options,
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// The limits the server will enforce, sent with the item.
///
/// Carried rather than hard-coded so the stepper and the note counter cannot
/// drift from what the server accepts.
class CustomizationLimits {
  const CustomizationLimits({
    this.maxQuantity = 20,
    this.maxSpecialInstructions = 300,
  });

  final int maxQuantity;
  final int maxSpecialInstructions;

  static CustomizationLimits fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const CustomizationLimits();

    return CustomizationLimits(
      maxQuantity: _int(json['max_quantity']) ?? 20,
      maxSpecialInstructions: _int(json['max_special_instructions']) ?? 300,
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// Everything a customer needs to configure one dish.
class MenuItemCustomization {
  const MenuItemCustomization({
    this.variants = const <MenuItemVariant>[],
    this.modifierGroups = const <MenuModifierGroup>[],
    this.requiresVariant = false,
    this.limits = const CustomizationLimits(),
  });

  final List<MenuItemVariant> variants;
  final List<MenuModifierGroup> modifierGroups;

  /// True when there are sizes and none of them is a usable default, so the
  /// customer must choose before the screen can quote a price.
  final bool requiresVariant;

  final CustomizationLimits limits;

  bool get hasVariants => variants.isNotEmpty;

  bool get hasAnything => hasVariants || modifierGroups.isNotEmpty;

  /// The size the screen opens on, or null.
  ///
  /// Never "the first one": a default is something an operator configured, and
  /// guessing means quoting a price nobody chose to show.
  MenuItemVariant? get defaultVariant {
    for (final MenuItemVariant variant in variants) {
      if (variant.isDefault && variant.isAvailable) return variant;
    }

    return null;
  }

  MenuItemVariant? variantById(String? id) {
    if (id == null) return null;

    for (final MenuItemVariant variant in variants) {
      if (variant.id == id) return variant;
    }

    return null;
  }

  MenuModifierOption? optionById(String id) {
    for (final MenuModifierGroup group in modifierGroups) {
      for (final MenuModifierOption option in group.options) {
        if (option.id == id) return option;
      }
    }

    return null;
  }

  MenuModifierGroup? groupOf(String optionId) {
    for (final MenuModifierGroup group in modifierGroups) {
      for (final MenuModifierOption option in group.options) {
        if (option.id == optionId) return group;
      }
    }

    return null;
  }

  static MenuItemCustomization fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const MenuItemCustomization();

    return MenuItemCustomization(
      variants: <MenuItemVariant>[
        for (final Object? raw
            in (json['variants'] as List<Object?>? ?? const []))
          if (raw is Map<String, dynamic>)
            if (MenuItemVariant.fromJson(raw) case final MenuItemVariant v) v,
      ],
      modifierGroups: <MenuModifierGroup>[
        for (final Object? raw
            in (json['modifier_groups'] as List<Object?>? ?? const []))
          if (raw is Map<String, dynamic>)
            if (MenuModifierGroup.fromJson(raw) case final MenuModifierGroup g)
              g,
      ],
      requiresVariant: json['requires_variant'] == true,
      limits: CustomizationLimits.fromJson(json['limits']),
    );
  }
}
