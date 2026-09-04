import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:foodonthego/app.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/core/routing/app_router.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/repositories/auth_repository.dart';
import 'package:foodonthego/domain/repositories/customer_repository.dart';
import 'package:foodonthego/domain/repositories/home_repository.dart';
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
Widget wrapApp({
  required HomeRepository repository,
  ThemeData? theme,
  ConnectivityService? connectivity,
  String initialLocation = '/',
  FakeAuthRepository? auth,
  FakeCustomerRepository? customer,
  SessionStore? sessionStore,
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
