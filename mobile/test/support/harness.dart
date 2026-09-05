import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:foodonthego/app.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/core/geo/polyline_codec.dart';
import 'package:foodonthego/core/location/location_service.dart';
import 'package:foodonthego/core/routing/app_router.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/discovery_facets.dart';
import 'package:foodonthego/domain/models/discovery_query.dart';
import 'package:foodonthego/domain/models/trip_route.dart';
import 'package:foodonthego/domain/repositories/auth_repository.dart';
import 'package:foodonthego/domain/repositories/customer_repository.dart';
import 'package:foodonthego/domain/repositories/home_repository.dart';
import 'package:foodonthego/domain/repositories/place_repository.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/domain/repositories/discovery_repository.dart';
import 'package:foodonthego/domain/repositories/restaurant_repository.dart';
import 'package:foodonthego/domain/repositories/route_repository.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';
import 'package:foodonthego/shared/state/connectivity.dart';
import 'package:foodonthego/shared/state/providers.dart';

/// A repository that returns exactly what a test tells it to.
///
/// Tests use this rather than the development fixtures, so editing a demo
/// persona can never silently change what a test asserts.
class StubHomeRepository implements HomeRepository {
  StubHomeRepository.value(this._dashboard) : _failure = null;

  StubHomeRepository.failing(HomeFailureKind failure)
    : _dashboard = null,
      _failure = failure;

  final HomeDashboard? _dashboard;
  final HomeFailureKind? _failure;

  /// How many times the screen asked for data — the way a test proves a refresh
  /// actually re-fetched rather than merely animating.
  int loadCount = 0;

  @override
  Future<HomeDashboard> loadDashboard() async {
    loadCount++;
    if (_failure != null) throw HomeLoadFailure(_failure);
    return _dashboard!;
  }
}

/// A scriptable stand-in for the auth API.
///
/// Every branch the server can take is reachable from here — wrong code,
/// expired code, rate limit, suspended account, network loss — which is what
/// lets the widget tests cover the failure paths without a running backend. The
/// paths that must also be proven against the real server are covered by the
/// backend feature tests and by the live integration run.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.otpLength = 6, Customer? customer})
    : customer = customer ?? sampleCustomer;

  static const Customer sampleCustomer = Customer(
    id: 'c0ffee00-0000-4000-8000-000000000001',
    firstName: 'Ravi',
    lastName: 'Kumar',
    phone: '+919876543210',
    phoneVerified: true,
  );

  final int otpLength;

  Customer customer;

  /// The code that verifies. Anything else is rejected as OTP_INVALID.
  String validCode = '123456';

  /// When true, a correct code produces a registration token instead of a
  /// session — the new-customer branch.
  bool registrationRequired = false;

  /// Thrown by the next matching call and then cleared, so a test can script a
  /// single failure followed by a success.
  ApiException? nextRequestError;
  ApiException? nextVerifyError;
  ApiException? nextRegisterError;
  ApiException? nextCurrentCustomerError;

  final List<String> requestedPhones = <String>[];
  final List<String> submittedCodes = <String>[];

  /// What register() was called with. `phone` is deliberately absent from the
  /// signature, so a test can assert the screen had no way to send one.
  Map<String, String?>? registeredWith;

  int requestCount = 0;
  int logoutCount = 0;
  int currentCustomerCount = 0;

  int resendAvailableInSeconds = 30;
  int expiresInSeconds = 300;

  ApiException? _take(ApiException? Function() read, void Function() clear) {
    final ApiException? error = read();
    clear();
    return error;
  }

  @override
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String countryCode,
  }) async {
    requestCount++;
    requestedPhones.add('+$countryCode$phone');

    final ApiException? error = _take(
      () => nextRequestError,
      () => nextRequestError = null,
    );
    if (error != null) throw error;

    return OtpRequestResult(
      maskedPhone: _mask(countryCode, phone),
      expiresInSeconds: expiresInSeconds,
      resendAvailableInSeconds: resendAvailableInSeconds,
      otpLength: otpLength,
    );
  }

  @override
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String countryCode,
    required String code,
  }) async {
    submittedCodes.add(code);

    final ApiException? error = _take(
      () => nextVerifyError,
      () => nextVerifyError = null,
    );
    if (error != null) throw error;

    if (code != validCode) {
      throw const ApiException(
        code: ApiErrorCode.otpInvalid,
        message: "That code isn't correct.",
        status: 422,
      );
    }

    if (registrationRequired) {
      return const OtpRegistrationRequired(
        registrationToken: 'test-registration-token',
        expiresInSeconds: 900,
      );
    }

    return OtpSignedIn(session);
  }

  @override
  Future<AuthSession> register({
    required String registrationToken,
    required String firstName,
    String? lastName,
    String? email,
  }) async {
    registeredWith = <String, String?>{
      'registration_token': registrationToken,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
    };

    final ApiException? error = _take(
      () => nextRegisterError,
      () => nextRegisterError = null,
    );
    if (error != null) throw error;

    customer = Customer(
      id: customer.id,
      firstName: firstName,
      lastName: lastName,
      phone: customer.phone,
      email: email,
      phoneVerified: true,
    );

    return session;
  }

  @override
  Future<Customer> currentCustomer() async {
    currentCustomerCount++;

    final ApiException? error = _take(
      () => nextCurrentCustomerError,
      () => nextCurrentCustomerError = null,
    );
    if (error != null) throw error;

    return customer;
  }

  @override
  Future<void> logout() async => logoutCount++;

  AuthSession get session => AuthSession(
    accessToken: 'test-access-token',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    customer: customer,
  );

  static String _mask(String countryCode, String national) {
    if (national.length <= 4) return '+$countryCode $national';
    final String hidden = '•' * (national.length - 4);
    return '+$countryCode $hidden${national.substring(national.length - 4)}';
  }
}

