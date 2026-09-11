import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/features/trips/widgets/location_picker_sheet.dart';

import 'support/harness.dart';

/// Locating a saved address.
///
/// Module 04 let a customer write an address down; nothing gave it a position,
/// so no saved address could ever be one end of a journey. This is where that is
/// fixed — by asking the customer to find it, never by geocoding what they typed
/// behind their back.
void main() {
  Future<void> openForm(
    WidgetTester tester, {
    required FakeCustomerRepository customer,
    FakePlaceRepository? places,
  }) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        customer: customer,
        places: places,
        initialLocation: '/profile',
      ),
    );
    await tester.pumpAndSettle();

    // Reached the way a customer reaches it: the form is pushed inside the
    // Profile branch, so the bottom navigation stays put.
    await tester.tap(find.text('Saved addresses'));
    await tester.pumpAndSettle();

    final Finder fab = find.byType(FloatingActionButton);
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab);
    } else {
      await tester.tap(find.text('Add your first address'));
    }
    await tester.pumpAndSettle();
  }

  /// The locate control sits below the fold on a phone, so it is scrolled to
  /// before being tapped rather than tapped where it is not.
  Future<void> openLocator(WidgetTester tester) async {
    final Finder button = find.widgetWithText(TextButton, 'Find this address');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> fillRequiredFields(WidgetTester tester) async {
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '12 Hauz Khas');
    await tester.enterText(fields.at(3), 'New Delhi');
    await tester.enterText(fields.at(4), 'Delhi');
    await tester.enterText(fields.at(5), '110016');
    await tester.pump();
  }

  testWidgets('a new address starts unlocated, and says so', (
    WidgetTester tester,
  ) async {
    await openForm(tester, customer: FakeCustomerRepository());

    expect(find.text('Not located yet'), findsOneWidget);
    expect(find.text('Find this address'), findsWidgets);
  });

  testWidgets('locating offers search alone', (WidgetTester tester) async {
    await openForm(tester, customer: FakeCustomerRepository());

    await openLocator(tester);

    expect(find.byType(LocationPickerSheet), findsOneWidget);
    // Not the device's position: the customer is describing an address from
    // memory, and pinning it to wherever they are standing would be wrong.
    expect(find.text('Use my current location'), findsNothing);
    // Not the saved addresses either — that would be circular.
    expect(find.text('Saved addresses'), findsNothing);
  });

  testWidgets('a found place gives the address a position', (
    WidgetTester tester,
  ) async {
    final FakeCustomerRepository customer = FakeCustomerRepository();
    await openForm(tester, customer: customer);

    await fillRequiredFields(tester);

    await openLocator(tester);

    await tester.enterText(find.byType(TextField).last, 'jaipur');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jaipur International Airport').last);
    await tester.pumpAndSettle();

    expect(find.text('Not located yet'), findsNothing);
    expect(find.text('Change'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
    await tester.pumpAndSettle();

    final AddressDraft draft = customer.lastDraft!;

    // The position the provider gave, unaltered, alongside the lines the
    // customer typed.
    expect(draft.latitude, closeTo(26.8242, 0.0001));
    expect(draft.longitude, closeTo(75.8122, 0.0001));
    expect(draft.placeId, 'dev:jaipur-airport');
    expect(draft.addressLine1, '12 Hauz Khas');
  });

  testWidgets('an address saved without locating sends no coordinates', (
    WidgetTester tester,
  ) async {
    final FakeCustomerRepository customer = FakeCustomerRepository();
    await openForm(tester, customer: customer);

    await fillRequiredFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = customer.lastDraft!.toJson();

    // Not zero, and not a guess derived from "New Delhi". An absent position is
    // the honest answer, and the planner explains what it means.
    expect(json.containsKey('latitude'), isFalse);
    expect(json.containsKey('longitude'), isFalse);
  });
}
