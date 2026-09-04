import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/features/addresses/saved_addresses_screen.dart';

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

const Customer _ananya = Customer(
  id: 'cus-ananya',
  firstName: 'Ananya',
  lastName: 'Mehta',
  phone: '+919999900102',
  phoneVerified: true,
);

/// The mandatory account-switch test.
///
/// Rahul signs in, loads his addresses, signs out; Ananya signs in. She must
/// never see a frame of his — not in the list, not in the profile header, not in
/// the home greeting.
///
/// The guarantee is structural rather than a cache-clearing step somebody has to
/// remember: `AddressesController.build()` *watches* the auth state, so ending a
/// session rebuilds the provider from nothing. There is no stale state to leak
/// because there is no state that survives the session.
void main() {
  Future<void> pumpAsRahul(
    WidgetTester tester, {
    required FakeCustomerRepository customer,
    required SessionStore store,
    required FakeAuthRepository auth,
    FakeTripRepository? trips,
  }) async {
    usePhoneSurface(tester);

    await store.write(
      AuthSession(
        accessToken: 'rahul-token',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        customer: _rahul,
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: auth,
        customer: customer,
        trips: trips,
        sessionStore: store,
        signedIn: false,
        initialLocation: '/profile',
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddresses(WidgetTester tester) async {
    await tester.tap(find.text('Saved addresses'));
    await tester.pumpAndSettle();
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.widgetWithText(OutlinedButton, 'Sign out'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
  }

  testWidgets('Ananya never sees a frame of Rahul\'s data', (
    WidgetTester tester,
  ) async {
    final InMemorySessionStore store = InMemorySessionStore();
    final FakeAuthRepository auth = FakeAuthRepository(customer: _rahul);

    // One repository across both accounts, exactly like one app talking to one
    // server: same endpoints, different data once a different token arrives.
    final FakeCustomerRepository customer = FakeCustomerRepository(
      customer: _rahul,
      addresses: <SavedAddress>[
        sampleAddress(
          label: 'Home',
          addressLine1: '12 Green Park Road',
          isDefault: true,
        ),
      ],
    );

    await pumpAsRahul(tester, customer: customer, store: store, auth: auth);

    // Rahul's addresses are loaded and on screen.
    await openAddresses(tester);
    expect(find.text('12 Green Park Road, Green Park'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await signOut(tester);

    expect(find.text('Eat well on the road'), findsOneWidget);

    // Ananya signs in on the same device, through the real flow — not a widget
    // rebuild. A second pumpWidget would update the existing ProviderScope
    // rather than recreate it, and would prove nothing about state being
    // dropped.
    auth.customer = _ananya;
    customer.switchTo(_ananya, <SavedAddress>[
      sampleAddress(
        id: 'addr-a1',
        type: AddressType.work,
        label: 'Work',
        addressLine1: 'Cyber City',
        addressLine2: null,
        city: 'Gurugram',
        state: 'Haryana',
        postalCode: '122002',
        isDefault: true,
      ),
    ]);

    await tester.tap(find.text('Continue with mobile number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      _ananya.phone.substring(3),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pumpAndSettle();

    // Signed in as Ananya, on the home screen.
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();

    // Her profile header, not his — checked before anything else is tapped, so
    // one stale frame would fail here.
    expect(find.text('Ananya Mehta'), findsWidgets);
    expect(find.text('Rahul Sharma'), findsNothing);
    expect(find.text('+91 ••••••0102'), findsOneWidget);
    expect(find.text('+91 ••••••0101'), findsNothing);

    await openAddresses(tester);

    expect(find.text('Cyber City'), findsOneWidget);
    expect(find.text('12 Green Park Road, Green Park'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SavedAddressesScreen),
        matching: find.text('Home'),
      ),
      findsNothing,
    );
  });

  testWidgets('signing out empties the address state immediately', (
    WidgetTester tester,
  ) async {
    final InMemorySessionStore store = InMemorySessionStore();
    final FakeCustomerRepository customer = FakeCustomerRepository(
      customer: _rahul,
      addresses: <SavedAddress>[sampleAddress(isDefault: true)],
    );

    await pumpAsRahul(
      tester,
      customer: customer,
      store: store,
      auth: FakeAuthRepository(customer: _rahul),
    );

    await openAddresses(tester);
    expect(find.text('12 Green Park Road, Green Park'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await signOut(tester);

    // Not merely hidden behind the welcome screen — gone. The provider watches
    // the session, so ending one rebuilds it from nothing.
    expect(find.text('12 Green Park Road, Green Park'), findsNothing);
    expect(await store.read(), isNull);
  });

  testWidgets('a signed-out app makes no request for addresses', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final FakeCustomerRepository customer = FakeCustomerRepository(
      customer: _rahul,
      addresses: <SavedAddress>[sampleAddress(isDefault: true)],
    );

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: FakeAuthRepository(customer: _rahul),
        customer: customer,
        signedIn: false,
      ),
    );
    await tester.pumpAndSettle();

    // Nothing fetches personal data for somebody who is not signed in.
    expect(customer.listReads, 0);
    expect(find.text('Eat well on the road'), findsOneWidget);
  });

  testWidgets("Ananya never sees a frame of Rahul's journeys", (
    WidgetTester tester,
  ) async {
    final InMemorySessionStore store = InMemorySessionStore();
    final FakeAuthRepository auth = FakeAuthRepository(customer: _rahul);

    // One repository across both accounts, exactly like one app talking to one
    // server: same endpoints, different data once a different token arrives.
    final FakeTripRepository trips = FakeTripRepository(
      trips: <Trip>[
        sampleTrip(
          id: 'rahul-1',
          destinationName: 'Jaipur International Airport',
        ),
      ],
    );

    await pumpAsRahul(
      tester,
      customer: FakeCustomerRepository(customer: _rahul),
      store: store,
      auth: auth,
      trips: trips,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Trips'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Hauz Khas Village → Jaipur International Airport'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();
    await signOut(tester);

    expect(find.text('Eat well on the road'), findsOneWidget);

    auth.customer = _ananya;
    trips.switchTo(<Trip>[
      sampleTrip(
        id: 'ananya-1',
        originName: 'DLF Cyber City',
        destinationName: 'Sector 17 Plaza',
      ),
    ]);

    await tester.tap(find.text('Continue with mobile number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      _ananya.phone.substring(3),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Trips'),
      ),
    );
    await tester.pumpAndSettle();

    // Hers, and not one frame of his — where he was going is as sensitive as
    // where he lives.
    expect(find.text('DLF Cyber City → Sector 17 Plaza'), findsOneWidget);
    expect(
      find.text('Hauz Khas Village → Jaipur International Airport'),
      findsNothing,
    );
    expect(find.textContaining('Jaipur'), findsNothing);
  });

  testWidgets('signing out empties the journey state immediately', (
    WidgetTester tester,
  ) async {
    final InMemorySessionStore store = InMemorySessionStore();
    final FakeTripRepository trips = FakeTripRepository(
      trips: <Trip>[sampleTrip()],
    );

    await pumpAsRahul(
      tester,
      customer: FakeCustomerRepository(customer: _rahul),
      store: store,
      auth: FakeAuthRepository(customer: _rahul),
      trips: trips,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Trips'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Hauz Khas Village → Jaipur International Airport'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();
    await signOut(tester);

    // Not merely hidden behind the welcome screen — gone. `TripsController`
    // watches the session, so ending one rebuilds it from nothing.
    expect(find.text('New Delhi → Jaipur'), findsNothing);
    expect(await store.read(), isNull);
  });

  testWidgets('a signed-out app makes no request for journeys', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    final FakeTripRepository trips = FakeTripRepository(
      trips: <Trip>[sampleTrip()],
    );

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: FakeAuthRepository(customer: _rahul),
        trips: trips,
        signedIn: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(trips.listReads, 0);
    expect(find.text('Eat well on the road'), findsOneWidget);
  });
}
