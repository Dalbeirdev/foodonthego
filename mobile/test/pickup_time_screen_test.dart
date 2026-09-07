import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/pickup.dart';
import 'package:foodonthego/domain/models/pre_checkout.dart';

import 'support/harness.dart';

/// Choosing a pickup time, as a customer meets it.
///
/// The theme is that **the screen decides nothing about time**. Several tests
/// below assert that what went to the server was the id it issued — never a
/// timestamp, never an index, never anything derived from a label on screen —
/// and that the verdicts rendered are the server's own rather than ones the
/// client worked out from what it could see.
void main() {
  Future<FakePickupRepository> open(
    WidgetTester tester, {
    FakePickupRepository? pickup,
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester);

    final FakePickupRepository repository = pickup ?? FakePickupRepository();

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
          pickup: repository,
          initialLocation: '/trips/trip-1/cart/pickup',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  /// Scrolls the check button into view before tapping it.
  ///
  /// It sits below the times and the explanation, which is where it belongs on
  /// a phone — a customer chooses first and checks after. A test that could
  /// only reach it without scrolling would be testing a shorter screen than the
  /// one that ships.
  Future<void> check(WidgetTester tester) async {
    final Finder button = find.byKey(
      const ValueKey<String>('pickup-check-order'),
    );

    final Finder list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(button, 200, scrollable: list);
    await tester.tap(button);
    await tester.pumpAndSettle();

    // The verdict appears below the button that asked for it, so a test that
    // stopped here would be asserting against a card the ListView has not
    // built yet.
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
  }

  // --- what the customer sees ----------------------------------------------

  testWidgets('shows the times, and how they were worked out', (
    WidgetTester tester,
  ) async {
    await open(tester);

    // Four windows, from the server.
    expect(find.textContaining('–'), findsWidgets);

    // And the arithmetic beside them. A list of times with no explanation is a
    // list a customer has to take on trust, and the first one that looks wrong
    // is the one that loses them.
    expect(find.text("You're about 93 minutes away"), findsOneWidget);
    expect(find.text('The kitchen needs about 20 minutes'), findsOneWidget);
    expect(find.text('Plus 5 minutes to bag it up'), findsOneWidget);
  });

  testWidgets('never promises a time it cannot keep', (
    WidgetTester tester,
  ) async {
    await open(tester);

    // The platform has an estimate of a drive and an estimate of a kitchen.
    // "Guaranteed ready at 3:30" is a promise neither of them can keep, and
    // this screen must not make it.
    expect(
      find.text('These are estimates. Traffic and kitchens both vary.'),
      findsOneWidget,
    );

    final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));

    for (final Text text in texts) {
      final String value = text.data ?? '';

      for (final String forbidden in <String>[
        'Guaranteed',
        'guaranteed',
        'Definitely',
        'Exactly',
      ]) {
        expect(
          value.contains(forbidden),
          isFalse,
          reason: '"$value" promises more than an estimate can',
        );
      }
    }
  });

  testWidgets('shows the time on the counter clock, not the phone one', (
    WidgetTester tester,
  ) async {
    await open(tester);

    // The fake's first window is 07:40 UTC, which the server writes as
    // 1:10 pm +05:30. A screen formatting the instant would show 7:40 am; one
    // formatting the phone's local time would show whatever the test machine
    // is set to. The door says ten past one.
    expect(find.text('1:10 pm – 1:20 pm'), findsOneWidget);
  });

  testWidgets('names the restaurant timezone rather than the phone one', (
    WidgetTester tester,
  ) async {
    await open(tester, pickup: FakePickupRepository(timezone: 'Asia/Kolkata'));

    // A pickup happens at the counter, on the counter's clock. Saying which
    // clock is what stops a traveller two zones away reading a time as theirs.
    expect(find.text('Times shown in Asia/Kolkata'), findsOneWidget);
  });

  // --- choosing ------------------------------------------------------------

  testWidgets('sends the option id the server issued, and nothing else', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = await open(tester);

    final String expected = pickup.offered.first.id;

    await tester.tap(find.byKey(ValueKey<String>('pickup-option-$expected')));
    await tester.pumpAndSettle();

    // The id, verbatim. Not a time, not an index, not a label — the exact
    // string the server minted.
    expect(pickup.optionIdsSent, <String>[expected]);
    expect(pickup.selectCalls, 1);

    // And nothing on screen ever became a request. The id carries no structure
    // a client could have assembled.
    for (final String sent in pickup.optionIdsSent) {
      expect(DateTime.tryParse(sent), isNull);
      expect(int.tryParse(sent), isNull);
    }
  });

  testWidgets('shows the chosen window once the server has agreed', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = await open(tester);

    expect(find.text('Your pickup time'), findsNothing);

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    // Not before. A screen that showed a choice as made while the request was
    // in flight would be showing a pickup time the server may refuse.
    expect(find.text('Your pickup time'), findsOneWidget);
  });

  testWidgets('an expired id reloads the times rather than explaining itself', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = await open(tester);

    pickup.nextSelectError = const ApiException(
      code: ApiErrorCode.pickupOptionExpired,
      message: 'That pickup time is no longer available.',
    );

    final int before = pickup.optionsCalls;

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    // Every chip on screen is suspect, not just the one that was tapped.
    // Leaving stale times up invites the customer to tap another and be
    // refused again.
    expect(pickup.optionsCalls, greaterThan(before));
  });

  testWidgets('a stale plan reloads too', (WidgetTester tester) async {
    final FakePickupRepository pickup = await open(tester);

    pickup.nextSelectError = const ApiException(
      code: ApiErrorCode.pickupOptionStale,
      message: 'Your order has changed since you chose that pickup time.',
    );

    final int before = pickup.optionsCalls;

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    expect(pickup.optionsCalls, greaterThan(before));
  });

  // --- what the server says has become of the choice ------------------------

  testWidgets('a stale selection is reported from the server status', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository()
      ..selectionStatus = PickupSelectionStatus.stale;

    await open(tester, pickup: pickup);

    // The screen does not compare a stored time against the clock to decide
    // this. That comparison belongs to the side that knows the restaurant's
    // hours and the route's age.
    expect(find.text('Your order has changed'), findsOneWidget);
  });

  testWidgets('an invalid selection is reported from the server status', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository()
      ..selectionStatus = PickupSelectionStatus.invalid;

    await open(tester, pickup: pickup);

    expect(find.text('That time has passed'), findsOneWidget);
  });

  testWidgets('a status this build has never heard of is not read as fine', (
    WidgetTester tester,
  ) async {
    // A wire value from a future release. The client must not treat an
    // unrecognised status as a settled one.
    expect(
      PickupSelectionStatus.fromWire('COLLECTED'),
      PickupSelectionStatus.none,
    );
    expect(PickupSelectionStatus.fromWire(null), PickupSelectionStatus.none);
    expect(PickupSelectionStatus.fromWire(42), PickupSelectionStatus.none);
  });

  // --- pre-checkout ---------------------------------------------------------

  testWidgets('renders the server verdict rather than deriving one', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository()
      // The case that matters most: the server says NO while listing an issue
      // this build has never heard of. A screen that decided readiness by
      // looking at the issues it recognised would say yes here.
      ..readyForCheckout = false
      ..preCheckoutIssues = const <PreCheckoutIssue>[
        PreCheckoutIssue(
          message: 'Something this version does not know about.',
          blocking: true,
        ),
      ];

    await open(tester, pickup: pickup);

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    await check(tester);

    expect(find.text('Not quite ready'), findsOneWidget);
    expect(find.text('Your order is ready to go'), findsNothing);

    // The server's own words reach the customer, because the message travelled
    // with the issue rather than being looked up from a code.
    expect(
      find.text('Something this version does not know about.'),
      findsOneWidget,
    );
  });

  testWidgets('a no with nothing to show for it is still a no', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository()
      // The sharpest case there is: the server refuses and lists nothing the
      // client can point at. A screen that worked readiness out from the issues
      // it could see would say yes here — which is precisely the moment saying
      // yes is worst.
      ..readyForCheckout = false
      ..preCheckoutIssues = const <PreCheckoutIssue>[];

    await open(tester, pickup: pickup);

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    await check(tester);

    expect(find.text('Not quite ready'), findsOneWidget);
    expect(find.text('Your order is ready to go'), findsNothing);
  });

  testWidgets('says yes only when the server does', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository()
      ..readyForCheckout = true;

    await open(tester, pickup: pickup);

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    await check(tester);

    expect(find.text('Your order is ready to go'), findsOneWidget);
  });

  testWidgets('a price that has fallen is shown and is not in the way', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository()
      ..readyForCheckout = true
      ..preCheckoutIssues = const <PreCheckoutIssue>[
        PreCheckoutIssue(
          code: PreCheckoutIssueCode.priceDecreased,
          message: 'One item now costs less than when you added it.',
          blocking: false,
        ),
      ];

    await open(tester, pickup: pickup);

    await tester.tap(
      find.byKey(ValueKey<String>('pickup-option-${pickup.offered.first.id}')),
    );
    await tester.pumpAndSettle();

    await check(tester);

    // Told, and not blocked. Nobody needs a dialogue to be charged less.
    expect(find.text('Not quite ready'), findsNothing);
    expect(
      find.text('One item now costs less than when you added it.'),
      findsOneWidget,
    );
  });

  testWidgets('checking is unavailable until a time is chosen', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = await open(tester);

    // Nothing chosen, so nothing to check. The server would refuse anyway;
    // this only saves the customer the trip.
    final Finder button = find.byKey(
      const ValueKey<String>('pickup-check-order'),
    );

    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(pickup.preCheckoutCalls, 0);
  });

  // --- nothing to offer ------------------------------------------------------

  testWidgets('a stale journey asks for a refresh rather than re-routing', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      pickup: FakePickupRepository(
        options: const <PickupOption>[],
        isFeasible: false,
        requiresRouteRefresh: true,
        reason: 'ROUTE_STALE',
      ),
    );

    // The app never triggers a billed routing call on its own. It says what is
    // needed and lets the customer ask for it.
    expect(find.text('Your journey needs refreshing'), findsOneWidget);
  });

  testWidgets('a closed kitchen says so, and does not offer times', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      pickup: FakePickupRepository(
        options: const <PickupOption>[],
        isFeasible: false,
        reason: 'RESTAURANT_NOT_ACCEPTING_ORDERS',
      ),
    );

    expect(find.text('This kitchen has stopped taking orders'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('no feasible window explains itself', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      pickup: FakePickupRepository(
        options: const <PickupOption>[],
        isFeasible: false,
        reason: 'NO_FEASIBLE_PICKUP_WINDOW',
      ),
    );

    expect(find.text('No pickup times available'), findsOneWidget);
  });

  // --- failures --------------------------------------------------------------

  testWidgets('a failed load offers a retry that actually retries', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = FakePickupRepository();

    pickup.nextOptionsError = const ApiException(
      code: ApiErrorCode.serverError,
      message: 'Something went wrong.',
    );

    await open(tester, pickup: pickup);

    expect(find.text("We couldn't work out pickup times"), findsOneWidget);

    final int before = pickup.optionsCalls;

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(pickup.optionsCalls, greaterThan(before));
    expect(find.textContaining('–'), findsWidgets);
  });

  testWidgets('a retried selection replays rather than repeats', (
    WidgetTester tester,
  ) async {
    final FakePickupRepository pickup = await open(tester);

    final String id = pickup.offered.first.id;

    pickup.nextSelectError = const ApiException(
      code: ApiErrorCode.network,
      message: 'No connection.',
    );

    await tester.tap(find.byKey(ValueKey<String>('pickup-option-$id')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey<String>('pickup-option-$id')));
    await tester.pumpAndSettle();

    // The same key both times. A connection that died after the server acted
    // must not produce a second selection.
    expect(pickup.keysUsed.length, 2);
    expect(pickup.keysUsed.first, isNotNull);
    expect(pickup.keysUsed.first, pickup.keysUsed.last);
  });

  // --- accessibility ---------------------------------------------------------

  testWidgets('the recommendation is spoken as well as drawn', (
    WidgetTester tester,
  ) async {
    await open(tester);

    // A customer using a screen reader gets the same steer as one looking at a
    // highlighted chip.
    expect(find.bySemanticsLabel(RegExp(r'Recommended')), findsOneWidget);
  });

  testWidgets('the times survive the largest text a phone offers', (
    WidgetTester tester,
  ) async {
    await open(tester, textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('–'), findsWidgets);
  });
}
