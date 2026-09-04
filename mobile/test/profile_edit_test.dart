import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';

import 'support/harness.dart';

const HomeDashboard _dashboard = HomeDashboard(
  customer: CustomerSummary(fullName: 'Rahul Sharma'),
);

const Customer _rahul = Customer(
  id: 'cus-rahul',
  firstName: 'Rahul',
  lastName: 'Sharma',
  phone: '+919999900101',
  email: 'rahul.test@foodonthego.example',
  phoneVerified: true,
);

/// The profile screen and the one form that edits it.
void main() {
  Future<FakeCustomerRepository> pumpProfile(
    WidgetTester tester, {
    FakeCustomerRepository? customer,
    FakeAuthRepository? auth,
  }) async {
    usePhoneSurface(tester);
    final FakeCustomerRepository repository =
        customer ?? FakeCustomerRepository(customer: _rahul);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: auth ?? FakeAuthRepository(customer: _rahul),
        customer: repository,
        initialLocation: '/profile',
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  Future<void> openEditProfile(WidgetTester tester) async {
    await tester.tap(find.text('Personal information'));
    await tester.pumpAndSettle();
  }

  group('the profile screen', () {
    testWidgets('shows the signed-in account, not a fixture', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);

      expect(find.text('Rahul Sharma'), findsWidgets);
      expect(find.text('+91 ••••••0101'), findsOneWidget);
      // Never the full number, even on the account's own screen.
      expect(find.text('+919999900101'), findsNothing);
    });

    testWidgets('a long name does not break the header', (
      WidgetTester tester,
    ) async {
      await pumpProfile(
        tester,
        customer: FakeCustomerRepository(
          customer: const Customer(
            id: 'cus-long',
            firstName: 'Rahul Krishnamurthy',
            lastName: 'Venkataraghavan Sharma',
            phone: '+919999900101',
            phoneVerified: true,
          ),
        ),
        auth: FakeAuthRepository(
          customer: const Customer(
            id: 'cus-long',
            firstName: 'Rahul Krishnamurthy',
            lastName: 'Venkataraghavan Sharma',
            phone: '+919999900101',
            phoneVerified: true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Two initials from the first and last name, not five from every word.
      expect(find.text('RV'), findsOneWidget);
    });
  });

  group('editing the profile', () {
    testWidgets('opens pre-filled from the session', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);
      await openEditProfile(tester);

      expect(find.widgetWithText(TextFormField, 'Rahul'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Sharma'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'rahul.test@foodonthego.example'),
        findsOneWidget,
      );
    });

    testWidgets('the verified number is shown and has no editable control', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);
      await openEditProfile(tester);

      expect(find.text('+91 ••••••0101'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(
        find.text(
          'Your mobile number is how we recognise you. Contact support to change it.',
        ),
        findsOneWidget,
      );

      // Three fields, and none of them is the phone. There is nowhere on this
      // screen for a number change to originate.
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.widgetWithText(TextFormField, '+919999900101'), findsNothing);
    });

    testWidgets('"Verified" is text, not a colour', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);
      await openEditProfile(tester);

      // A green tick alone is invisible to a screen reader and to anybody who
      // cannot distinguish the colour.
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('the email field never claims the address is verified', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);
      await openEditProfile(tester);

      expect(
        find.text(
          'Used for receipts only. We do not verify email addresses yet.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('saving sends only what the customer may change', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).at(1), 'S. Sharma');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(repository.lastProfileUpdate, <String, String?>{
        'first_name': 'Rahul',
        'last_name': 'S. Sharma',
        'email': 'rahul.test@foodonthego.example',
      });
      expect(repository.lastProfileUpdate!.containsKey('phone'), isFalse);
    });

    testWidgets('a successful save confirms and returns to the profile', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Rahul');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Profile updated'), findsOneWidget);
      expect(find.text('Personal information'), findsOneWidget);
    });

    testWidgets('the new name reaches the rest of the app immediately', (
      WidgetTester tester,
    ) async {
      await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Rahul');
      await tester.enterText(find.byType(TextFormField).at(1), 'S. Sharma');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      // The session is the single source of truth for who is signed in; without
      // updating it the home greeting keeps the old name until a cold start.
      expect(find.text('Rahul S. Sharma'), findsWidgets);
    });

    testWidgets('a blank first name is rejected before any request', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your first name.'), findsOneWidget);
      expect(repository.lastProfileUpdate, isNull);
    });

    testWidgets('a blank surname is allowed — Module 03 made it optional', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      // Cleared, not stored as "". A rule established in one module cannot be
      // silently tightened in the next.
      expect(repository.lastProfileUpdate!['last_name'], isNull);
    });

    testWidgets('a malformed email is caught before the request', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).at(2), 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.text('That email address does not look right.'),
        findsOneWidget,
      );
      expect(repository.lastProfileUpdate, isNull);
    });

    testWidgets('a server validation message is shown against the form', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository =
          FakeCustomerRepository(customer: _rahul)
            ..nextProfileError = const ApiException(
              code: ApiErrorCode.validationFailed,
              message: 'Invalid.',
              status: 422,
              details: <String, dynamic>{
                'fields': <String, dynamic>{
                  'email': <String>[
                    'That email address is already on another account.',
                  ],
                },
              },
            );

      await pumpProfile(tester, customer: repository);
      await openEditProfile(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      // The server's field message is more specific than anything the screen
      // could compose.
      expect(
        find.text('That email address is already on another account.'),
        findsOneWidget,
      );
    });

    testWidgets('offline says nothing was saved rather than claiming success', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = FakeCustomerRepository(
        customer: _rahul,
      )..nextProfileError = const ApiException.network();

      await pumpProfile(tester, customer: repository);
      await openEditProfile(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'You need a connection to save this. Nothing has been changed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Profile updated'), findsNothing);
      // Still on the form, with what was typed intact.
      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    testWidgets('a server error does not show a stack trace', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository =
          FakeCustomerRepository(customer: _rahul)
            ..nextProfileError = const ApiException(
              code: ApiErrorCode.serverError,
              message: 'Undefined index: foo in /var/www/app/Thing.php:42',
              status: 500,
            );

      await pumpProfile(tester, customer: repository);
      await openEditProfile(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('/var/www'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('unicode and punctuated names go through unchanged', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).first, 'José');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        "O'Brien-Krishna",
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(repository.lastProfileUpdate!['first_name'], 'José');
      expect(repository.lastProfileUpdate!['last_name'], "O'Brien-Krishna");
    });

    testWidgets('the name is trimmed before it is sent', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.enterText(find.byType(TextFormField).first, '  Rahul  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(repository.lastProfileUpdate!['first_name'], 'Rahul');
    });
  });
}
