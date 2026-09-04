import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';

import 'support/harness.dart';

const HomeDashboard _dashboard = HomeDashboard(
  customer: CustomerSummary(fullName: 'Rahul Sharma'),
);

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      wrapApp(repository: StubHomeRepository.value(_dashboard)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the five destinations', () {
    testWidgets('are all present', (WidgetTester tester) async {
      await pumpApp(tester);

      for (final String label in <String>[
        'Home',
        'Trips',
        'Orders',
        'Alerts',
        'Profile',
      ]) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: '$label destination is missing',
        );
      }
    });

    testWidgets('start on Home', (WidgetTester tester) async {
      await pumpApp(tester);

      final NavigationBar bar = tester.widget(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
      expect(find.text('Where are you travelling today?'), findsOneWidget);
    });
  });

  group('the navigation matrix', () {
    // Home -> Trips -> Orders -> Notifications -> Profile -> Home, as specified.
    testWidgets('walks the full cycle', (WidgetTester tester) async {
      await pumpApp(tester);

      await tapTab(tester, 'Trips');
      expect(find.text('No journeys yet'), findsOneWidget);

      await tapTab(tester, 'Orders');
      expect(find.text('No orders yet'), findsOneWidget);

      await tapTab(tester, 'Alerts');
      expect(find.text("You're all caught up"), findsOneWidget);

      await tapTab(tester, 'Profile');
      // The signed-in account's name, not the home dashboard's — from Module 03
      // the profile header reads the session rather than the dashboard payload.
      expect(find.text('Ravi Kumar'), findsWidgets);

      await tapTab(tester, 'Home');
      expect(find.text('Where are you travelling today?'), findsOneWidget);

      final NavigationBar bar = tester.widget(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
    });

    testWidgets('keeps the selected index in step with the screen', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      for (final (int index, String label) in <(int, String)>[
        (1, 'Trips'),
        (2, 'Orders'),
        (3, 'Alerts'),
        (4, 'Profile'),
        (0, 'Home'),
      ]) {
        await tapTab(tester, label);
        final NavigationBar bar = tester.widget(find.byType(NavigationBar));
        expect(
          bar.selectedIndex,
          index,
          reason: '$label should select index $index',
        );
      }
    });
  });

  group('robustness', () {
    testWidgets('survives rapid repeated tab switching', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      // Deliberately without settling between taps — this is a user jabbing at
      // the bar, which is where a naive shell drops frames or loses its index.
      for (int i = 0; i < 12; i++) {
        for (final String label in <String>[
          'Trips',
          'Orders',
          'Alerts',
          'Profile',
          'Home',
        ]) {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(label),
            ),
          );
          await tester.pump(const Duration(milliseconds: 8));
        }
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final NavigationBar bar = tester.widget(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
    });

    testWidgets('double-tapping a destination is harmless', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tapTab(tester, 'Orders');
      await tapTab(tester, 'Orders');

      expect(find.text('No orders yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not rebuild a tab from scratch when returning to it', (
      WidgetTester tester,
    ) async {
      final StubHomeRepository repository = StubHomeRepository.value(
        _dashboard,
      );
      usePhoneSurface(tester);
      await tester.pumpWidget(wrapApp(repository: repository));
      await tester.pumpAndSettle();

      expect(repository.loadCount, 1);

      await tapTab(tester, 'Trips');
      await tapTab(tester, 'Home');

      // The branch keeps its state, so coming back does not re-fetch and flash a
      // skeleton at somebody who never really left.
      expect(repository.loadCount, 1);
    });
  });

  group('Android back behaviour', () {
    testWidgets(
      'back from a non-home tab returns to Home rather than exiting',
      (WidgetTester tester) async {
        await pumpApp(tester);

        await tapTab(tester, 'Profile');
        expect(
          (tester.widget(
            find.byType(NavigationBar),
          ) as NavigationBar).selectedIndex,
          4,
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          (tester.widget(
            find.byType(NavigationBar),
          ) as NavigationBar).selectedIndex,
          0,
        );
      },
    );
  });

  group('unbuilt features', () {
    testWidgets('the journey CTA routes to a controlled placeholder', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Plan a journey'));
      await tester.pumpAndSettle();

      // Never a dead button, never silence.
      expect(find.text('Not built yet'.toUpperCase()), findsOneWidget);
      expect(find.textContaining('Module 05'), findsOneWidget);
    });

    testWidgets('the placeholder can be dismissed back to where it came from', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Plan a journey'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Where are you travelling today?'), findsOneWidget);
    });

    testWidgets('a profile row that IS built opens the real screen', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tapTab(tester, 'Profile');

      await tester.tap(find.text('Saved addresses'));
      await tester.pumpAndSettle();

      // Real from Module 04, not a placeholder.
      expect(find.text('No saved addresses yet'), findsOneWidget);
      expect(find.textContaining('Module'), findsNothing);
    });

    testWidgets('a profile row that is NOT built still names its module', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tapTab(tester, 'Profile');

      await tester.tap(find.text('Payment methods'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Module 11'), findsOneWidget);
    });

    testWidgets('a quick action that IS built navigates for real', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tester.scrollUntilVisible(find.text('Quick actions'), 300);
      await tester.tap(find.text('Orders').last);
      await tester.pumpAndSettle();

      // Orders exists in this module, so this is a real destination, not a stub.
      expect(find.text('No orders yet'), findsOneWidget);
    });
  });
}