/// A scriptable stand-in for the profile and address API.
///
/// It keeps a real list and applies the server's rules to it — the first address
/// becomes the default, a new default clears the old one, deleting the default
/// promotes a survivor. A fake that skipped those would let a screen pass a test
/// while showing two defaults against the real backend.
class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({Customer? customer, List<SavedAddress>? addresses})
    : _customer = customer ?? FakeAuthRepository.sampleCustomer,
      _addresses = <SavedAddress>[...?addresses] {
    // The API returns default first; a fake that did not would let a screen pass
    // a test while showing the wrong order against the real backend.
    _sort();
  }

  Customer _customer;
  final List<SavedAddress> _addresses;

  /// Thrown by the next matching call and then cleared, so a test can script one
  /// failure followed by a success.
  ApiException? nextProfileError;
  ApiException? nextListError;
  ApiException? nextWriteError;

  int profileReads = 0;
  int listReads = 0;
  int createCount = 0;
  int deleteCount = 0;
  int defaultChangeCount = 0;

  /// What updateProfile() was called with. `phone` is deliberately impossible to
  /// pass, so a test can assert the screen had no way to send one.
  Map<String, String?>? lastProfileUpdate;

  AddressDraft? lastDraft;

  List<SavedAddress> get addressesSnapshot =>
      List<SavedAddress>.unmodifiable(_addresses);

  /// Swaps the account this repository answers for.
  ///
  /// Stands in for what the server does when a different token arrives: the same
  /// endpoints, different data. Used by the account-switch test, which must go
  /// through the real sign-in flow rather than rebuilding the widget tree — a
  /// second pumpWidget updates the existing ProviderScope instead of recreating
  /// it, so it would prove nothing about state being dropped.
  void switchTo(Customer customer, List<SavedAddress> addresses) {
    _customer = customer;
    _addresses
      ..clear()
      ..addAll(addresses);
    _sort();
  }

  ApiException? _take(ApiException? error, void Function() clear) {
    clear();
    return error;
  }

  @override
  Future<Customer> profile() async {
    profileReads++;
    final ApiException? error = _take(
      nextProfileError,
      () => nextProfileError = null,
    );
    if (error != null) throw error;

    return _customer;
  }

  @override
  Future<Customer> updateProfile({
    required String firstName,
    String? lastName,
    String? email,
    bool clearLastName = false,
    bool clearEmail = false,
  }) async {
    lastProfileUpdate = <String, String?>{
      'first_name': firstName.trim(),
      'last_name': _blank(lastName),
      'email': _blank(email),
    };

    final ApiException? error = _take(
      nextProfileError,
      () => nextProfileError = null,
    );
    if (error != null) throw error;

    _customer = Customer(
      id: _customer.id,
      firstName: firstName.trim(),
      lastName: _blank(lastName),
      // The verified number is identity: this fake cannot change it either,
      // because the interface gives it nowhere to come from.
      phone: _customer.phone,
      email: _blank(email),
      phoneVerified: _customer.phoneVerified,
      status: _customer.status,
    );

    return _customer;
  }

  @override
  Future<List<SavedAddress>> addresses() async {
    listReads++;
    final ApiException? error = _take(
      nextListError,
      () => nextListError = null,
    );
    if (error != null) throw error;

    return List<SavedAddress>.unmodifiable(_addresses);
  }

  @override
  Future<SavedAddress> createAddress(AddressDraft draft) async {
    createCount++;
    lastDraft = draft;

    final ApiException? error = _take(
      nextWriteError,
      () => nextWriteError = null,
    );
    if (error != null) throw error;

    final bool isDefault = draft.isDefault || _addresses.isEmpty;
    if (isDefault) {
      _clearDefault();
    }

    final SavedAddress created = _materialise(
      id: 'addr-${_addresses.length + 1}',
      draft: draft,
      isDefault: isDefault,
    );

    _addresses.insert(0, created);
    _sort();

    return created;
  }

  @override
  Future<SavedAddress> updateAddress(String id, AddressDraft draft) async {
    lastDraft = draft;

    final ApiException? error = _take(
      nextWriteError,
      () => nextWriteError = null,
    );
    if (error != null) throw error;

    final int index = _addresses.indexWhere((SavedAddress a) => a.id == id);
    if (index < 0) {
      throw const ApiException(
        code: ApiErrorCode.addressNotFound,
        message: 'Gone.',
        status: 404,
      );
    }

    final bool becomesDefault = draft.isDefault || _addresses[index].isDefault;
    if (draft.isDefault) {
      _clearDefault();
    }

    final SavedAddress updated = _materialise(
      id: id,
      draft: draft,
      isDefault: becomesDefault,
    );

    _addresses[index] = updated;
    _sort();

    return updated;
  }

  @override
  Future<void> deleteAddress(String id) async {
    deleteCount++;

    final ApiException? error = _take(
      nextWriteError,
      () => nextWriteError = null,
    );
    if (error != null) throw error;

    final int index = _addresses.indexWhere((SavedAddress a) => a.id == id);
    if (index < 0) return;

    final bool wasDefault = _addresses[index].isDefault;
    _addresses.removeAt(index);

    // Deleting the default promotes the newest survivor, exactly as the server
    // does — a fake that left no default would hide a real bug.
    if (wasDefault && _addresses.isNotEmpty) {
      _addresses[0] = _copyWith(_addresses[0], isDefault: true);
    }
    _sort();
  }

  @override
  Future<SavedAddress> makeDefault(String id) async {
    defaultChangeCount++;

    final ApiException? error = _take(
      nextWriteError,
      () => nextWriteError = null,
    );
    if (error != null) throw error;

    final int index = _addresses.indexWhere((SavedAddress a) => a.id == id);
    if (index < 0) {
      throw const ApiException(
        code: ApiErrorCode.addressNotFound,
        message: 'Gone.',
        status: 404,
      );
    }

    _clearDefault();
    _addresses[index] = _copyWith(_addresses[index], isDefault: true);
    _sort();

    return _addresses.firstWhere((SavedAddress a) => a.id == id);
  }

  void _clearDefault() {
    for (int i = 0; i < _addresses.length; i++) {
      if (_addresses[i].isDefault) {
        _addresses[i] = _copyWith(_addresses[i], isDefault: false);
      }
    }
  }

  void _sort() {
    _addresses.sort((SavedAddress a, SavedAddress b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return 0;
    });
  }

  SavedAddress _materialise({
    required String id,
    required AddressDraft draft,
    required bool isDefault,
  }) {
    final String label = (draft.label?.trim().isNotEmpty ?? false)
        ? draft.label!.trim()
        : switch (draft.type) {
            AddressType.home => 'Home',
            AddressType.work => 'Work',
            AddressType.other => 'Other',
          };

    final String region = <String>[
      draft.state,
      if (draft.postalCode != null && draft.postalCode!.isNotEmpty)
        draft.postalCode!,
    ].join(' ').trim();

    return SavedAddress(
      id: id,
      type: draft.type,
      label: label,
      addressLine1: draft.addressLine1.trim(),
      addressLine2: draft.addressLine2?.trim(),
      landmark: draft.landmark?.trim(),
      city: draft.city.trim(),
      state: draft.state.trim(),
      postalCode: draft.postalCode?.trim(),
      countryCode: draft.countryCode.toUpperCase(),
      formattedAddress: <String>[
        draft.addressLine1.trim(),
        if (draft.addressLine2?.trim().isNotEmpty ?? false)
          draft.addressLine2!.trim(),
        draft.city.trim(),
        region,
        draft.countryCode.toUpperCase(),
      ].where((String p) => p.isNotEmpty).join(', '),
      isDefault: isDefault,
    );
  }

  static SavedAddress _copyWith(
    SavedAddress source, {
    required bool isDefault,
  }) => SavedAddress(
    id: source.id,
    type: source.type,
    label: source.label,
    addressLine1: source.addressLine1,
    addressLine2: source.addressLine2,
    landmark: source.landmark,
    city: source.city,
    state: source.state,
    postalCode: source.postalCode,
    countryCode: source.countryCode,
    formattedAddress: source.formattedAddress,
    latitude: source.latitude,
    longitude: source.longitude,
    placeId: source.placeId,
    isDefault: isDefault,
  );

  static String? _blank(String? value) {
    final String trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// A saved address shaped like one the API returns.
SavedAddress sampleAddress({
  String id = 'addr-1',
  AddressType type = AddressType.home,
  String label = 'Home',
  String addressLine1 = '12 Green Park Road',
  String? addressLine2 = 'Green Park',
  String? landmark,
  String city = 'New Delhi',
  String state = 'Delhi',
  String? postalCode = '110016',
  bool isDefault = false,
}) {
  final String region = <String>[state, ?postalCode].join(' ').trim();

  return SavedAddress(
    id: id,
    type: type,
    label: label,
    addressLine1: addressLine1,
    addressLine2: addressLine2,
    landmark: landmark,
    city: city,
    state: state,
    postalCode: postalCode,
    countryCode: 'IN',
    formattedAddress: <String>[
      addressLine1,
      ?addressLine2,
      city,
      region,
      'IN',
    ].join(', '),
    isDefault: isDefault,
  );
}

/// Wraps a single widget in the theme and localizations it needs.
///
/// The helpers take concrete dependencies rather than a list of overrides
/// because `Override` is not exported from `flutter_riverpod`, and reaching into
/// a transitive package for a type is worse than a narrower API.
Widget wrapWidget(Widget child, {ThemeData? theme}) {
  return ProviderScope(
    child: MaterialApp(
      theme: theme ?? FotgTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppStringsDelegate(),
      ],
      supportedLocales: AppStringsDelegate.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// Boots the whole application against stubbed dependencies, so navigation and
/// auth-guard tests exercise the real router rather than an approximation.
///
/// [signedIn] seeds the session store, which is what a returning customer's
/// device looks like on launch. Left false, the app starts where a new install
/// starts: the welcome screen.
/// A trip repository that applies the *server's* rules.
///
/// The point of the exercise: a fake that accepted anything would let a screen
/// pass its tests while doing something the real backend refuses. So this one
/// resolves a saved address **through the addresses it was given** and refuses
/// an id it does not hold — which is how the cross-customer case is exercised
/// without a network — refuses two ends that are the same place, refuses a
/// coordinate outside the possible range, enforces the open limit, and keeps a
/// discarded trip out of the open list, exactly as `TripService` does.
class FakeTripRepository implements TripRepository {
  FakeTripRepository({
    List<Trip>? trips,
    List<SavedAddress>? addresses,
    this.openLimit = 20,
  }) : _trips = <Trip>[...?trips],
       _addresses = <SavedAddress>[...?addresses];

  final List<Trip> _trips;

  /// The addresses this customer owns. An id outside this list is refused the
  /// way the server refuses one belonging to somebody else: as though it does
  /// not exist, with nothing about it in the answer.
  final List<SavedAddress> _addresses;

  final int openLimit;

  /// Thrown by the next matching call and then cleared, so a test can script one
  /// failure followed by a success.
  ApiException? nextListError;
  ApiException? nextWriteError;

  int listReads = 0;
  int createCount = 0;
  int discardCount = 0;

  TripDraft? lastDraft;

  /// The exact JSON the screen would have put on the wire. Tests assert on this
  /// to prove that no customer id, status or route field is ever sent.
  Map<String, dynamic>? lastPayload;

  List<Trip> get snapshot => List<Trip>.unmodifiable(_trips);

  /// Stands in for what the server does when a different token arrives: the same
  /// endpoints, different data.
  void switchTo(List<Trip> trips, {List<SavedAddress>? addresses}) {
    _trips
      ..clear()
      ..addAll(trips);

    if (addresses != null) {
      _addresses
        ..clear()
        ..addAll(addresses);
    }
  }

  @override
  Future<List<Trip>> trips({TripScope scope = TripScope.open}) async {
    listReads++;

    final ApiException? error = nextListError;
    if (error != null) {
      nextListError = null;
      throw error;
    }

    final List<Trip> matching = switch (scope) {
      TripScope.open => _trips.where((Trip t) => !t.isCancelled).toList(),
      TripScope.cancelled => _trips.where((Trip t) => t.isCancelled).toList(),
      TripScope.all => <Trip>[..._trips],
    };

    return List<Trip>.unmodifiable(matching.reversed);
  }

  @override
  Future<Trip?> currentTrip() async {
    final List<Trip> open = await trips();
    return open.isEmpty ? null : open.first;
  }

  @override
  Future<Trip> trip(String id) async {
    for (final Trip candidate in _trips) {
      if (candidate.id == id) return candidate;
    }
    throw const ApiException(
      code: ApiErrorCode.tripNotFound,
      message: 'That journey does not exist.',
      status: 404,
    );
  }

  @override
  Future<Trip> createTrip(TripDraft draft) async {
    createCount++;
    lastDraft = draft;
    lastPayload = draft.toJson();
    _throwScriptedWriteError();

    if (_trips.where((Trip t) => !t.isCancelled).length >= openLimit) {
      throw const ApiException(
        code: ApiErrorCode.tripLimitReached,
        message: 'Too many planned journeys.',
        status: 422,
      );
    }

    final TripEndpoint origin = _resolve(draft.origin);
    final TripEndpoint destination = _resolve(draft.destination);

    if (_isSamePlace(origin, destination)) {
      throw const ApiException(
        code: ApiErrorCode.sameLocation,
        message: 'Your starting point and destination are the same place.',
        status: 422,
      );
    }

    final Trip created = Trip(
      id: 'trip-${_trips.length + 1}',
      status: TripStatus.routePending,
      // Always. Module 05 never calculates a route, and a fake that returned
      // READY would let a screen render a distance in a test and nowhere else.
      routeStatus: RouteStatus.notCalculated,
      origin: origin,
      destination: destination,
      createdAt: DateTime.now().toUtc(),
    );

    _trips.add(created);
    return created;
  }

  @override
  Future<Trip> discardTrip(String id) async {
    discardCount++;
    _throwScriptedWriteError();

    final Trip existing = await trip(id);

    if (existing.isCancelled) {
      throw const ApiException(
        code: ApiErrorCode.tripNotEditable,
        message: 'That journey has already been discarded.',
        status: 422,
      );
    }

    final Trip discarded = Trip(
      id: existing.id,
      status: TripStatus.cancelled,
      routeStatus: existing.routeStatus,
      origin: existing.origin,
      destination: existing.destination,
      cancelledAt: DateTime.now().toUtc(),
      createdAt: existing.createdAt,
    );

    _trips[_trips.indexOf(existing)] = discarded;
    return discarded;
  }

  void _throwScriptedWriteError() {
    final ApiException? error = nextWriteError;
    if (error != null) {
      nextWriteError = null;
      throw error;
    }
  }

  /// What the server does with one end of the request.
  ///
  /// A saved address is looked up in *this customer's* list and copied out of
  /// it; the client's own values for that end are ignored entirely, which is the
  /// property that makes the id the only thing worth sending.
  TripEndpoint _resolve(TripLocation location) {
    if (location.isSavedAddress) {
      for (final SavedAddress address in _addresses) {
        if (address.id != location.savedAddressId) continue;

        if (!address.hasCoordinates) {
          throw const ApiException(
            code: ApiErrorCode.savedAddressNotLocated,
            message: 'That saved address has no location.',
            status: 422,
          );
        }

        return TripEndpoint(
          sourceType: LocationSourceType.savedAddress,
          displayName: address.label,
          formattedAddress: address.formattedAddress,
          latitude: address.latitude!,
          longitude: address.longitude!,
          city: address.city,
          countryCode: address.countryCode,
        );
      }

      // Not this customer's. Indistinguishable from an id that never existed —
      // no hint that somebody else's address is real.
      throw const ApiException(
        code: ApiErrorCode.addressNotFound,
        message: 'That address is no longer on your account.',
        status: 404,
      );
    }

    final double? latitude = location.latitude;
    final double? longitude = location.longitude;

    if (latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        (latitude == 0 && longitude == 0)) {
      throw const ApiException(
        code: ApiErrorCode.invalidCoordinates,
        message: 'That place has no location we can use.',
        status: 422,
      );
    }

    return TripEndpoint(
      sourceType: location.sourceType,
      displayName: location.displayName,
      formattedAddress: location.formattedAddress,
      latitude: latitude,
      longitude: longitude,
      placeId: location.placeId,
      city: location.city,
      region: location.region,
      countryCode: location.countryCode,
      postalCode: location.postalCode,
    );
  }

  bool _isSamePlace(TripEndpoint a, TripEndpoint b) {
    if (a.placeId != null && a.placeId == b.placeId) return true;

    // The server's 75 m rule, in the crude form a test needs: four decimal
    // places is roughly 11 m.
    return (a.latitude - b.latitude).abs() < 0.0007 &&
        (a.longitude - b.longitude).abs() < 0.0007;
  }
}

/// A place repository that answers from a fixed list.
///
/// Records what it was asked, and can be made slow, so the debounce and the
/// stale-result guard can be tested at all: the race this module has to rule out
/// only appears when an older query answers *after* a newer one.
class FakePlaceRepository implements PlaceRepository {
  FakePlaceRepository({Map<String, List<PlaceSuggestion>>? results})
    : _results = results ?? _defaultResults();

  final Map<String, List<PlaceSuggestion>> _results;

  /// Per-query delay. A query with no entry answers immediately.
  final Map<String, Duration> delays = <String, Duration>{};

  final List<String> queries = <String>[];
  final List<String?> sessionTokens = <String?>[];

  int detailsCount = 0;
  int reverseCount = 0;

  ApiException? nextSearchError;
  ApiException? nextDetailsError;

  /// Failures scripted per query, applied after that query's delay. Needed
  /// wherever two queries are in flight at once: a single scripted error is
  /// claimed by whichever call reaches it first, which is not necessarily the
  /// one the test meant.
  final Map<String, ApiException> searchErrors = <String, ApiException>{};

  /// What reverse geocoding answers. Null means "this point has no name", which
  /// is a success.
  PlaceDetails? reverseResult = const PlaceDetails(
    placeId: 'dev:green-park',
    displayName: 'Green Park',
    formattedAddress: 'Green Park, New Delhi, Delhi 110016',
    latitude: 28.5590,
    longitude: 77.2070,
    city: 'New Delhi',
    region: 'Delhi',
    countryCode: 'IN',
  );

  static Map<String, List<PlaceSuggestion>> _defaultResults() =>
      <String, List<PlaceSuggestion>>{
        'jaipur': const <PlaceSuggestion>[
          PlaceSuggestion(
            placeId: 'dev:jaipur-airport',
            primaryText: 'Jaipur International Airport',
            secondaryText: 'Sanganer, Jaipur, Rajasthan',
          ),
        ],
        'jai': const <PlaceSuggestion>[
          PlaceSuggestion(
            placeId: 'dev:jaipur-airport',
            primaryText: 'Jaipur International Airport',
            secondaryText: 'Sanganer, Jaipur, Rajasthan',
          ),
          PlaceSuggestion(
            placeId: 'dev:hawa-mahal',
            primaryText: 'Hawa Mahal',
            secondaryText: 'Badi Choupad, Jaipur, Rajasthan',
          ),
        ],
        'delhi': const <PlaceSuggestion>[
          PlaceSuggestion(
            placeId: 'dev:connaught-place',
            primaryText: 'Connaught Place',
            secondaryText: 'New Delhi, Delhi',
          ),
        ],
      };

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    String? sessionToken,
  }) async {
    queries.add(query);
    sessionTokens.add(sessionToken);

    final Duration? delay = delays[query.toLowerCase()];
    if (delay != null) await Future<void>.delayed(delay);

    final ApiException? scripted = searchErrors[query.toLowerCase()];
    if (scripted != null) throw scripted;

    final ApiException? error = nextSearchError;
    if (error != null) {
      nextSearchError = null;
      throw error;
    }

    return _results[query.toLowerCase()] ?? const <PlaceSuggestion>[];
  }

  @override
  Future<PlaceDetails> details(String placeId, {String? sessionToken}) async {
    detailsCount++;
    sessionTokens.add(sessionToken);

    final ApiException? error = nextDetailsError;
    if (error != null) {
      nextDetailsError = null;
      throw error;
    }

    return switch (placeId) {
      'dev:jaipur-airport' => const PlaceDetails(
        placeId: 'dev:jaipur-airport',
        displayName: 'Jaipur International Airport',
        formattedAddress: 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
        latitude: 26.8242,
        longitude: 75.8122,
        city: 'Jaipur',
        region: 'Rajasthan',
        countryCode: 'IN',
        postalCode: '302029',
      ),
      'dev:hawa-mahal' => const PlaceDetails(
        placeId: 'dev:hawa-mahal',
        displayName: 'Hawa Mahal',
        formattedAddress: 'Hawa Mahal Road, Badi Choupad, Jaipur, Rajasthan',
        latitude: 26.9239,
        longitude: 75.8267,
        city: 'Jaipur',
        region: 'Rajasthan',
        countryCode: 'IN',
      ),
      _ => const PlaceDetails(
        placeId: 'dev:connaught-place',
        displayName: 'Connaught Place',
        formattedAddress: 'Connaught Place, New Delhi, Delhi 110001',
        latitude: 28.6315,
        longitude: 77.2167,
        city: 'New Delhi',
        region: 'Delhi',
        countryCode: 'IN',
      ),
    };
  }

  @override
  Future<PlaceDetails?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    reverseCount++;
    return reverseResult;
  }
}

