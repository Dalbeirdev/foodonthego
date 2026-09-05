import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/money.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';

/// Money, and the menu models it lives in.
///
/// Most of these are about what the app refuses to do: guess a diet, invent a
/// spice level, round a price it cannot read, or render a dish it cannot price.
void main() {
  group('money', () {
    test('reads minor units and their currency', () {
      final Money? money = Money.fromJson(<String, dynamic>{
        'amount_minor': 24900,
        'currency': 'INR',
      });

      expect(money?.amountMinor, 24900);
      expect(money?.currency, 'INR');
    });

    test('a decimal amount is refused rather than rounded', () {
      // A double here means the server has started sending rupees. Rounding it
      // would introduce exactly the error integer minor units exist to
      // prevent, so the price is unreadable and the item is dropped.
      expect(
        Money.fromJson(<String, dynamic>{
          'amount_minor': 249.5,
          'currency': 'INR',
        }),
        isNull,
      );
    });

    test('a negative amount is refused', () {
      expect(
        Money.fromJson(<String, dynamic>{
          'amount_minor': -100,
          'currency': 'INR',
        }),
        isNull,
      );
    });

    test('a missing or malformed currency is refused', () {
      expect(Money.fromJson(<String, dynamic>{'amount_minor': 100}), isNull);
      expect(
        Money.fromJson(<String, dynamic>{
          'amount_minor': 100,
          'currency': 'RUPEES',
        }),
        isNull,
      );
    });

    test('zero is a price, not a missing one', () {
      final Money? money = Money.fromJson(<String, dynamic>{
        'amount_minor': 0,
        'currency': 'INR',
      });

      expect(money, isNotNull);
      expect(money!.isZero, isTrue);
    });

    test('a whole amount loses its decimals and a part amount keeps them', () {
      const Money whole = Money(amountMinor: 24900, currency: 'INR');
      const Money part = Money(amountMinor: 24950, currency: 'INR');

      expect(whole.isWhole, isTrue);
      expect(whole.format(locale: 'en_IN'), '₹249');

      expect(part.isWhole, isFalse);
      expect(part.format(locale: 'en_IN'), '₹249.50');
    });

    test('a currency with no minor unit is not divided by a hundred', () {
      // ¥500 is five hundred yen. Treating it as ¥5.00 is a hundredfold error.
      const Money yen = Money(amountMinor: 500, currency: 'JPY');

      expect(yen.subunits, 1);
      expect(yen.decimalDigits, 0);
      expect(yen.format(locale: 'en_US'), contains('500'));
    });

    test('the symbol comes from the locale, not from the code', () {
      const Money money = Money(amountMinor: 24900, currency: 'USD');

      expect(money.format(locale: 'en_US'), r'$249');
    });

    test('a screen reader hears the currency as a word', () {
      const Money money = Money(amountMinor: 24900, currency: 'INR');

      expect(money.spokenLabel(locale: 'en_IN'), '249 rupees');
    });

    test('two currencies cannot be compared', () {
      const Money rupees = Money(amountMinor: 400, currency: 'INR');
      const Money yen = Money(amountMinor: 500, currency: 'JPY');

      expect(() => rupees.compareTo(yen), throwsArgumentError);
    });
  });

  group('a menu item', () {
    Map<String, dynamic> json(Map<String, dynamic> overrides) =>
        <String, dynamic>{
          'id': 'item-1',
          'category_id': 'category-1',
          'name': 'Paneer Tikka',
          'price': <String, dynamic>{'amount_minor': 24900, 'currency': 'INR'},
          'stock_status': 'IN_STOCK',
          'is_orderable': true,
          ...overrides,
        };

    test('reads what the restaurant published', () {
      final MenuItem? item = MenuItem.fromJson(
        json(<String, dynamic>{
          'description': 'Cottage cheese in the tandoor.',
          'preparation_minutes': 15,
          'dietary_type': 'VEGETARIAN',
          'spice_level': 2,
        }),
      );

      expect(item?.name, 'Paneer Tikka');
      expect(item?.description, 'Cottage cheese in the tandoor.');
      expect(item?.preparationMinutes, 15);
      expect(item?.dietaryType, MenuItemDietaryType.vegetarian);
      expect(item?.spiceLevel, 2);
    });

    test('an item with no readable price is dropped, not shown at zero', () {
      expect(
        MenuItem.fromJson(json(<String, dynamic>{'price': null})),
        isNull,
      );
    });

    test('a missing description is null and never generated', () {
      final MenuItem? item = MenuItem.fromJson(json(<String, dynamic>{}));

      expect(item?.description, isNull);
      expect(item?.hasDescription, isFalse);
    });

    test('an empty description is treated as none', () {
      final MenuItem? item = MenuItem.fromJson(
        json(<String, dynamic>{'description': '   '}),
      );

      expect(item?.description, isNull);
    });

    test('the dietary wire strings are the ones the server sends', () {
      // Spelled out rather than derived, because an abbreviation compiles,
      // passes every fixture-built widget test, and silently drops every badge
      // against the real API. This is the assertion that would have caught it.
      expect(
        MenuItemDietaryType.values
            .where((MenuItemDietaryType t) => t.isKnown)
            .map((MenuItemDietaryType t) => t.wire),
        <String>['VEGETARIAN', 'NON_VEGETARIAN', 'VEGAN', 'EGG'],
      );

      expect(
        MenuItem.fromJson(
          json(<String, dynamic>{'dietary_type': 'NON_VEGETARIAN'}),
        )?.dietaryType,
        MenuItemDietaryType.nonVegetarian,
      );
    });

    test('an unknown dietary type is unknown, not one of the four', () {
      // A newer server naming a diet this build has not heard of. Shown as
      // nothing, which is honest, rather than as the nearest guess.
      final MenuItem? item = MenuItem.fromJson(
        json(<String, dynamic>{'dietary_type': 'JAIN'}),
      );

      expect(item?.dietaryType, MenuItemDietaryType.unknown);
      expect(item?.dietaryType.isKnown, isFalse);
    });

    test('a spice level outside the scale is withheld', () {
      expect(
        MenuItem.fromJson(json(<String, dynamic>{'spice_level': 9}))?.spiceLevel,
        isNull,
      );
    });

    test('a zero or negative preparation time is withheld', () {
      expect(
        MenuItem.fromJson(
          json(<String, dynamic>{'preparation_minutes': 0}),
        )?.preparationMinutes,
        isNull,
      );
    });

    test('an unknown stock status is not orderable', () {
      final MenuItem? item = MenuItem.fromJson(
        json(<String, dynamic>{'stock_status': 'ON_BACKORDER'}),
      );

      expect(item?.stockStatus, MenuItemStockStatus.soldOut);
      expect(item?.isSoldOut, isTrue);
    });

    test('a thumbnail falls back to the full image, and then to nothing', () {
      expect(
        MenuItem.fromJson(
          json(<String, dynamic>{'image_url': 'https://cdn.test/a.jpg'}),
        )?.listImageUrl,
        'https://cdn.test/a.jpg',
      );

      // No photograph at all. The card draws a monogram rather than somebody
      // else's food.
      expect(MenuItem.fromJson(json(<String, dynamic>{}))?.listImageUrl, isNull);
    });
  });

  group('a whole menu', () {
    Map<String, dynamic> body({
      List<Map<String, dynamic>> categories = const [],
      int itemCount = 0,
      int visibleItemCount = 0,
      String? search,
    }) => <String, dynamic>{
        'restaurant': <String, dynamic>{
          'id': 'restaurant-1',
          'name': 'Highway Spice Kitchen',
          'ordering': <String, dynamic>{
            'state': 'OPEN_ACCEPTING',
            'can_order': true,
            'can_browse_menu': true,
          },
        },
        'categories': categories,
        'meta': <String, dynamic>{
          'item_count': itemCount,
          'visible_item_count': visibleItemCount,
          'applied': <String, dynamic>{'search': search},
        },
    };

    Map<String, dynamic> category(String id, String name, int items) =>
        <String, dynamic>{
          'id': id,
          'name': name,
          'items': <Map<String, dynamic>>[
            for (int i = 1; i <= items; i++)
              <String, dynamic>{
                'id': '$id-item-$i',
                'category_id': id,
                'name': '$name dish $i',
                'price': <String, dynamic>{
                  'amount_minor': 10000 + i,
                  'currency': 'INR',
                },
                'stock_status': 'IN_STOCK',
                'is_orderable': true,
              },
          ],
        };

    test('reads categories and their items in the order they arrived', () {
      final RestaurantMenu? menu = RestaurantMenu.fromJson(
        body(
          categories: <Map<String, dynamic>>[
            category('category-1', 'Starters', 2),
            category('category-2', 'Mains', 1),
          ],
          itemCount: 3,
          visibleItemCount: 3,
        ),
      );

      expect(menu?.categories.map((MenuCategory c) => c.name), <String>[
        'Starters',
        'Mains',
      ]);
      expect(menu?.allItems.length, 3);
    });

    test('an empty category is not drawn', () {
      final RestaurantMenu? menu = RestaurantMenu.fromJson(
        body(
          categories: <Map<String, dynamic>>[
            category('category-1', 'Starters', 1),
            category('category-2', 'Desserts', 0),
          ],
          itemCount: 1,
          visibleItemCount: 1,
        ),
      );

      // "Desserts — no items" answers a question nobody asked.
      expect(menu?.categories.length, 1);
    });

    test('a restaurant with no menu is distinguished from an empty search', () {
      final RestaurantMenu? noMenu = RestaurantMenu.fromJson(body());

      expect(noMenu?.isMenuEmpty, isTrue);
      expect(noMenu?.isSearchEmpty, isFalse);

      final RestaurantMenu? noResults = RestaurantMenu.fromJson(
        body(itemCount: 0, visibleItemCount: 18, search: 'pizza'),
      );

      // The same empty list of categories, and a different problem: the
      // customer's next move is to clear the box, not to leave.
      expect(noResults?.isMenuEmpty, isFalse);
      expect(noResults?.isSearchEmpty, isTrue);
      expect(noResults?.appliedSearch, 'pizza');
    });

    test('a payload with no restaurant reads as nothing', () {
      // A 200 whose body cannot be read is a contract change, not a menu with
      // half a restaurant.
      expect(
        RestaurantMenu.fromJson(<String, dynamic>{'categories': <Object?>[]}),
        isNull,
      );
    });
  });
}
