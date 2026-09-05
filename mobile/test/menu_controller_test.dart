import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/shared/state/menu_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// The menu controller, without a widget tree.
///
/// Most of this file is about a customer typing faster than a network answers:
/// three keystrokes produce three requests that can return in any order, and
/// without the generation check the slowest one lands last.
void main() {
  ProviderContainer containerWith(FakeMenuRepository menus) {
    // The list type is inferred: `Override` is not exported from
    // flutter_riverpod, and importing it from a transitive package to write an
    // annotation the compiler can work out itself is not worth the coupling.
    final ProviderContainer container = ProviderContainer(
      overrides: [menuRepositoryProvider.overrideWithValue(menus)],
    );

    // The provider auto-disposes and the screen keeps it alive; a test with no
    // listener would tear the controller down between one read and the next.
    container.listen(
      menuControllerProvider,
      (MenuState? _, MenuState _) {},
      fireImmediately: true,
    );

    addTearDown(container.dispose);

    return container;
  }

  Future<MenuScreenController> opened(
    ProviderContainer container, {
    String restaurantId = 'restaurant-1',
  }) async {
    final MenuScreenController controller = container.read(
      menuControllerProvider.notifier,
    );

    await controller.open(tripId: 'trip-1', restaurantId: restaurantId);

    return controller;
  }

  group('opening a menu', () {
    test('loads it once and keeps it', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      final MenuScreenController controller = await opened(container);

      expect(container.read(menuControllerProvider).hasItems, isTrue);
      expect(menus.calls, 1);

      // Re-entering the same screen does not re-fetch what is already there.
      await controller.open(tripId: 'trip-1', restaurantId: 'restaurant-1');

      expect(menus.calls, 1);
    });

    test('a different restaurant clears the previous menu first', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        delay: const Duration(milliseconds: 40),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuScreenController controller = container.read(
        menuControllerProvider.notifier,
      );

      final Future<void> second = controller.open(
        tripId: 'trip-1',
        restaurantId: 'restaurant-2',
      );

      // Mid-flight. One kitchen's prices must not sit under another kitchen's
      // name while the request is out.
      expect(container.read(menuControllerProvider).hasMenu, isFalse);
      expect(container.read(menuControllerProvider).isLoading, isTrue);

      await second;

      expect(container.read(menuControllerProvider).hasItems, isTrue);
    });
  });

  group('searching', () {
    test('a keystroke is debounced into one request', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuScreenController controller = container.read(
        menuControllerProvider.notifier,
      );

      controller
        ..searchChanged('pa')
        ..searchChanged('pan')
        ..searchChanged('pane')
        ..searchChanged('paneer');

      // Nothing has gone out yet — only the initial load.
      expect(menus.calls, 1);

      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 60),
      );

      expect(menus.calls, 2);
      expect(menus.lastRequest?.search, 'paneer');
    });

    test('a single character is not sent', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      container.read(menuControllerProvider.notifier).searchChanged('p');

      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 60),
      );

      // Sending it would return the whole menu and the screen would present it
      // as a result for "p".
      expect(menus.calls, 1);
      expect(container.read(menuControllerProvider).searchTerm, 'p');
    });

    test('a stale answer never overwrites a newer one', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        // The earlier request is made slower than the later one, which is the
        // ordering that breaks a naive implementation.
        delayFor: (String? search) => search == 'paneer'
            ? const Duration(milliseconds: 120)
            : const Duration(milliseconds: 10),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuScreenController controller = container.read(
        menuControllerProvider.notifier,
      );

      controller.searchChanged('paneer');
      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 20),
      );

      controller.searchChanged('dal');
      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 200),
      );

      // "paneer" resolved last and is discarded: the screen shows what the
      // customer actually typed.
      expect(container.read(menuControllerProvider).menu?.appliedSearch, 'dal');
    });

    test('clearing the search asks for the whole menu again', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuScreenController controller = container.read(
        menuControllerProvider.notifier,
      );

      controller.searchChanged('paneer');
      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 60),
      );

      await controller.clearSearch();

      expect(menus.lastRequest?.search, isNull);
      expect(container.read(menuControllerProvider).searchTerm, '');
    });

    test('the menu stays on screen while a search is in flight', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        delay: const Duration(milliseconds: 60),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      container.read(menuControllerProvider.notifier).searchChanged('paneer');

      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 20),
      );

      final MenuState state = container.read(menuControllerProvider);

      // A list that empties and refills on every letter is unreadable.
      expect(state.isSearching, isTrue);
      expect(state.hasItems, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('a search the server refuses is its own failure', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        errorFor: (String? search) => search == null
            ? null
            : const ApiException(
                code: ApiErrorCode.validationFailed,
                message: 'Too long.',
                status: 422,
              ),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      container
          .read(menuControllerProvider.notifier)
          .searchChanged('a' * 120);

      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 80),
      );

      expect(
        container.read(menuControllerProvider).failure,
        MenuFailure.searchRejected,
      );
    });
  });

  group('failures', () {
    test('an offline refresh keeps the menu and says it is stale', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      menus.nextError = const ApiException.network();

      await container.read(menuControllerProvider.notifier).refresh();

      final MenuState state = container.read(menuControllerProvider);

      // Kinder than punishing the customer for our outage — but never silent.
      expect(state.hasItems, isTrue);
      expect(state.isOffline, isTrue);
      expect(state.failure, MenuFailure.network);
    });

    test('a withdrawn restaurant loses its menu', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      menus.nextError = const ApiException(
        code: ApiErrorCode.restaurantUnavailable,
        message: 'No longer available.',
        status: 404,
      );

      await container.read(menuControllerProvider.notifier).refresh();

      final MenuState state = container.read(menuControllerProvider);

      // Leaving it up would present a suspended kitchen as though it were
      // trading.
      expect(state.hasMenu, isFalse);
      expect(state.failure, MenuFailure.withdrawn);
      expect(state.isRetryable, isFalse);
    });

    test('an outage offers a retry and a withdrawal does not', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        errorFor: (_) => const ApiException(
          code: ApiErrorCode.serverError,
          message: 'Ours.',
          status: 500,
        ),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      expect(container.read(menuControllerProvider).isRetryable, isTrue);
    });
  });

  group('the item preview', () {
    test('shows the card copy immediately and replaces it', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        delay: const Duration(milliseconds: 40),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuItem item = container
          .read(menuControllerProvider)
          .categories
          .first
          .items
          .first;

      final Future<void> opening = container
          .read(menuControllerProvider.notifier)
          .openItem(item);

      final MenuItemPreviewState immediate = container
          .read(menuControllerProvider)
          .preview;

      expect(immediate.isLoading, isTrue);
      expect(immediate.item?.name, item.name);

      await opening;

      // The fresh copy wins. A price may have changed since the list was drawn.
      expect(
        container.read(menuControllerProvider).preview.preview,
        isNotNull,
      );
    });

    test('an item withdrawn since the list was drawn loses its copy', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuItem item = container
          .read(menuControllerProvider)
          .categories
          .first
          .items
          .first;

      menus.nextItemError = const ApiException(
        code: ApiErrorCode.itemNotFound,
        message: 'Gone.',
        status: 404,
      );

      await container.read(menuControllerProvider.notifier).openItem(item);

      final MenuItemPreviewState preview = container
          .read(menuControllerProvider)
          .preview;

      // Leaving the card's copy up would present a dish the kitchen has taken
      // off as though it were still available.
      expect(preview.item, isNull);
      expect(preview.failure, MenuItemFailure.notFound);
      expect(preview.isRetryable, isFalse);
    });

    test('closing the sheet discards an answer still in flight', () async {
      final FakeMenuRepository menus = FakeMenuRepository(
        delay: const Duration(milliseconds: 60),
      );
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuItem item = container
          .read(menuControllerProvider)
          .categories
          .first
          .items
          .first;

      final MenuScreenController controller = container.read(
        menuControllerProvider.notifier,
      );

      final Future<void> opening = controller.openItem(item);
      controller.closeItem();

      await opening;

      // The sheet the customer dismissed must not reopen itself.
      expect(container.read(menuControllerProvider).preview.isOpen, isFalse);
    });
  });

  group('the section selector', () {
    test('a search that removes the selected section moves the highlight', () async {
      final FakeMenuRepository menus = FakeMenuRepository();
      final ProviderContainer container = containerWith(menus);

      await opened(container);

      final MenuScreenController controller = container.read(
        menuControllerProvider.notifier,
      )..categorySelected('category-3');

      expect(container.read(menuControllerProvider).selectedCategoryId, 'category-3');

      controller.searchChanged('Paneer');
      await Future<void>.delayed(
        MenuScreenController.searchDebounce + const Duration(milliseconds: 80),
      );

      // Beverages is not in the results, so the highlight cannot stay on it.
      final MenuState state = container.read(menuControllerProvider);

      expect(state.selectedCategoryId, isNot('category-3'));
      expect(
        state.categories.map((MenuCategory c) => c.id),
        contains(state.selectedCategoryId),
      );
    });
  });
}