/// A location service that can produce every outcome on demand.
///
/// The six failure branches cannot otherwise be exercised: reaching them for
/// real needs six differently-configured handsets, and the one that matters most
/// — location switched off at the device while permission is granted — needs a
/// state a simulator will not enter on request.
class FakeLocationService implements LocationService {
  FakeLocationService({this.result = const LocationFix(_delhi)});

  static const DeviceLocation _delhi = DeviceLocation(
    latitude: 28.5590,
    longitude: 77.2070,
    accuracyMetres: 12,
  );

  LocationResult result;

  /// How long the device takes to answer. Lets a test see the "Finding you…"
  /// state, which is otherwise gone within a frame.
  Duration delay = Duration.zero;

  /// Never answers at all — a browser with an unanswered permission prompt, or
  /// a platform channel that has gone quiet. The screen has to survive it.
  bool hangs = false;

  int calls = 0;
  int settingsOpened = 0;
  bool settingsCanOpen = true;

  @override
  Future<LocationResult> currentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    calls++;
    if (hangs) return Completer<LocationResult>().future;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return result;
  }

  @override
  Future<bool> openPermissionSettings() async {
    settingsOpened++;
    return settingsCanOpen;
  }
}

/// A trip for a test to work with: Hauz Khas to Jaipur Airport, real
/// coordinates, no route calculated — because no trip in this module has one.
Trip sampleTrip({
  String id = 'trip-1',
  String originName = 'Hauz Khas Village',
  String destinationName = 'Jaipur International Airport',
  TripStatus status = TripStatus.routePending,
  RouteStatus routeStatus = RouteStatus.notCalculated,
  LocationSourceType originSource = LocationSourceType.currentLocation,
  DateTime? createdAt,
}) {
  return Trip(
    id: id,
    status: status,
    routeStatus: routeStatus,
    origin: TripEndpoint(
      sourceType: originSource,
      displayName: originName,
      formattedAddress: 'Hauz Khas, New Delhi, Delhi 110016',
      latitude: 28.5494,
      longitude: 77.2001,
      city: 'New Delhi',
      region: 'Delhi',
      countryCode: 'IN',
    ),
    destination: TripEndpoint(
      sourceType: LocationSourceType.placeSearch,
      displayName: destinationName,
      formattedAddress: 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
      latitude: 26.8242,
      longitude: 75.8122,
      placeId: 'dev:jaipur-airport',
      city: 'Jaipur',
      region: 'Rajasthan',
      countryCode: 'IN',
    ),
    createdAt: createdAt ?? DateTime.now().toUtc(),
  );
}

