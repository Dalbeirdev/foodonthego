import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/features/menu/widgets/menu_category_selector.dart';
import 'package:foodonthego/features/menu/widgets/menu_item_card.dart';
import 'package:foodonthego/shared/state/menu_controller.dart';

import 'support/harness.dart';

/// The menu screen, as a customer meets it.
///
/// Most of these assertions are about what is *not* on the screen: a dish
/// without a description does not get one, an unphotographed dish does not
/// borrow somebody else's photograph, and nothing anywhere can be ordered.
void main() {
  Future<FakeMenuRepository> open(
    WidgetTester tester, {
    FakeMenuRepository? menus,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeMenuRepository repository = menus ?? FakeMenuRepository();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          routes: FakeRouteRepository(calculated: true),
          menus: repository,
          initialLocation:
              '/trips/trip-1/route/restaurants/restaurant-1/menu',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  /// Scrolls the list until [finder] has been built.
  ///
  /// The menu is a `ListView.builder`, so a dish below the fold is never built
  /// and has no widget at all — an assertion about it reports "not found"
  /// whether the app is right or wrong.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(
      MenuScreenController.searchDebounce + const Duration(milliseconds: 60),
    );
    await tester.pumpAndSettle();
  }

  group('a menu', () {
    testWidgets('shows the restaurant, its sections and its dishes', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Highway Spice Kitchen'), findsWidgets);
      expect(find.text('Starters'), findsWidgets);
      expect(find.text('Paneer Tikka'), findsOneWidget);
    });

    testWidgets('shows a price as the customer would read it', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // ₹249 rather than ₹249.00 — a menu of trailing zeroes reads like a
      // spreadsheet.
      expect(find.text('₹249'), findsOneWidget);
    });

    testWidgets('a price with paise keeps them', (WidgetTester tester) async {
      await open(tester);

      await scrollTo(tester, find.text('Paneer Butter Masala'));

      // ₹349.50 shown as ₹349 would be a lie about the price.
      expect(find.text('₹349.50'), findsOneWidget);
    });

    testWidgets('a free item is a price, not a blank', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Table Water'));

      expect(find.text('₹0'), findsOneWidget);
    });

    testWidgets('the operator ordered the sections, and so does the screen', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // `.last` is the heading; the first is the section chip of the same
      // name in the selector above.
      final double starters = tester.getTopLeft(find.text('Starters').last).dy;
      final double mains = tester.getTopLeft(find.text('Main Course').last).dy;

      expect(starters, lessThan(mains));
    });
  });

  group('what the screen does not invent', () {
    testWidgets('a dish with no description gets none', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // Chicken Seekh Kebab has no description in the fixture. The card shows
      // its name, its price and its badges — and no filler sentence.
      final Finder card = find.ancestor(
        of: find.text('Chicken Seekh Kebab'),
        matching: find.byType(MenuItemCard),
      );

      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(Text)),
        // Name, price, and the two badges it does have.
        findsNWidgets(4),
      );
    });

    testWidgets('a dish with no declared diet gets no badge', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Dal Makhani'));

      final Finder card = find.ancestor(
        of: find.text('Dal Makhani'),
        matching: find.byType(MenuItemCard),
      );

      // Dal Makhani is vegetarian to a reader and unknown to this app. Nobody
      // declared it, so nothing is claimed.
      expect(
        find.descendant(of: card, matching: find.text('Veg')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Non-veg')),
        findsNothing,
      );
    });

    testWidgets('a declared diet is shown as declared', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Veg'), findsOneWidget);
      expect(find.text('Non-veg'), findsOneWidget);
    });

    testWidgets('preparation time is not shown as a pickup time', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Paneer Tikka'));
      await tester.pumpAndSettle();

      // Worded so it cannot be read as when the food will be ready.
      expect(find.text('15 min to cook'), findsOneWidget);
      expect(find.textContaining('ready'), findsNothing);
      expect(find.textContaining('pickup'), findsNothing);
    });
  });

  group('availability', () {
    testWidgets('a sold-out dish is shown and labelled, not removed', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // A customer who came for one thing deserves to learn the kitchen has
      // run out, rather than to conclude they misremembered the menu.
      expect(find.text('Tandoori Mushroom'), findsOneWidget);
      expect(find.text('Sold out'), findsWidgets);
    });

    testWidgets('a closed restaurant still serves its menu, with a notice', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        menus: FakeMenuRepository(
          menuToReturn: sampleMenu(
            ordering: RestaurantOrderingState.closed,
          ),
        ),
      );

      expect(find.textContaining('Closed now'), findsOneWidget);
      expect(find.text('Paneer Tikka'), findsOneWidget);
    });

    testWidgets('a paused kitchen says so before a meal is chosen', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        menus: FakeMenuRepository(
          menuToReturn: sampleMenu(
            ordering: RestaurantOrderingState.openPaused,
          ),
        ),
      );

      expect(find.textContaining('Not taking orders'), findsOneWidget);
    });
  });

  group('searching', () {
    testWidgets('narrows the menu to what matches', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await type(tester, 'paneer');

      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('Chicken Seekh Kebab'), findsNothing);
    });

    testWidgets('a search that matches nothing is its own state', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await type(tester, 'pizza');

      expect(find.text('Nothing matched'), findsOneWidget);
      expect(find.textContaining('pizza'), findsWidgets);

      // A different problem from "no menu", and it offers the move that fixes
      // it.
      expect(find.text('No menu yet'), findsNothing);
      expect(find.text('Clear search'), findsOneWidget);
    });

    testWidgets('clearing the search brings the whole menu back', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await type(tester, 'pizza');
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('Paneer Tikka'), findsOneWidget);
    });

    testWidgets('the field cannot be typed past what the server accepts', (
      WidgetTester tester,
    ) async {
      await open(tester);

      final TextField field = tester.widget<TextField>(find.byType(TextField));

      expect(field.maxLength, 100);
    });
  });

  group('empty and error states', () {
    testWidgets('a restaurant with no menu says so, without an error', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        menus: FakeMenuRepository(menuToReturn: emptyMenu()),
      );

      expect(find.text('No menu yet'), findsOneWidget);
      expect(find.textContaining("hasn't published"), findsOneWidget);

      // Not a failure — a fact about the restaurant. No retry button.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('an outage offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = FakeMenuRepository()
        ..nextError = const ApiException(
          code: ApiErrorCode.serverError,
          message: 'Ours.',
          status: 500,
        );

      await open(tester, menus: menus);

      expect(find.textContaining("couldn't load this menu"), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Paneer Tikka'), findsOneWidget);
    });

    testWidgets('a withdrawn restaurant offers no retry', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = FakeMenuRepository()
        ..nextError = const ApiException(
          code: ApiErrorCode.restaurantUnavailable,
          message: 'Gone.',
          status: 404,
        );

      await open(tester, menus: menus);

      // It will not come back because the customer pressed a button.
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Back to restaurant'), findsOneWidget);
    });
  });

  group('the item preview', () {
    testWidgets('opens read-only, with no way to order', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Paneer Tikka'));
      await tester.pumpAndSettle();

      expect(find.text('Ordering opens soon'), findsOneWidget);

      // Module 10 ends at browsing. Not a disabled button — no button.
      expect(find.textContaining('Add to cart'), findsNothing);
      expect(find.textContaining('Add to bag'), findsNothing);
      expect(find.byType(Stepper), findsNothing);
    });

    testWidgets('shows the description in full where the card clipped it', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Paneer Tikka'));
      await tester.pumpAndSettle();

      expect(find.text('Cottage cheese in the tandoor.'), findsWidgets);
    });

    testWidgets('asks the server rather than echoing the card', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await open(tester);

      await tester.tap(find.text('Paneer Tikka'));
      await tester.pumpAndSettle();

      // A customer may have had the menu open for ten minutes.
      expect(menus.itemCalls, 1);
      expect(menus.itemRequests.single, 'item-1');
    });

    testWidgets('an item withdrawn since the list was drawn says so', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await open(tester);

      menus.nextItemError = const ApiException(
        code: ApiErrorCode.itemNotFound,
        message: 'Gone.',
        status: 404,
      );

      await tester.tap(find.text('Paneer Tikka'));
      await tester.pumpAndSettle();

      expect(find.text('No longer on the menu'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('sections', () {
    testWidgets('several sections get a selector', (WidgetTester tester) async {
      await open(tester);

      expect(find.byType(ChoiceChip), findsNWidgets(3));
    });

    testWidgets('one section is not a choice, so there is no selector', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        menus: FakeMenuRepository(
          menuToReturn: sampleMenu(
            categories: <MenuCategory>[
              MenuCategory(
                id: 'category-1',
                name: 'Everything',
                items: <MenuItem>[sampleMenuItem()],
              ),
            ],
          ),
        ),
      );

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('tapping a section takes the customer to it', (
      WidgetTester tester,
    ) async {
      await open(tester);

      final Finder chip = find.widgetWithText(ChoiceChip, 'Beverages');

      // The third chip is clipped at the right edge of a 390pt phone, exactly
      // as it is for a customer. Brought into view first, which is what the
      // selector's own horizontal scroll is for.
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();

      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.text('Table Water'), findsOneWidget);
    });

    testWidgets('a section far down a long menu can still be reached', (
      WidgetTester tester,
    ) async {
      await open(tester, menus: FakeMenuRepository(menuToReturn: largeMenu()));

      final Finder chip = find.widgetWithText(ChoiceChip, 'Section 14');

      // The selector is a lazy horizontal list, so a chip fourteen along has
      // not been built either. Scrolled to exactly as a customer would.
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.descendant(
          of: find.byType(MenuCategorySelector),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(chip);
      await tester.pumpAndSettle();

      // Section 14's heading was never built when the chip was tapped — three
      // hundred dishes above it had not been laid out. A selector that only
      // worked for the sections already on screen would be useless on exactly
      // the menus it exists for.
      expect(find.text('Section 14'), findsWidgets);
      expect(find.text('Section 14 Dish 1'), findsOneWidget);
    });

    testWidgets('a twenty-section menu builds only what is on screen', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        menus: FakeMenuRepository(menuToReturn: largeMenu()),
      );

      // Five hundred dishes in the menu; a dozen cards built. A screen that
      // built all five hundred would take seconds to open on the phone this
      // app is used on.
      expect(
        tester.widgetList<MenuItemCard>(find.byType(MenuItemCard)).length,
        lessThan(30),
      );

      // The selector is lazy for the same reason.
      expect(
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).length,
        lessThan(20),
      );
    });
  });

  group('accessibility', () {
    testWidgets('a dish is announced with its diet, price and availability', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // Not "button" three hundred times — and the diet is in the sentence,
      // because the card merges its children and a badge with its own node
      // would be a badge nobody hears.
      expect(
        find.bySemanticsLabel('Paneer Tikka. Veg. 249 rupees'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Tandoori Mushroom.*Sold out')),
        findsOneWidget,
      );
    });

    testWidgets('a dish nobody declared a diet for claims none', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Dal Makhani'));

      // Vegetarian to a reader, unknown to this app. The sentence goes
      // straight from the name to the price.
      expect(
        find.bySemanticsLabel('Dal Makhani. 299 rupees'),
        findsOneWidget,
      );
    });

    testWidgets('a declared spice level is announced, and only then', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(
        find.bySemanticsLabel(
          RegExp('Chicken Seekh Kebab.*Spice level: Medium'),
        ),
        findsOneWidget,
      );

      // Paneer Tikka has no spice level in the fixture.
      expect(
        find.bySemanticsLabel(RegExp('Paneer Tikka.*Spice level')),
        findsNothing,
      );
    });

    testWidgets('a section chip says what it does', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // A row of bare words tells a screen-reader user nothing about what
      // tapping one would do.
      expect(find.bySemanticsLabel('Jump to Beverages'), findsOneWidget);
    });

    testWidgets('the cooking time carries its own disclaimer', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Paneer Tikka'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('not a pickup time')),
        findsOneWidget,
      );
    });

    testWidgets('the screen survives the largest text a phone offers', (
      WidgetTester tester,
    ) async {
      await open(tester, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('Paneer Tikka'), findsOneWidget);
    });
  });
}
