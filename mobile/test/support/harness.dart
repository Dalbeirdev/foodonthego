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
import 'package:foodonthego/domain/repositories/auth_repository.dart';
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
  SessionStore? sessionStore,
  bool signedIn = true,
}) {
  final FakeAuthRepository authRepository = auth ?? FakeAuthRepository();
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