/// A route repository that behaves like the server.
///
/// It counts calls, because the property this module is judged on is **not
/// calling the provider**: a screen that recalculates on every rebuild is a bill,
/// and the only way to catch that is to count.
///
/// Like its siblings it applies the server's rules rather than accepting
/// anything: selection replaces the whole set, exactly one route is ever
/// selected, and a failure leaves what was already stored alone.
class FakeRouteRepository implements RouteRepository {
  FakeRouteRepository({
    Trip? trip,
    this.alternatives = 1,
    bool calculated = false,
  }) : _trip = trip ?? sampleTrip() {
    if (calculated) _materialise();
  }

  final int alternatives;

  Trip _trip;
  List<TripRoute> _routes = const <TripRoute>[];

  int readCalls = 0;
  int calculateCalls = 0;
  int selectCalls = 0;

  /// Scripted failures. Cleared after they fire, so a test can script one
  /// failure followed by a success.
  ApiException? nextReadError;
  ApiException? nextCalculateError;
  ApiException? nextSelectError;

  /// Per-call delay, so a test can see a loading state or race two selections.
  Duration calculateDelay = Duration.zero;
  Duration selectDelay = Duration.zero;

  /// What the provider is pretending to be. Anything but a real name makes the
  /// screen show its development notice.
  String provider = 'google';

