import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/features/restaurant/widgets/restaurant_hero_gallery.dart';
import 'package:foodonthego/shared/widgets/empty_state_view.dart';

import 'support/harness.dart';

/// The restaurant page, as a customer meets it.
void main() {
  Future<FakeRestaurantRepository> open(
    WidgetTester tester, {
    FakeRestaurantRepository? restaurants,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeRestaurantRepository repository =
        restaurants ?? FakeRestaurantRepository();

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
          restaurants: repository,
          initialLocation: '/trips/trip-1/route/restaurants/restaurant-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  /// Scrolls the page until [finder] has been built.
  ///
  /// The detail page is a `ListView`, so a section below the fold is never
  /// built and has no widget at all — an assertion about the hours reports
  /// "not found" whether the app is right or wrong.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('a restaurant on the route', () {
    testWidgets('shows the name, cuisines and price', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Highway Spice Kitchen'), findsWidgets);
      expect(find.textContaining('North Indian'), findsWidgets);
      // Two levels, as the fixture declares.
      expect(find.textContaining('₹₹'), findsOneWidget);
    });

    testWidgets('leads with what stopping costs on this journey', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // The card that makes this FoodOnTheGo's screen rather than a generic
      // restaurant page.
      expect(find.text('On your route'), findsOneWidget);
      expect(find.textContaining('68 km ahead'), findsOneWidget);
      expect(find.textContaining('4 min detour'), findsOneWidget);
      expect(find.textContaining('1.8 km off your route'), findsOneWidget);
    });

    testWidgets('asks for the restaurant in the url', (
      WidgetTester tester,
    ) async {
      final FakeRestaurantRepository repository = await open(tester);

      expect(repository.lastRequest!.tripId, 'trip-1');
      expect(repository.lastRequest!.restaurantId, 'restaurant-1');
    });

    testWidgets('shows the operator description under a heading', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('About'));

      expect(find.text('About'), findsOneWidget);
      expect(
        find.text('A highway kitchen on the Delhi-Jaipur road.'),
        findsOneWidget,
      );
    });
  });

  group('things a restaurant did not tell us', () {
    testWidgets('no description means no About section', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(description: null),
        ),
      );

      // An empty card with a heading over blank space reads as a bug, and
      // inventing a sentence to fill it would be worse.
      expect(find.text('About'), findsNothing);
    });

    testWidgets('no facilities means no Facilities section', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            restaurant: sampleRestaurant(facilities: const <String>[]),
          ),
        ),
      );

      expect(find.text('Facilities'), findsNothing);
    });

    testWidgets('no rating shows New, never a fabricated score', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('New'), findsOneWidget);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.textContaining('4.5'), findsNothing);
    });

    testWidgets('a real rating is shown with its review count', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            restaurant: sampleRestaurant(rating: 4.3, reviewCount: 214),
          ),
        ),
      );

      expect(find.text('4.3'), findsOneWidget);
      expect(find.text('(214)'), findsOneWidget);
      expect(find.text('New'), findsNothing);
    });

    testWidgets('no price level means no price in the header', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            restaurant: sampleRestaurant(priceLevel: null),
          ),
        ),
      );

      expect(find.textContaining('₹'), findsNothing);
    });
  });

  group('photographs', () {
    testWidgets('a restaurant with none gets a branded fallback', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // Never a broken image icon, and never a stock photograph of somebody
      // else's dining room.
      expect(find.text('No photographs yet'), findsOneWidget);
    });

    testWidgets('one photograph is not a gallery', (WidgetTester tester) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            media: <RestaurantImage>[sampleImage()],
          ),
        ),
      );

      // A "1 / 1" indicator and a swipe that goes nowhere both promise
      // something that is not there.
      expect(find.text('1 / 1'), findsNothing);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('several photographs get a counter and a swipe', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            media: <RestaurantImage>[
              sampleImage(id: 'a', altText: 'The dining room'),
              sampleImage(id: 'b', url: 'https://cdn.example.test/2.jpg'),
              sampleImage(id: 'c', url: 'https://cdn.example.test/3.jpg'),
            ],
          ),
        ),
      );

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byType(RestaurantHeroGallery), findsOneWidget);
    });

    testWidgets("a photograph that will not load falls back rather than "
        'breaking the page', (WidgetTester tester) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            media: <RestaurantImage>[
              sampleImage(url: 'https://cdn.example.test/missing.jpg'),
            ],
          ),
        ),
      );

      // In a widget test every network image fails, which is exactly the
      // failure path this asserts: the same branded stand-in, not a broken box.
      expect(find.text('No photographs yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('can I order', () {
    testWidgets('open and accepting gets a live menu button', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Open · Accepting orders'), findsOneWidget);

      final FilledButton cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'View menu'),
      );
      expect(cta.onPressed, isNotNull);
    });

    testWidgets('a paused kitchen says so and does not offer to order', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            ordering: RestaurantOrderingState.openPaused,
          ),
        ),
      );

      expect(
        find.text('Open · Not accepting orders right now'),
        findsOneWidget,
      );
      // A banner as well as a chip: a customer who scrolled past a small amber
      // pill to the button has been failed by the screen.
      expect(find.text('Not taking orders right now'), findsOneWidget);
      // The menu is still worth reading — the pause may lift before they
      // arrive — but the wording changes so nobody thinks they are ordering.
      expect(find.text('View menu'), findsNothing);
      expect(find.text('Browse the menu'), findsOneWidget);
    });

    testWidgets('a closed restaurant says when it opens again', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            ordering: RestaurantOrderingState.closed,
            hours: sampleHours(
              nextOpenAt: DateTime.now().add(const Duration(days: 1)),
            ),
          ),
        ),
      );

      expect(find.text('Closed'), findsWidgets);
      expect(find.textContaining('Opens tomorrow at'), findsOneWidget);
    });

    testWidgets('a permanently closed restaurant offers nothing to open', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            ordering: RestaurantOrderingState.closedPermanently,
          ),
        ),
      );

      expect(find.text('This restaurant is unavailable'), findsOneWidget);

      final FilledButton cta = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      // Its menu describes something that no longer exists.
      expect(cta.onPressed, isNull);
    });

    testWidgets('unknown hours never become permission to order', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            ordering: RestaurantOrderingState.unavailable,
          ),
        ),
      );

      final FilledButton cta = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(cta.onPressed, isNull);
    });
  });

  group('opening hours', () {
    testWidgets("today's hours are shown and the week is not, until asked", (
      WidgetTester tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('Opening hours'));

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Wednesday'), findsNothing);
      expect(find.text('View all hours'), findsOneWidget);
    });

    testWidgets('the whole week expands, with its timezone', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await scrollTo(tester, find.text('View all hours'));

      await tester.tap(find.text('View all hours'));
      await tester.pumpAndSettle();

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
      // Shown so a customer in another state is not misled by "opens at 8".
      expect(find.text('Times shown for Asia/Kolkata'), findsOneWidget);
    });

    testWidgets('a day the kitchen is shut says Closed', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            hours: sampleHours(
              today: const <OpeningWindow>[],
              week: <DayHours>[
                // Today is a Monday and the kitchen is shut; the rest of the
                // week it is open. A restaurant with *no* schedule at all is a
                // different case, tested below.
                const DayHours(
                  dayOfWeek: 0,
                  isToday: true,
                  windows: <OpeningWindow>[],
                ),
                const DayHours(
                  dayOfWeek: 1,
                  windows: <OpeningWindow>[
                    OpeningWindow(opensAt: '09:00:00', closesAt: '17:00:00'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      await scrollTo(tester, find.text('View all hours'));

      // A missing row is a question; a row that says Closed is an answer.
      expect(find.text('Closed'), findsWidgets);
    });

    testWidgets('an overnight window says it runs past midnight', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            hours: sampleHours(
              today: const <OpeningWindow>[
                OpeningWindow(
                  opensAt: '18:00:00',
                  closesAt: '02:00:00',
                  isOvernight: true,
                ),
              ],
            ),
          ),
        ),
      );

      await scrollTo(tester, find.text('Opening hours'));

      // "6:00 PM – 2:00 AM" read quickly looks like a typo.
      expect(find.textContaining('(overnight)'), findsOneWidget);
    });

    testWidgets('a restaurant with no schedule says so rather than guessing', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            hours: sampleHours(
              today: const <OpeningWindow>[],
              week: const <DayHours>[],
            ),
          ),
        ),
      );

      await scrollTo(tester, find.text('Opening hours'));

      expect(find.text('Opening times unknown'), findsOneWidget);
    });
  });

  group('when it goes wrong', () {
    Future<void> failWith(WidgetTester tester, ApiErrorCode code) async {
      await open(
        tester,
        restaurants: FakeRestaurantRepository()
          ..nextError = ApiException(code: code, message: 'no'),
      );
    }

    testWidgets('a withdrawn restaurant gets its own words and a way back', (
      WidgetTester tester,
    ) async {
      await failWith(tester, ApiErrorCode.restaurantUnavailable);

      expect(
        find.text('This restaurant is no longer available'),
        findsOneWidget,
      );
      // Not "Try again": it will not come back because they pressed a button.
      expect(find.text('Try again'), findsNothing);
      expect(
        find.widgetWithText(EmptyStateView, 'Back to restaurants'),
        findsOneWidget,
      );
    });

    testWidgets('a restaurant on another road says which problem it is', (
      WidgetTester tester,
    ) async {
      await failWith(tester, ApiErrorCode.restaurantOutsideRoute);

      expect(find.text('Not on this journey'), findsOneWidget);
    });

    testWidgets('an outage offers to try again', (WidgetTester tester) async {
      await failWith(tester, ApiErrorCode.serverError);

      expect(find.text("We couldn't load this restaurant"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retrying asks the server again', (WidgetTester tester) async {
      final FakeRestaurantRepository repository = await open(
        tester,
        restaurants: FakeRestaurantRepository()
          ..nextError = ApiException(
            code: ApiErrorCode.serverError,
            message: 'no',
          ),
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repository.calls, 2);
      expect(find.text('Highway Spice Kitchen'), findsWidgets);
    });
  });

  group('layout', () {
    testWidgets('a long restaurant name wraps rather than being cut off', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        size: const Size(320, 720),
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            restaurant: sampleRestaurant(
              name:
                  'Shree Rajasthan Highway Family Restaurant & '
                  'Vegetarian Food Court',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the page fits at every width we support', (
      WidgetTester tester,
    ) async {
      for (final Size size in <Size>[
        Size(320, 720),
        Size(360, 740),
        Size(375, 812),
        Size(390, 844),
        Size(412, 892),
        Size(430, 932),
      ]) {
        await open(tester, size: size);

        expect(tester.takeException(), isNull, reason: 'overflow at $size');
        expect(find.byType(FilledButton), findsOneWidget);
      }
    });

    testWidgets('the menu button is still reachable at 1.6x text', (
      WidgetTester tester,
    ) async {
      await open(tester, size: const Size(360, 740), textScale: 1.6);

      expect(tester.takeException(), isNull);
      // Pinned above the safe area rather than at the end of the scroll, so
      // large text cannot push it off the bottom.
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('many facilities stay readable', (WidgetTester tester) async {
      await open(
        tester,
        size: const Size(320, 720),
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            restaurant: sampleRestaurant(
              facilities: const <String>[
                'Parking',
                'Restroom',
                'Seating',
                'Wheelchair Accessible',
                'Takeaway',
                'EV Charging',
                'Wi-Fi',
              ],
            ),
          ),
        ),
      );

      await scrollTo(tester, find.text('Facilities'));

      expect(tester.takeException(), isNull);
      expect(find.text('Wheelchair Accessible'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('price level is announced as a word, not as symbols', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await open(tester);

      // "₹₹" is a visual convention a screen reader cannot convey.
      expect(find.bySemanticsLabel(RegExp('Moderate')), findsWidgets);

      handle.dispose();
    });

    testWidgets('a photograph is announced with the operator caption where '
        'there is one', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await open(
        tester,
        restaurants: FakeRestaurantRepository(
          detailToReturn: sampleRestaurantDetail(
            media: <RestaurantImage>[
              sampleImage(altText: 'The terrace at dusk'),
            ],
          ),
        ),
      );

      // A RegExp rather than an exact string: the fallback nested inside the
      // image contributes its own label when the bytes cannot load, which is
      // every widget test.
      expect(
        find.bySemanticsLabel(RegExp('The terrace at dusk')),
        findsWidgets,
      );

      handle.dispose();
    });

    testWidgets('a day of the week is announced with its hours', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await open(tester);
      await scrollTo(tester, find.text('View all hours'));

      expect(find.bySemanticsLabel(RegExp('^Today, ')), findsOneWidget);

      handle.dispose();
    });
  });
}
