import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/features/addresses/saved_addresses_screen.dart';
import 'package:foodonthego/features/addresses/widgets/address_card.dart';

import 'support/harness.dart';

const HomeDashboard _dashboard = HomeDashboard(
  customer: CustomerSummary(fullName: 'Rahul Sharma'),
);

const Customer _rahul = Customer(
  id: 'cus-rahul',
  firstName: 'Rahul',
  lastName: 'Sharma',
  phone: '+919999900101',
  phoneVerified: true,
);

void main() {
  Future<FakeCustomerRepository> pumpAddresses(
    WidgetTester tester, {
    List<SavedAddress>? addresses,
    FakeCustomerRepository? customer,
    Size size = const Size(390, 844),
  }) async {
    usePhoneSurface(tester, size: size);
    final FakeCustomerRepository repository =
        customer ??
        FakeCustomerRepository(customer: _rahul, addresses: addresses);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: FakeAuthRepository(customer: _rahul),
        customer: repository,
        initialLocation: '/profile',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved addresses'));
    await tester.pumpAndSettle();

    return repository;
  }

  /// Scoped to the addresses screen.
  ///
  /// Saved Addresses is pushed inside the Profile branch, so the bottom
  /// navigation is still on screen — and its "Home" tab would otherwise match a
  /// finder looking for a Home *address*.
  Finder onScreen(Finder finder) =>
      find.descendant(of: find.byType(SavedAddressesScreen), matching: finder);

  Future<void> fillForm(
    WidgetTester tester, {
    String line1 = '12 Green Park Road',
    String city = 'New Delhi',
    String state = 'Delhi',
    String postal = '110016',
  }) async {
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), line1);
    await tester.enterText(fields.at(3), city);
    await tester.enterText(fields.at(4), state);
    await tester.enterText(fields.at(5), postal);
    await tester.pump();
  }

  Future<void> openAddForm(WidgetTester tester) async {
    final Finder fab = find.byType(FloatingActionButton);
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab);
    } else {
      await tester.tap(find.text('Add your first address'));
    }
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('a new customer sees an empty state that explains the value', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(tester);

      expect(find.text('No saved addresses yet'), findsOneWidget);
      // Says what saving one buys, not just that there are none.
      expect(find.textContaining('single tap'), findsOneWidget);
      expect(find.text('Add your first address'), findsOneWidget);
    });

    testWidgets('populated rows show label, address and locality', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(
        tester,
        addresses: <SavedAddress>[
          sampleAddress(isDefault: true),
          sampleAddress(
            id: 'addr-2',
            type: AddressType.work,
            label: 'Work',
            addressLine1: 'Connaught Place',
            addressLine2: null,
            postalCode: '110001',
          ),
        ],
      );

      expect(onScreen(find.text('Home')), findsOneWidget);
      expect(onScreen(find.text('Work')), findsOneWidget);
      expect(find.text('12 Green Park Road, Green Park'), findsOneWidget);
      expect(find.text('New Delhi, Delhi 110016'), findsOneWidget);
    });

    testWidgets('the default is marked with a word, not just a colour', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(
        tester,
        addresses: <SavedAddress>[sampleAddress(isDefault: true)],
      );

      expect(find.text('DEFAULT'), findsOneWidget);
    });

    testWidgets('the default is listed first', (WidgetTester tester) async {
      await pumpAddresses(
        tester,
        addresses: <SavedAddress>[
          sampleAddress(id: 'addr-1', label: 'Home'),
          sampleAddress(
            id: 'addr-2',
            type: AddressType.work,
            label: 'Work',
            isDefault: true,
          ),
        ],
      );

      final double workY = tester.getTopLeft(onScreen(find.text('Work'))).dy;
      final double homeY = tester.getTopLeft(onScreen(find.text('Home'))).dy;

      expect(workY, lessThan(homeY));
    });

    testWidgets('a custom label is shown as the customer wrote it', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(
        tester,
        addresses: <SavedAddress>[
          sampleAddress(
            type: AddressType.other,
            label: "Parents' House",
            isDefault: true,
          ),
        ],
      );

      expect(find.text("Parents' House"), findsOneWidget);
    });

    testWidgets('a long address wraps instead of overflowing', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(
        tester,
        size: const Size(320, 640),
        addresses: <SavedAddress>[
          sampleAddress(
            addressLine1: 'Flat 204, Shree Krishna Residency',
            addressLine2: 'Mahatma Gandhi Extension Service Road, Near Central Metro Interchange',
            landmark: 'Opposite the interchange gate number four',
            isDefault: true,
          ),
        ],
      );

      // No RenderFlex overflow on the smallest supported width.
      expect(tester.takeException(), isNull);
      expect(onScreen(find.text('Home')), findsOneWidget);
    });

    testWidgets(
      'a long custom label truncates rather than pushing the badge off',
      (WidgetTester tester) async {
        usePhoneSurface(tester, size: const Size(320, 640));
        await pumpAddresses(
          tester,
          addresses: <SavedAddress>[
            sampleAddress(
              type: AddressType.other,
              label: 'My parents house in the old part of Jaipur near the fort',
              isDefault: true,
            ),
          ],
        );

        expect(tester.takeException(), isNull);
        // The DEFAULT badge survives the long label.
        expect(find.text('DEFAULT'), findsOneWidget);
      },
    );

    testWidgets('a failed load offers a retry that actually re-asks', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = FakeCustomerRepository(
        customer: _rahul,
      )..nextListError = const ApiException.network();

      await pumpAddresses(tester, customer: repository);

      expect(
        find.text('No connection. Your changes have not been saved.'),
        findsOneWidget,
      );

      final int before = repository.listReads;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(repository.listReads, greaterThan(before));
      expect(find.text('No saved addresses yet'), findsOneWidget);
    });
  });

  group('adding an address', () {
    testWidgets('the form asks for an Indian address in writing order', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(tester);
      await openAddForm(tester);

      expect(find.text('Add address'), findsWidgets);
      expect(find.text('Flat, house or building'), findsOneWidget);
      expect(find.text('Landmark (optional)'), findsOneWidget);
      expect(find.text('PIN code'), findsOneWidget);
      // The country is fixed for the launch market and shown rather than picked.
      expect(find.text('India'), findsOneWidget);
    });

    testWidgets('required fields are enforced before any request', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpAddresses(tester);
      await openAddForm(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the flat, building or street.'), findsOneWidget);
      expect(find.text('Enter the city.'), findsOneWidget);
      expect(find.text('Enter the state.'), findsOneWidget);
      expect(repository.createCount, 0);
    });

    testWidgets('an invalid PIN code is caught locally', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpAddresses(tester);
      await openAddForm(tester);

      await fillForm(tester, postal: '11001');
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('a PIN code looks like 110016'),
        findsOneWidget,
      );
      expect(repository.createCount, 0);
    });

    testWidgets('the type selector fits the smallest supported screen', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(tester, size: const Size(320, 640));
      await openAddForm(tester);

      // Below 320dp of usable width Material wraps a segment's label rather
      // than shrinking it — "Othe / r". The icons go instead, because the label
      // is the part that carries the meaning.
      expect(tester.takeException(), isNull);
      expect(find.text('Other'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    });

    testWidgets('an Other address must be named', (WidgetTester tester) async {
      final FakeCustomerRepository repository = await pumpAddresses(tester);
      await openAddForm(tester);

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(find.text('Give this address a name.'), findsOneWidget);
      expect(repository.createCount, 0);
    });

    testWidgets('a valid address is saved and confirmed', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpAddresses(tester);
      await openAddForm(tester);

      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(repository.createCount, 1);
      expect(repository.lastDraft!.addressLine1, '12 Green Park Road');
      expect(find.text('Address saved'), findsOneWidget);
      expect(onScreen(find.text('Home')), findsOneWidget);
    });

    testWidgets('the first address is shown as the default', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(tester);
      await openAddForm(tester);
      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(find.text('DEFAULT'), findsOneWidget);
    });

    testWidgets('blank optional fields are sent as absent, not empty', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await pumpAddresses(tester);
      await openAddForm(tester);

      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      // Asserted on the wire payload, which is where blank becomes absent. An
      // empty string is not a landmark, and storing one makes every later null
      // check wrong.
      final Map<String, dynamic> sent = repository.lastDraft!.toJson();
      expect(sent['landmark'], isNull);
      expect(sent['address_line_2'], isNull);
    });

    testWidgets('offline says so and saves nothing', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = FakeCustomerRepository(
        customer: _rahul,
      )..nextWriteError = const ApiException.network();

      await pumpAddresses(tester, customer: repository);
      await openAddForm(tester);
      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'You need a connection to save this. Nothing has been changed.',
        ),
        findsOneWidget,
      );
      // Nothing claims success, and the form keeps what was typed.
      expect(find.text('Address saved'), findsNothing);
      expect(
        find.widgetWithText(TextFormField, '12 Green Park Road'),
        findsOneWidget,
      );
    });

    testWidgets('the address limit is reported in the server\'s own words', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository =
          FakeCustomerRepository(customer: _rahul)
            ..nextWriteError = const ApiException(
              code: ApiErrorCode.addressLimitReached,
              message:
                  'You can save up to 25 addresses. Remove one to add another.',
              status: 422,
            );

      await pumpAddresses(tester, customer: repository);
      await openAddForm(tester);
      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(find.textContaining('up to 25 addresses'), findsOneWidget);
    });
  });

  group('editing and removing', () {
    Future<FakeCustomerRepository> withTwo(WidgetTester tester) =>
        pumpAddresses(
          tester,
          addresses: <SavedAddress>[
            sampleAddress(isDefault: true),
            sampleAddress(
              id: 'addr-2',
              type: AddressType.work,
              label: 'Work',
              addressLine1: 'Connaught Place',
              addressLine2: null,
              postalCode: '110001',
            ),
          ],
        );

    Future<void> openMenu(WidgetTester tester, String label) async {
      // Anchored on the list item, not on the nearest Row: the label sits inside
      // an inner Row that does not contain the overflow button.
      final Finder item = find.ancestor(
        of: onScreen(find.text(label)),
        matching: find.byType(AddressListItem),
      );

      await tester.tap(
        find.descendant(
          of: item,
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('edit opens the form pre-filled', (WidgetTester tester) async {
      await withTwo(tester);
      await openMenu(tester, 'Work');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit address'), findsWidgets);
      expect(
        find.widgetWithText(TextFormField, 'Connaught Place'),
        findsOneWidget,
      );
    });

    testWidgets('an edit is confirmed and the list reflects the server', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await withTwo(tester);
      await openMenu(tester, 'Work');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Near the metro',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save address'));
      await tester.pumpAndSettle();

      expect(find.text('Address updated'), findsOneWidget);
      expect(find.text('Near the metro'), findsOneWidget);
      expect(repository.lastDraft!.landmark, 'Near the metro');
    });

    testWidgets('setting a different default moves it, exactly one at a time', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await withTwo(tester);
      await openMenu(tester, 'Work');
      await tester.tap(find.text('Set as default'));
      await tester.pumpAndSettle();

      expect(repository.defaultChangeCount, 1);
      expect(find.text('Default address updated'), findsOneWidget);
      expect(find.text('DEFAULT'), findsOneWidget);

      final List<SavedAddress> after = repository.addressesSnapshot;
      expect(after.where((SavedAddress a) => a.isDefault).length, 1);
      expect(after.firstWhere((SavedAddress a) => a.isDefault).label, 'Work');
    });

    testWidgets('the current default offers no "set as default"', (
      WidgetTester tester,
    ) async {
      await withTwo(tester);
      await openMenu(tester, 'Home');

      // A control that would do nothing is worse than no control.
      expect(find.text('Set as default'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('removing asks first and cancelling changes nothing', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await withTwo(tester);
      await openMenu(tester, 'Work');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove "Work"?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteCount, 0);
      expect(onScreen(find.text('Work')), findsOneWidget);
    });

    testWidgets('confirming removes it and confirms', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await withTwo(tester);
      await openMenu(tester, 'Work');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(repository.deleteCount, 1);
      expect(find.text('Address removed'), findsOneWidget);
      expect(onScreen(find.text('Work')), findsNothing);
      expect(onScreen(find.text('Home')), findsOneWidget);
    });

    testWidgets('removing the default promotes another one', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await withTwo(tester);
      await openMenu(tester, 'Home');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      // A customer with addresses always has a default.
      final List<SavedAddress> after = repository.addressesSnapshot;
      expect(after.where((SavedAddress a) => a.isDefault).length, 1);
      expect(find.text('DEFAULT'), findsOneWidget);
    });

    testWidgets('removing the last one returns to the empty state', (
      WidgetTester tester,
    ) async {
      await pumpAddresses(
        tester,
        addresses: <SavedAddress>[sampleAddress(isDefault: true)],
      );

      await openMenu(tester, 'Home');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('No saved addresses yet'), findsOneWidget);
    });

    testWidgets('an address deleted elsewhere is reported, not crashed on', (
      WidgetTester tester,
    ) async {
      final FakeCustomerRepository repository = await withTwo(tester);
      repository.nextWriteError = const ApiException(
        code: ApiErrorCode.addressNotFound,
        message: 'Gone.',
        status: 404,
      );

      await openMenu(tester, 'Work');
      await tester.tap(find.text('Set as default'));
      await tester.pumpAndSettle();

      expect(
        find.text('That address is no longer saved to your account.'),
        findsOneWidget,
      );
    });
  });
}