  TripRoutes get _snapshot => TripRoutes(trip: _trip, routes: _routes);

  void _materialise() {
    _routes = <TripRoute>[
      for (int index = 0; index < alternatives; index++)
        TripRoute(
          id: 'route-$index',
          provider: provider,
          providerRouteIndex: index,
          summary: index == 0 ? 'via NH 48' : 'via NH 148N',
          distanceMeters: 278000 - (index * 13000),
          durationSeconds: 16200 + (index * 840),
          trafficDurationSeconds: index == 0 ? 17100 : null,
          trafficDelaySeconds: index == 0 ? 900 : null,
          encodedPolyline: sampleRouteGeometry(),
          bounds: const RouteBounds(
            north: 28.5494,
            south: 26.8242,
            east: 77.2001,
            west: 75.8122,
          ),
          isRecommended: index == 0,
          isSelected: index == 0,
          calculatedAt: DateTime.now().toUtc(),
        ),
    ];

    _trip = _withStatus(RouteStatus.ready, _routes.first);
  }

  Trip _withStatus(RouteStatus status, TripRoute? selected) => Trip(
    id: _trip.id,
    status: _trip.status,
    routeStatus: status,
    origin: _trip.origin,
    destination: _trip.destination,
    cancelledAt: _trip.cancelledAt,
    createdAt: _trip.createdAt,
    selectedRoute: selected == null
        ? null
        : RouteSummary(
            routeId: selected.id,
            distanceMeters: selected.distanceMeters,
            durationSeconds: selected.durationSeconds,
            trafficDurationSeconds: selected.trafficDurationSeconds,
            trafficDelaySeconds: selected.trafficDelaySeconds,
            summary: selected.summary,
            calculatedAt: selected.calculatedAt,
          ),
  );

