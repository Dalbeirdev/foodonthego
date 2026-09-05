import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/menu_customization.dart';

/// The customization models.
///
/// Most of these are about what the client refuses to invent: a default nobody
/// configured, a paid option preselected, a rule it made up because the server
/// sent a contradictory one.
void main() {
  Map<String, dynamic> variantJson(Map<String, dynamic> overrides) =>
      <String, dynamic>{
        'id': 'variant-1',
        'name': 'Large',
        'price': <String, dynamic>{'amount_minor': 32900, 'currency': 'INR'},
        ...overrides,
      };

  Map<String, dynamic> optionJson(Map<String, dynamic> overrides) =>
      <String, dynamic>{
        'id': 'option-1',
        'name': 'Extra Cheese',
        'price_delta': <String, dynamic>{
          'amount_minor': 4000,
          'currency': 'INR',
        },
        ...overrides,
      };

  Map<String, dynamic> groupJson(Map<String, dynamic> overrides) =>
      <String, dynamic>{
        'id': 'group-1',
        'name': 'Spice level',
        'min_select': 1,
        'max_select': 1,
        'options': <Map<String, dynamic>>[optionJson(<String, dynamic>{})],
        ...overrides,
      };

  group('a variant', () {
    test('carries an absolute price, not a delta', () {
      final MenuItemVariant? variant = MenuItemVariant.fromJson(
        variantJson(<String, dynamic>{}),
      );

      // ₹329 is what the dish costs in this size.
      expect(variant?.price.amountMinor, 32900);
    });

    test('a size with no readable price is dropped', () {
      // Offering it would ask the customer to choose something nobody can
      // quote.
      expect(
        MenuItemVariant.fromJson(variantJson(<String, dynamic>{'price': null})),
        isNull,
      );
    });

    test('an absurd preparation override is withheld', () {
      expect(
        MenuItemVariant.fromJson(
          variantJson(<String, dynamic>{'preparation_minutes': 0}),
        )?.preparationMinutes,
        isNull,
      );
    });
  });

  group('a modifier group', () {
    test('reads its rule as numbers', () {
      final MenuModifierGroup? group = MenuModifierGroup.fromJson(
        groupJson(<String, dynamic>{'min_select': 2, 'max_select': 4}),
      );

      expect(group?.minSelect, 2);
      expect(group?.maxSelect, 4);
      expect(group?.isRequired, isTrue);
      expect(group?.isSingleSelect, isFalse);
      expect(group?.hasRangeRule, isTrue);
    });

    test('a zero minimum is optional', () {
      final MenuModifierGroup? group = MenuModifierGroup.fromJson(
        groupJson(<String, dynamic>{'min_select': 0, 'max_select': 3}),
      );

      expect(group?.isRequired, isFalse);
    });

    test('a maximum below the minimum is raised to meet it', () {
      // "At least 2, at most 1" is unsatisfiable. Refusing every add on that
      // dish would be correct and useless; raising the ceiling makes the
      // screen work while an operator fixes their data.
      final MenuModifierGroup? group = MenuModifierGroup.fromJson(
        groupJson(<String, dynamic>{'min_select': 2, 'max_select': 1}),
      );

      expect(group?.maxSelect, 2);
    });

    test('a group with no options is not a question', () {
      expect(
        MenuModifierGroup.fromJson(
          groupJson(<String, dynamic>{'options': <Object?>[]}),
        ),
        isNull,
      );
    });

    test('only available defaults are preselected', () {
      final MenuModifierGroup? group = MenuModifierGroup.fromJson(
        groupJson(<String, dynamic>{
          'options': <Map<String, dynamic>>[
            optionJson(<String, dynamic>{
              'id': 'a',
              'is_default': true,
              'price_delta': <String, dynamic>{
                'amount_minor': 0,
                'currency': 'INR',
              },
            }),
            optionJson(<String, dynamic>{
              'id': 'b',
              'is_default': true,
              'is_available': false,
              'price_delta': <String, dynamic>{
                'amount_minor': 0,
                'currency': 'INR',
              },
            }),
          ],
        }),
      );

      // A default the kitchen has run out of is not a default.
      expect(group?.defaultOptionIds, <String>['a']);
    });
  });

  group('an option', () {
    test('a free option knows it is free', () {
      final MenuModifierOption? option = MenuModifierOption.fromJson(
        optionJson(<String, dynamic>{
          'price_delta': <String, dynamic>{
            'amount_minor': 0,
            'currency': 'INR',
          },
        }),
      );

      expect(option?.isFree, isTrue);
    });

    test('an option with no readable delta is dropped', () {
      expect(
        MenuModifierOption.fromJson(
          optionJson(<String, dynamic>{'price_delta': null}),
        ),
        isNull,
      );
    });
  });

  group('the whole customization', () {
    test('a dish with nothing configurable says so plainly', () {
      final MenuItemCustomization customization =
          MenuItemCustomization.fromJson(<String, dynamic>{
            'variants': <Object?>[],
            'modifier_groups': <Object?>[],
            'requires_variant': false,
          });

      // Empty lists, not a fabricated "Regular".
      expect(customization.hasVariants, isFalse);
      expect(customization.hasAnything, isFalse);
      expect(customization.defaultVariant, isNull);
    });

    test('the default is the configured one, never the first row', () {
      final MenuItemCustomization customization =
          MenuItemCustomization.fromJson(<String, dynamic>{
            'variants': <Map<String, dynamic>>[
              variantJson(<String, dynamic>{'id': 'a', 'name': 'Regular'}),
              variantJson(<String, dynamic>{
                'id': 'b',
                'name': 'Large',
                'is_default': true,
              }),
            ],
          });

      expect(customization.defaultVariant?.name, 'Large');
    });

    test('an unavailable default is no default at all', () {
      final MenuItemCustomization customization =
          MenuItemCustomization.fromJson(<String, dynamic>{
            'variants': <Map<String, dynamic>>[
              variantJson(<String, dynamic>{
                'id': 'a',
                'is_default': true,
                'is_available': false,
              }),
            ],
          });

      // Quoting a price for a size the kitchen cannot make would be worse than
      // asking.
      expect(customization.defaultVariant, isNull);
    });

    test('limits come from the server rather than from a constant', () {
      final MenuItemCustomization customization =
          MenuItemCustomization.fromJson(<String, dynamic>{
            'limits': <String, dynamic>{
              'max_quantity': 5,
              'max_special_instructions': 120,
            },
          });

      expect(customization.limits.maxQuantity, 5);
      expect(customization.limits.maxSpecialInstructions, 120);
    });

    test('an option can be found with the group that asked for it', () {
      final MenuItemCustomization customization =
          MenuItemCustomization.fromJson(<String, dynamic>{
            'modifier_groups': <Map<String, dynamic>>[
              groupJson(<String, dynamic>{}),
            ],
          });

      expect(customization.optionById('option-1')?.name, 'Extra Cheese');
      expect(customization.groupOf('option-1')?.name, 'Spice level');
      expect(customization.optionById('nope'), isNull);
    });
  });
}
