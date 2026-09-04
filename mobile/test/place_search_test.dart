import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/shared/state/place_search_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Place autocomplete: what is sent, how often, and which answer wins.
///
/// The last group is the one this module's test matrix insists on. A slow
/// response to an abandoned query arriving after a fast response to the current
/// one is not a hypothetical — it is what a mobile network does routinely — and
/// the visible symptom is a customer seeing results for a word they finished
/// typing seconds ago.
void main() {
  late FakePlaceRepository places;
  late ProviderContainer container;

  setUp(() {
    places = FakePlaceRepository();
    container = ProviderContainer(
      // The list type is inferred: `Override` is not exported from
      // flutter_riverpod, and importing it from a transitive package to write an
      // annotation the compiler can work out itself is not worth the coupling.
      overrides: [placeRepositoryProvider.overrideWithValue(places)],
    );
    addTearDown(container.dispose);

    // The provider auto-disposes, and in the app the search sheet is what keeps
    // it alive. A test with no listener would tear the controller down between
    // one read and the next.
    container.listen(
      placeSearchControllerProvider,
      (PlaceSearchState? _, PlaceSearchState _) {},
      fireImmediately: true,
    );
  });

  PlaceSearchController controller() =>
      container.read(placeSearchControllerProvider.notifier);

  PlaceSearchState state() => container.read(placeSearchControllerProvider);

  /// Long enough for the debounce to elapse and the (immediate) request to
  /// settle.
  Future<void> settle([Duration? extra]) => Future<void>.delayed(
    kPlaceSearchDebounce + (extra ?? const Duration(milliseconds: 20)),
  );

  group('what reaches the provider', () {
    test('one letter is never sent', () async {
      controller().query('J');
      await settle();

      // A single letter is not a search. Sending it would spend a metered
      // request on nothing and return the whole gazetteer.
      expect(places.queries, isEmpty);
      expect(state().isSearching, isFalse);
      expect(state().hasSearched, isFalse);
    });

    test('a whole word typed quickly costs one request, not six', () async {
      final PlaceSearchController c = controller();

      for (final String value in <String>[
        'ja',
        'jai',
        'jaip',
        'jaipu',
        'jaipur',
      ]) {
        c.query(value);
        // Faster than the debounce, which is how people type.
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      await settle();

      expect(places.queries, <String>['jaipur']);
    });

    test('a pause mid-word does produce a second request', () async {
      final PlaceSearchController c = controller();

      c.query('jai');
      await settle();
      c.query('jaipur');
      await settle();

      expect(places.queries, <String>['jai', 'jaipur']);
    });

    test('clearing the field abandons anything pending', () async {
      final PlaceSearchController c = controller();

      c.query('jaipur');
      c.clear();
      await settle();

      expect(places.queries, isEmpty);
      expect(state().query, isEmpty);
      expect(state().results, isEmpty);
    });
  });

  group('the session token', () {
    test('is minted once and reused across every keystroke', () async {
      final PlaceSearchController c = controller();
      c.beginSession();

      final String? token = c.sessionToken;
      expect(token, isNotNull);

      c.query('jai');
      await settle();
      c.query('jaipur');
      await settle();

      // A token per keystroke bills exactly like no token at all, which is the
      // failure mode this guards against.
      expect(places.sessionTokens, <String?>[token, token]);
      expect(c.sessionToken, token);
    });

    test('a second search gets a fresh token, not the previous one', () async {
      final PlaceSearchController c = controller();

      c.beginSession();
      final String? first = c.sessionToken;
      c.endSession();

      c.beginSession();
      final String? second = c.sessionToken;

      // A token that lives forever is a session that never closes.
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second, isNot(first));
    });

    test('tokens are not guessable from one another', () {
      final PlaceSearchController c = controller();

      final Set<String> seen = <String>{};
      for (int i = 0; i < 20; i++) {
        c.beginSession();
        seen.add(c.sessionToken!);
        c.endSession();
      }

      expect(seen.length, 20);
      expect(seen.every((String t) => t.length == 32), isTrue);
    });
  });

  group('stale answers', () {
    test('a slow answer to an abandoned query never reaches the screen', () async {
      final PlaceSearchController c = controller();

      // "jai" takes far longer than "jaipur" — the ordinary shape of a mobile
      // network under load.
      places.delays['jai'] = const Duration(milliseconds: 400);

      c.query('jai');
      await Future<void>.delayed(
        kPlaceSearchDebounce + const Duration(milliseconds: 20),
      );

      c.query('jaipur');
      await Future<void>.delayed(
        kPlaceSearchDebounce + const Duration(milliseconds: 20),
      );

      // Current query's results are on screen.
      expect(state().results.single.placeId, 'dev:jaipur-airport');

      // Now let the abandoned query land.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Still the current query's results. The stale two-result list for "jai"
      // was discarded rather than rendered.
      expect(places.queries, <String>['jai', 'jaipur']);
      expect(state().query, 'jaipur');
      expect(state().results.length, 1);
      expect(state().results.single.placeId, 'dev:jaipur-airport');
    });

    test('a stale failure does not replace a current success', () async {
      final PlaceSearchController c = controller();

      places.delays['jai'] = const Duration(milliseconds: 400);
      // Scripted against "jai" specifically: both queries are in flight, and a
      // single scripted error would be claimed by whichever returned first.
      places.searchErrors['jai'] = const ApiException(
        code: ApiErrorCode.placeLookupFailed,
        message: 'down',
        status: 503,
      );

      c.query('jai');
      await Future<void>.delayed(
        kPlaceSearchDebounce + const Duration(milliseconds: 20),
      );
      c.query('jaipur');
      await settle();

      expect(state().failure, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 500));

      // An error banner over a correct list is the same defect as stale results
      // over a correct list.
      expect(state().failure, isNull);
      expect(state().results, isNotEmpty);
    });
  });

  group('what the screen is told', () {
    test('no results is an empty state, not a failure', () async {
      controller().query('atlantis');
      await settle();

      expect(state().failure, isNull);
      expect(state().isEmptyResult, isTrue);
    });

    test('a provider failure is distinguishable from no results', () async {
      places.nextSearchError = const ApiException(
        code: ApiErrorCode.placeLookupFailed,
        message: 'down',
        status: 503,
      );

      controller().query('jaipur');
      await settle();

      expect(state().failure, PlaceSearchFailure.lookupUnavailable);
      expect(state().isEmptyResult, isFalse);
    });

    test('being offline reads as offline, not as a broken provider', () async {
      places.nextSearchError = const ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
        status: 0,
      );

      controller().query('jaipur');
      await settle();

      expect(state().failure, PlaceSearchFailure.network);
    });

    test('retry re-runs the current query', () async {
      places.nextSearchError = const ApiException(
        code: ApiErrorCode.placeLookupFailed,
        message: 'down',
        status: 503,
      );

      final PlaceSearchController c = controller();
      c.query('jaipur');
      await settle();
      expect(state().failure, isNotNull);

      c.retry();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(places.queries, <String>['jaipur', 'jaipur']);
      expect(state().failure, isNull);
      expect(state().results, isNotEmpty);
    });
  });
}