  @override
  Future<TripRoutes> routes(String tripId) async {
    readCalls++;

    final ApiException? error = nextReadError;
    if (error != null) {
      nextReadError = null;
      throw error;
    }

    return _snapshot;
  }

  @override
  Future<TripRoutes> calculate(String tripId, {bool refresh = false}) async {
    calculateCalls++;

    if (calculateDelay > Duration.zero) {
      await Future<void>.delayed(calculateDelay);
    }

    final ApiException? error = nextCalculateError;
    if (error != null) {
      nextCalculateError = null;

      // A failure leaves what was already stored alone — the server does the
      // same, because losing a working route to a failed refresh punishes the
      // customer for an outage.
      if (_routes.isEmpty) {
        _trip = _withStatus(
          error.code == ApiErrorCode.routeNoRouteFound
              ? RouteStatus.noRoute
              : RouteStatus.failed,
          null,
        );
      }

      throw error;
    }

    _materialise();

    return _snapshot;
  }

  @override
  Future<TripRoutes> select(String tripId, String routeId) async {
    selectCalls++;

    if (selectDelay > Duration.zero) {
      await Future<void>.delayed(selectDelay);
    }

    final ApiException? error = nextSelectError;
    if (error != null) {
      nextSelectError = null;
      throw error;
    }

    TripRoute? chosen;

    _routes = _routes
        .map((TripRoute route) {
          final bool isSelected = route.id == routeId;
          final TripRoute updated = TripRoute(
            id: route.id,
            provider: route.provider,
            providerRouteIndex: route.providerRouteIndex,
            summary: route.summary,
            distanceMeters: route.distanceMeters,
            durationSeconds: route.durationSeconds,
            trafficDurationSeconds: route.trafficDurationSeconds,
            trafficDelaySeconds: route.trafficDelaySeconds,
            encodedPolyline: route.encodedPolyline,
            bounds: route.bounds,
            isRecommended: route.isRecommended,
            isSelected: isSelected,
            calculatedAt: route.calculatedAt,
          );

          if (isSelected) chosen = updated;

          return updated;
        })
        .toList(growable: false);

    _trip = _withStatus(RouteStatus.ready, chosen);

    return _snapshot;
  }
}

/// A decodable line from Hauz Khas to Jaipur airport.
///
/// Real endpoints, synthetic geometry: it exists so a widget test can decode
/// something and draw it, not to stand in for a road.
String sampleRouteGeometry() {
  final List<GeoPoint> points = <GeoPoint>[
    for (int i = 0; i <= 20; i++)
      GeoPoint(
        28.5494 + (26.8242 - 28.5494) * (i / 20),
        77.2001 + (75.8122 - 77.2001) * (i / 20),
      ),
  ];

  return PolylineCodec.encode(points);
}

/// A resolved place, for tests that build a [TripLocation] directly.
PlaceDetails samplePlace({
  String placeId = 'dev:jaipur-airport',
  String displayName = 'Jaipur International Airport',
  double latitude = 26.8242,
  double longitude = 75.8122,
}) => PlaceDetails(
  placeId: placeId,
  displayName: displayName,
  formattedAddress: 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
  latitude: latitude,
  longitude: longitude,
  city: 'Jaipur',
  region: 'Rajasthan',
  countryCode: 'IN',
);

