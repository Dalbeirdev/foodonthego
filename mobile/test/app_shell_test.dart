import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/router/app_shell.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/main.dart';

Widget _wrap(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? FotgTheme.light(), home: child);

/// The home screen is a lazy ListView, so content below the fold is never built
/// and an assertion about it would fail for the wrong reason. Scrolling is what a
/// real user does, and it exercises the scroll view rather than working around it.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('navigation architecture', () {
    testWidgets('shows the five customer destinations', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      for (final String label in <String>[
        'Home',
        'Trips',
        'Orders',
        'Alerts',
        'Profile',
      ]) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label destination is missing',
        );
      }
    });

    testWidgets('starts on Home', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Where are you travelling today?'),
        findsOneWidget,
      );
    });

    testWidgets('navigates to each tab and back', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();
      expect(find.text('Not built yet'), findsOneWidget);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.text('Not built yet'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Where are you travelling today?'),
        findsOneWidget,
      );
    });

    testWidgets('keeps every tab alive so state survives switching', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      // IndexedStack builds all five children; a swap-based shell would build one.
      expect(find.byType(IndexedStack), findsOneWidget);
      final IndexedStack stack = tester.widget(find.byType(IndexedStack));
      expect(stack.children.length, fotgDestinations.length);
    });

    testWidgets(
      'gives every destination a distinct route and a selected icon',
      (WidgetTester tester) async {
        final Set<String> routes = fotgDestinations.map((d) => d.route).toSet();
        expect(routes.length, fotgDestinations.length);

        for (final FotgDestination destination in fotgDestinations) {
          // The selected state changes shape, not only colour — colour alone is not
          // a reliable signal for a colour-blind user.
          expect(destination.selectedIcon, isNot(equals(destination.icon)));
        }
      },
    );
  });

  group('home screen', () {
    testWidgets('greets the development persona and offers the journey CTA', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Rahul'), findsWidgets);
      expect(find.text('Plan a journey'), findsWidgets);
    });

    testWidgets('the journey button is disabled rather than opening nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget(
        find.widgetWithText(FilledButton, 'Plan a journey'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('Module 09'), findsOneWidget);
    });

    testWidgets('states plainly that nothing is live data', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      final Finder notice = find.textContaining(
        'Nothing on this screen is live data',
      );
      await _scrollTo(tester, notice);
      expect(notice, findsOneWidget);
    });

    testWidgets('explains the route-based proposition, which is the product', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const FotgAppShell()));
      await tester.pumpAndSettle();

      final Finder journey = find.textContaining('Delhi to Jaipur');
      await _scrollTo(tester, journey);
      expect(journey, findsOneWidget);

      final Finder arrival = find.textContaining('against your arrival time');
      await _scrollTo(tester, arrival);
      expect(arrival, findsOneWidget);
    });
  });

  group('theming', () {
    testWidgets('renders in dark mode without losing the shell', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const FotgAppShell(), theme: FotgTheme.dark()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.textContaining('Where are you travelling today?'),
        findsOneWidget,
      );
    });

    testWidgets('the app follows the system theme rather than forcing one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const FoodOnTheGoApp());
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
      expect(app.darkTheme, isNotNull);
    });
  });
}
