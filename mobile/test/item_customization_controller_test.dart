import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/menu_customization.dart';
import 'package:foodonthego/domain/models/money.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/shared/state/item_customization_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// The customization state machine.
///
/// Three things it exists to get right, and most of this file is about them:
/// the newest request wins, a retry does not add twice, and the price on the
/// button is a preview that the server's answer replaces.
void main() {
  late FakeMenuRepository menus;
  late ProviderContainer container;

  ProviderContainer build(FakeMenuRepository repository) {
    final ProviderContainer c = ProviderContainer(
      overrides: [menuRepositoryProvider.overrideWithValue(repository)],
    );

    // The provider auto-disposes and the screen keeps it alive; a test with no
    // listener would tear the controller down between one read and the next.
    c.listen(
      itemCustomizationControllerProvider,
      (CustomizationState? _, CustomizationState _) {},
      fireImmediately: true,
    );

    addTearDown(c.dispose);

    return c;
  }

  ItemCustomizationController controller() =>
      container.read(itemCustomizationControllerProvider.notifier);

  CustomizationState state() =>
      container.read(itemCustomizationControllerProvider);

  Future<void> openItem({
    MenuItemPreview? preview,
    FakeMenuRepository? repository,
  }) async {
    menus = repository ?? FakeMenuRepository();
    menus.previewToReturn = preview ?? sampleItemPreview();
    container = build(menus);

    await controller().open(
      tripId: 'trip-1',
      restaurantId: 'restaurant-1',
      itemId: 'item-1',
    );
  }

  MenuModifierGroup groupNamed(String name) => state()
      .customization
      .modifierGroups
      .firstWhere((MenuModifierGroup g) => g.name == name);

  MenuModifierOption optionNamed(String group, String name) =>
      groupNamed(group).options
          .firstWhere((MenuModifierOption o) => o.name == name);

  group('opening', () {
    test('starts on the configured default size and free defaults', () async {
      await openItem();

      expect(state().selectedVariant?.name, 'Regular');

      // No default is configured on the spice group in this fixture, so
      // nothing is preselected there.
      expect(state().selectedOptionIds, isEmpty);
    });

    test('preselects a configured free default option', () async {
      await openItem(
        preview: sampleItemPreview(
          customization: sampleCustomization(
            groups: const <MenuModifierGroup>[
              MenuModifierGroup(
                id: 'group-spice',
                name: 'Spice level',
                minSelect: 1,
                maxSelect: 1,
                options: <MenuModifierOption>[
                  MenuModifierOption(
                    id: 'option-mild',
                    name: 'Mild',
                    priceDelta: Money(amountMinor: 0, currency: 'INR'),
                    isDefault: true,
                  ),
                  MenuModifierOption(
                    id: 'option-hot',
                    name: 'Hot',
                    priceDelta: Money(amountMinor: 0, currency: 'INR'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(state().selectedOptionIds, <String>{'option-mild'});
      expect(state().isComplete, isTrue);
    });

    test('a dish with no sizes gets no size and no complaint', () async {
      await openItem(
        preview: sampleItemPreview(
          customization: sampleCustomization(
            withVariants: false,
            groups: const <MenuModifierGroup>[],
          ),
        ),
      );

      expect(state().customization.hasVariants, isFalse);
      expect(state().needsVariant, isFalse);
      expect(state().isComplete, isTrue);
    });

    test('a stale answer never overwrites a newer one', () async {
      menus = FakeMenuRepository(delay: const Duration(milliseconds: 80))
        ..previewToReturn = sampleItemPreview();
      container = build(menus);

      // A customer opening one dish, backing out, and opening another.
      final Future<void> first = controller().open(
        tripId: 'trip-1',
        restaurantId: 'restaurant-1',
        itemId: 'item-1',
      );

      menus.previewToReturn = sampleItemPreview(
        item: sampleMenuItem(id: 'item-2', name: 'Dal Makhani'),
      );

      final Future<void> second = controller().open(
        tripId: 'trip-1',
        restaurantId: 'restaurant-1',
        itemId: 'item-2',
      );

      await Future.wait(<Future<void>>[first, second]);

      expect(state().item?.name, 'Dal Makhani');
    });
  });

  group('choosing', () {
    test('a size replaces the price the button shows', () async {
      await openItem();

      expect(state().previewUnitPrice?.amountMinor, 24900);

      controller().selectVariant('variant-large');

      // Absolute, not additive: ₹329, not ₹578.
      expect(state().previewUnitPrice?.amountMinor, 32900);
    });

    test('a sold-out size cannot be chosen', () async {
      await openItem();

      controller().selectVariant('variant-family');

      expect(state().selectedVariant?.name, 'Regular');
    });

    test('a single-select group replaces rather than adds', () async {
      await openItem();

      final MenuModifierGroup spice = groupNamed('Spice level');

      controller()
        ..toggleOption(spice, optionNamed('Spice level', 'Mild'))
        ..toggleOption(spice, optionNamed('Spice level', 'Hot'));

      expect(state().selectedOptionIds, <String>{'option-hot'});
    });

    test('a multi-select group toggles', () async {
      await openItem();

      final MenuModifierGroup extras = groupNamed('Add extras');
      final MenuModifierOption cheese = optionNamed(
        'Add extras',
        'Extra Cheese',
      );

      controller().toggleOption(extras, cheese);
      expect(state().selectedOptionIds.contains('option-cheese'), isTrue);

      controller().toggleOption(extras, cheese);
      expect(state().selectedOptionIds.contains('option-cheese'), isFalse);
    });

    test('a paid option moves the price', () async {
      await openItem();

      controller()
        ..selectVariant('variant-large')
        ..toggleOption(
          groupNamed('Add extras'),
          optionNamed('Add extras', 'Extra Cheese'),
        );

      // 329 + 40.
      expect(state().previewUnitPrice?.amountMinor, 36900);

      controller().toggleOption(
        groupNamed('Add extras'),
        optionNamed('Add extras', 'Jalapeños'),
      );

      expect(state().previewUnitPrice?.amountMinor, 38900);
    });

    test('removing an option brings the price back down', () async {
      await openItem();

      final MenuModifierOption cheese = optionNamed(
        'Add extras',
        'Extra Cheese',
      );

      controller()
        ..toggleOption(groupNamed('Add extras'), cheese)
        ..toggleOption(groupNamed('Add extras'), cheese);

      expect(state().previewUnitPrice?.amountMinor, 24900);
    });

    test(
      'the ceiling refuses a third rather than dropping the first',
      () async {
        await openItem();

        final MenuModifierGroup extras = groupNamed('Add extras');

        controller()
          ..toggleOption(extras, optionNamed('Add extras', 'Extra Cheese'))
          ..toggleOption(extras, optionNamed('Add extras', 'Jalapeños'));

        expect(state().isFull(extras), isTrue);

        controller().toggleOption(
          extras,
          optionNamed('Add extras', 'Extra Paneer'),
        );

        // A customer who tapped three things and saw two should be told which
        // two, not left to work out which one silently went.
        expect(state().selectedOptionIds, <String>{
          'option-cheese',
          'option-jalapeno',
        });
      },
    );

    test('a sold-out option cannot be chosen', () async {
      await openItem();

      controller().toggleOption(
        groupNamed('Add extras'),
        optionNamed('Add extras', 'Extra Cashew'),
      );

      expect(state().selectedOptionIds, isEmpty);
    });
  });

  group('quantity', () {
    test('stops at one and at the server limit', () async {
      await openItem();

      expect(state().quantity, 1);
      expect(state().canDecrease, isFalse);

      controller().decreaseQuantity();
      expect(state().quantity, 1);

      for (int i = 0; i < 25; i++) {
        controller().increaseQuantity();
      }

      // The limit is the server's, carried with the item.
      expect(state().quantity, state().customization.limits.maxQuantity);
      expect(state().canIncrease, isFalse);
    });

    test('multiplies the line total', () async {
      await openItem();

      controller()
        ..selectVariant('variant-large')
        ..toggleOption(
          groupNamed('Add extras'),
          optionNamed('Add extras', 'Extra Cheese'),
        )
        ..increaseQuantity();

      expect(state().previewLineTotal?.amountMinor, 73800);
    });
  });

  group('the note', () {
    test('is clipped at the limit rather than refused', () async {
      await openItem();

      final int max = state().customization.limits.maxSpecialInstructions;

      controller().noteChanged('a' * (max + 50));

      // A customer who pastes a paragraph keeps the beginning of it.
      expect(state().specialInstructions.length, max);
      expect(state().noteRemaining, 0);
    });
  });

  group('validation before the request', () {
    test('an unanswered required group blocks and names itself', () async {
      await openItem();

      await controller().addToCart();

      expect(state().failure, AddToCartFailure.selectionIncomplete);
      expect(state().invalidGroupId, 'group-spice');
      expect(state().showValidation, isTrue);

      // Nothing went to the server: the customer has not finished.
      expect(menus.addCalls, 0);
    });

    test('nothing is marked before the customer has tried', () async {
      await openItem();

      // A screen that opens covered in red is telling somebody off for not
      // having started.
      expect(state().showValidation, isFalse);
      expect(state().unsatisfiedGroups.length, 1);
    });

    test('a required size with no default blocks', () async {
      await openItem(
        preview: sampleItemPreview(
          customization: sampleCustomization(
            variantDefault: false,
            requiresVariant: true,
            groups: const <MenuModifierGroup>[],
          ),
        ),
      );

      expect(state().needsVariant, isTrue);

      await controller().addToCart();

      expect(state().failure, AddToCartFailure.selectionIncomplete);
      expect(menus.addCalls, 0);
    });
  });

  group('adding', () {
    Future<void> completeConfiguration() async {
      controller()
        ..selectVariant('variant-large')
        ..toggleOption(
          groupNamed('Spice level'),
          optionNamed('Spice level', 'Mild'),
        );
    }

    test('sends selections and the quoted price, and no total', () async {
      await openItem();
      await completeConfiguration();

      await controller().addToCart();

      final request = menus.addRequests.single;

      expect(request.itemId, 'item-1');
      expect(request.variantId, 'variant-large');
      expect(request.optionIds, <String>['option-mild']);
      expect(request.quantity, 1);

      // What the screen showed, so the server can refuse to charge more.
      expect(request.quotedUnitPriceMinor, 32900);
    });

    test('the server figure replaces the preview', () async {
      await openItem();
      await completeConfiguration();

      // The kitchen dropped the price between load and add.
      menus.serverUnitPriceMinor = (int _) => 29900;

      await controller().addToCart();

      expect(state().addition?.unitPrice.amountMinor, 29900);
      expect(state().cart.itemCount, 1);
    });

    test('a second tap while one is in flight does nothing', () async {
      await openItem();
      await completeConfiguration();

      menus.addDelay = const Duration(milliseconds: 60);

      final Future<void> first = controller().addToCart();
      final Future<void> second = controller().addToCart();

      await Future.wait(<Future<void>>[first, second]);

      // One logical operation, whatever the finger did.
      expect(menus.addCalls, 1);
    });

    test('a retry after a lost response reuses the key', () async {
      await openItem();
      await completeConfiguration();

      // The first attempt reaches the server and the response is lost.
      menus.addErrorFor = (int attempt) =>
          attempt == 1 ? const ApiException.network() : null;

      await controller().addToCart();
      expect(state().failure, AddToCartFailure.network);

      await controller().retryAdd();

      expect(menus.addCalls, 2);

      // The same key both times, so the server treats the second as a replay
      // of the first rather than as a second order.
      expect(
        menus.addRequests[0].idempotencyKey,
        menus.addRequests[1].idempotencyKey,
      );
      expect(menus.addRequests[0].idempotencyKey, isNotNull);
    });

    test('a changed configuration gets a new key', () async {
      await openItem();
      await completeConfiguration();

      menus.addErrorFor = (int attempt) =>
          attempt == 1 ? const ApiException.network() : null;

      await controller().addToCart();

      // A different dish now — not a retry of the last one.
      controller().increaseQuantity();

      await controller().addToCart();

      expect(
        menus.addRequests[0].idempotencyKey,
        isNot(menus.addRequests[1].idempotencyKey),
      );
    });

    test('a successful add ends the retry window', () async {
      await openItem();
      await completeConfiguration();

      await controller().addToCart();
      await controller().addToCart();

      // The second is a new order, not a replay of the first.
      expect(
        menus.addRequests[0].idempotencyKey,
        isNot(menus.addRequests[1].idempotencyKey),
      );
    });

    test('a network failure keeps every selection', () async {
      await openItem();
      await completeConfiguration();

      controller()
        ..toggleOption(
          groupNamed('Add extras'),
          optionNamed('Add extras', 'Extra Cheese'),
        )
        ..increaseQuantity()
        ..noteChanged('No onion');

      menus.nextAddError = const ApiException.network();

      await controller().addToCart();

      // The customer does not customize it again because our network failed.
      expect(state().failure, AddToCartFailure.network);
      expect(state().selectedVariant?.name, 'Large');
      expect(state().selectedOptionIds.contains('option-cheese'), isTrue);
      expect(state().quantity, 2);
      expect(state().specialInstructions, 'No onion');
    });
  });

  group('the price change', () {
    Future<void> refuseOnPrice() async {
      menus.nextAddError = const ApiException(
        code: ApiErrorCode.priceUpdated,
        message: 'The price changed.',
        status: 409,
        details: <String, dynamic>{
          'current_unit_price': <String, dynamic>{
            'amount_minor': 35900,
            'currency': 'INR',
          },
        },
      );

      await controller().addToCart();
    }

    test('a higher price is refused with the new figure', () async {
      await openItem();

      controller()
        ..selectVariant('variant-large')
        ..toggleOption(
          groupNamed('Spice level'),
          optionNamed('Spice level', 'Mild'),
        );

      await refuseOnPrice();

      expect(state().failure, AddToCartFailure.priceChanged);
      expect(state().priceChangedTo?.amountMinor, 35900);

      // And nothing was added.
      expect(state().addition, isNull);
    });

    test('accepting it sends a fresh request with no quote', () async {
      await openItem();

      controller()
        ..selectVariant('variant-large')
        ..toggleOption(
          groupNamed('Spice level'),
          optionNamed('Spice level', 'Mild'),
        );

      await refuseOnPrice();
      await controller().acceptNewPrice();

      expect(menus.addCalls, 2);

      // No quote on the second: the customer has agreed to whatever the server
      // now says, and the server prices it from its own rows either way.
      expect(menus.addRequests[1].quotedUnitPriceMinor, isNull);
      expect(state().addition, isNotNull);
    });
  });

  group('failures are told apart', () {
    Future<void> failWith(ApiErrorCode code) async {
      await openItem();

      controller()
        ..selectVariant('variant-large')
        ..toggleOption(
          groupNamed('Spice level'),
          optionNamed('Spice level', 'Mild'),
        );

      menus.nextAddError = ApiException(
        code: code,
        message: 'Refused.',
        status: 409,
      );

      await controller().addToCart();
    }

    test('a sold-out race is its own state', () async {
      await failWith(ApiErrorCode.itemSoldOut);

      expect(state().failure, AddToCartFailure.soldOut);
    });

    test('an unavailable option is a sold-out race too', () async {
      await failWith(ApiErrorCode.modifierUnavailable);

      expect(state().failure, AddToCartFailure.soldOut);
    });

    test('a paused kitchen is its own state', () async {
      await failWith(ApiErrorCode.restaurantNotAcceptingOrders);

      expect(state().failure, AddToCartFailure.notAcceptingOrders);
    });

    test('a cart conflict is its own state', () async {
      await failWith(ApiErrorCode.cartRestaurantConflict);

      expect(state().failure, AddToCartFailure.cartConflict);
    });

    test('a quantity refusal is its own state', () async {
      await failWith(ApiErrorCode.quantityLimitExceeded);

      expect(state().failure, AddToCartFailure.quantityRefused);
    });
  });

  group('what the screen may offer', () {
    test('a sold-out dish is not orderable', () async {
      await openItem(
        preview: sampleItemPreview(
          item: sampleMenuItem(stockStatus: MenuItemStockStatus.soldOut),
        ),
      );

      expect(state().isOrderable, isFalse);
    });

    test('a paused restaurant is not orderable', () async {
      await openItem(
        preview: sampleItemPreview(
          ordering: RestaurantOrderingState.openPaused,
        ),
      );

      expect(state().isOrderable, isFalse);
    });
  });
}