/// Restaurants along a route, without a server.
///
/// Positions are computed from a fraction along the sample route and a stated
/// perpendicular offset, exactly as the backend's fixtures are — so a test that
/// says "800 metres off the route at the halfway point" gets one, rather than a
/// coordinate somebody hoped looked right.
class FakeDiscoveryRepository implements DiscoveryRepository {
  FakeDiscoveryRepository({
    List<DiscoveredRestaurant>? restaurants,
    this.provider = 'google',
    this.corridorMetres = 5000,
    this.facets = const DiscoveryFacets(),
    this.responder,
  }) : _restaurants = restaurants ?? <DiscoveredRestaurant>[sampleRestaurant()];

  final List<DiscoveredRestaurant> _restaurants;
  final String provider;
  final int corridorMetres;

  /// The filter options the "server" advertises for this route.
  final DiscoveryFacets facets;

  /// A scripted answer per query.
  ///
  /// Deliberately a script rather than a re-implementation of the server's
  /// filtering. A fake that filtered by itself would let a test pass while the
  /// real request carried no filters at all — the assertion would be on the
  /// fake's arithmetic, not on the client's behaviour. What the client is
  /// responsible for is *which query it sends*, and that is what [queries]
  /// records.
  final RestaurantDiscovery Function(DiscoveryQuery query)? responder;

  int discoverCalls = 0;

  /// Every query the client asked for, in order.
  final List<DiscoveryQuery> queries = <DiscoveryQuery>[];

  DiscoveryQuery? get lastQuery => queries.isEmpty ? null : queries.last;

  /// Scripted failure. Cleared after it fires, so a test can script one failure
  /// followed by a success.
  ApiException? nextError;

  Duration delay = Duration.zero;

  /// A delay chosen per call, so a test can make an early request finish after
  /// a later one and prove the stale answer is discarded.
  Duration Function(DiscoveryQuery query)? delayFor;

  /// A failure chosen per query, for the same reason: [nextError] fires for
  /// whichever request resolves first, which is the wrong one when the point of
  /// the test is that a *particular* request failed.
  ApiException? Function(DiscoveryQuery query)? errorFor;

  @override
  Future<RestaurantDiscovery> discover(
    String tripId, {
    DiscoveryQuery query = DiscoveryQuery.unfiltered,
  }) async {
    discoverCalls++;
    queries.add(query);

    final Duration wait = delayFor?.call(query) ?? delay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);

    final ApiException? scriptedError = errorFor?.call(query);
    if (scriptedError != null) throw scriptedError;

    final ApiException? error = nextError;

    if (error != null) {
      nextError = null;
      throw error;
    }

    final RestaurantDiscovery? scripted = responder?.call(query);
    if (scripted != null) return scripted;

    return RestaurantDiscovery(
      restaurants: _restaurants,
      routeId: 'route-0',
      provider: provider,
      corridorMetres: corridorMetres,
      closedOnly:
          _restaurants.isNotEmpty &&
          !_restaurants.any(
            (DiscoveredRestaurant r) => r.availability.isActionable,
          ),
      candidatesConsidered: _restaurants.length,
      facets: facets,
      total: _restaurants.length,
      eligibleTotal: _restaurants.length,
      page: query.page,
      perPage: _restaurants.length,
      lastPage: 1,
    );
  }
}

/// A discovery response built to order, for a test that needs to script one.
RestaurantDiscovery sampleDiscovery({
  List<DiscoveredRestaurant> restaurants = const <DiscoveredRestaurant>[],
  DiscoveryFacets facets = const DiscoveryFacets(),
  int? total,
  int? eligibleTotal,
  int page = 1,
  int? perPage,
  int lastPage = 1,
  bool hasMore = false,
  bool filteredEmpty = false,
  String provider = 'google',
  int corridorMetres = 5000,
}) => RestaurantDiscovery(
  restaurants: restaurants,
  routeId: 'route-0',
  provider: provider,
  corridorMetres: corridorMetres,
  facets: facets,
  total: total ?? restaurants.length,
  eligibleTotal: eligibleTotal ?? total ?? restaurants.length,
  page: page,
  perPage: perPage ?? restaurants.length,
  lastPage: lastPage,
  hasMore: hasMore,
  filteredEmpty: filteredEmpty,
  candidatesConsidered: restaurants.length,
);

/// One discovered restaurant, with every figure stated rather than defaulted.
DiscoveredRestaurant sampleRestaurant({
  String id = 'restaurant-1',
  String name = 'Highway Spice Kitchen',
  RestaurantAvailability availability = RestaurantAvailability.open,
  int distanceAheadMetres = 68400,
  int proximityMetres = 1800,
  int? detourDurationSeconds = 240,
  int? detourDistanceMetres = 1700,
  int? timeAheadSeconds = 3600,
  bool requiresBacktracking = false,
  List<String> cuisines = const <String>['North Indian', 'Vegetarian'],
  List<String> facilities = const <String>['Parking', 'Restroom'],
  int? priceLevel = 2,
  double? rating,
  int? reviewCount,
  bool isAcceptingOrders = true,
  GeoPoint position = const GeoPoint(27.6916, 76.5096),
}) => DiscoveredRestaurant(
  id: id,
  name: name,
  position: position,
  route: RouteRelation(
    proximityMetres: proximityMetres,
    distanceAheadMetres: distanceAheadMetres,
    detourDistanceMetres: detourDistanceMetres,
    detourDurationSeconds: detourDurationSeconds,
    timeAheadSeconds: timeAheadSeconds,
    requiresBacktracking: requiresBacktracking,
  ),
  availability: availability,
  cuisines: cuisines,
  facilities: facilities,
  priceLevel: priceLevel,
  rating: rating,
  reviewCount: reviewCount,
  isAcceptingOrders: isAcceptingOrders,
);

Widget wrapApp({
  required HomeRepository repository,
  ThemeData? theme,
  ConnectivityService? connectivity,
  String initialLocation = '/',
  FakeAuthRepository? auth,
  FakeCustomerRepository? customer,
  SessionStore? sessionStore,
  FakeTripRepository? trips,
  FakePlaceRepository? places,
  FakeLocationService? location,
  FakeRouteRepository? routes,
  FakeDiscoveryRepository? discovery,
  FakeRestaurantRepository? restaurants,
  bool signedIn = true,
}) {
  final FakeAuthRepository authRepository = auth ?? FakeAuthRepository();
  final FakeCustomerRepository customerRepository =
      customer ?? FakeCustomerRepository();
  final SessionStore store = sessionStore ?? InMemorySessionStore();

  if (signedIn) {
    // Fire-and-forget: the in-memory store completes synchronously, and the
    // controller reads it on its first microtask.
    store.write(authRepository.session);
  }

  return ProviderScope(
    // The list type is inferred: `Override` is not exported from
    // flutter_riverpod, and importing it from a transitive package to write an
    // annotation the compiler can work out itself is not worth the coupling.
    overrides: [
      homeRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(authRepository),
      customerRepositoryProvider.overrideWithValue(customerRepository),
      tripRepositoryProvider.overrideWithValue(trips ?? FakeTripRepository()),
      placeRepositoryProvider.overrideWithValue(
        places ?? FakePlaceRepository(),
      ),
      routeRepositoryProvider.overrideWithValue(
        routes ?? FakeRouteRepository(),
      ),
      discoveryRepositoryProvider.overrideWithValue(
        discovery ?? FakeDiscoveryRepository(),
      ),
      restaurantRepositoryProvider.overrideWithValue(
        restaurants ?? FakeRestaurantRepository(),
      ),
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocationService(),
      ),
      sessionStoreProvider.overrideWithValue(store),
      if (connectivity != null)
        connectivityServiceProvider.overrideWithValue(connectivity),
      routerProvider.overrideWith((Ref ref) {
        final GoRouter router = createRouter(
          ref: ref,
          initialLocation: initialLocation,
        );
        ref.onDispose(router.dispose);
        return router;
      }),
    ],
    child: const FoodOnTheGoApp(),
  );
}

/// A phone-shaped surface. The 800x600 default is neither a phone nor tall
/// enough to lay the home screen out without spurious overflow.
void usePhoneSurface(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// One restaurant's page, without a server.
///
/// Records every request, so a test can assert on *which* restaurant the
/// screen asked for rather than on what this fake decided to return — the
/// client's job is the request, and that is what is checked.
class FakeRestaurantRepository implements RestaurantRepository {
  FakeRestaurantRepository({this.detailToReturn, this.responder});

  final RestaurantDetail? detailToReturn;

  /// A scripted answer per request, for the tests that need two different
  /// restaurants or a per-request delay.
  final RestaurantDetail Function(String tripId, String restaurantId)?
  responder;

  int calls = 0;

  final List<({String tripId, String restaurantId})> requests =
      <({String tripId, String restaurantId})>[];

  ({String tripId, String restaurantId})? get lastRequest =>
      requests.isEmpty ? null : requests.last;

  ApiException? nextError;

  Duration delay = Duration.zero;

  /// A delay chosen per restaurant, so a test can make an early request finish
  /// after a later one and prove the stale answer is discarded.
  Duration Function(String restaurantId)? delayFor;

  /// A failure chosen per restaurant, for the same reason: [nextError] fires
  /// for whichever request resolves first, which is the wrong one when the
  /// point of the test is that a *particular* request failed.
  ApiException? Function(String restaurantId)? errorFor;

  @override
  Future<RestaurantDetail> detail({
    required String tripId,
    required String restaurantId,
  }) async {
    calls++;
    requests.add((tripId: tripId, restaurantId: restaurantId));

    final Duration wait = delayFor?.call(restaurantId) ?? delay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);

    final ApiException? scripted = errorFor?.call(restaurantId);
    if (scripted != null) throw scripted;

    final ApiException? error = nextError;

    if (error != null) {
      nextError = null;
      throw error;
    }

    return responder?.call(tripId, restaurantId) ??
        detailToReturn ??
        sampleRestaurantDetail();
  }
}

/// One restaurant page, with every figure stated rather than defaulted.
RestaurantDetail sampleRestaurantDetail({
  DiscoveredRestaurant? restaurant,
  RestaurantOrderingState ordering = RestaurantOrderingState.openAccepting,
  String? description = 'A highway kitchen on the Delhi-Jaipur road.',
  String? publicPhone = '+911412345678',
  List<RestaurantImage> media = const <RestaurantImage>[],
  RestaurantHours? hours,
  DateTime? generatedAt,
  bool routeFromCache = true,
}) => RestaurantDetail(
  restaurant: restaurant ?? sampleRestaurant(),
  ordering: ordering,
  description: description,
  publicPhone: publicPhone,
  media: media,
  hours: hours ?? sampleHours(),
  generatedAt: generatedAt ?? DateTime.now(),
  routeFromCache: routeFromCache,
);

/// An ordinary week: open 08:00 to 22:00, every day.
RestaurantHours sampleHours({
  String timezone = 'Asia/Kolkata',
  List<OpeningWindow>? today,
  List<DayHours>? week,
  DateTime? closesAt,
  DateTime? nextOpenAt,
}) {
  const OpeningWindow ordinary = OpeningWindow(
    opensAt: '08:00:00',
    closesAt: '22:00:00',
  );

  return RestaurantHours(
    timezone: timezone,
    today: today ?? const <OpeningWindow>[ordinary],
    week:
        week ??
        <DayHours>[
          for (int day = 0; day <= 6; day++)
            DayHours(
              dayOfWeek: day,
              isToday: day == 0,
              windows: const <OpeningWindow>[ordinary],
            ),
        ],
    closesAt: closesAt,
    nextOpenAt: nextOpenAt,
  );
}

/// One photograph.
RestaurantImage sampleImage({
  String id = 'image-1',
  String url = 'https://cdn.example.test/1.jpg',
  String? altText,
}) => RestaurantImage(id: id, url: url, thumbnailUrl: url, altText: altText);
