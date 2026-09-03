import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_error_code.dart';
import '../../core/config/app_environment.dart';
import '../../core/config/feature_flags.dart';
import '../../data/auth/session_store.dart';
import '../../data/fixtures/development_personas.dart';
import '../../data/repositories/api_auth_repository.dart';
import '../../data/repositories/fixture_home_repository.dart';
import '../../data/repositories/unconfigured_home_repository.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/home_repository.dart';
import 'auth_controller.dart';
import 'connectivity.dart';

/// Riverpod is the state-management choice for the customer app.
///
/// Module 01 did not name one, so it is decided here and recorded in
/// docs/16-mobile-navigation.md. Riverpod over Bloc because this app's state is
/// mostly *derived, cached, async reads* rather than long event streams, and
/// because overriding a provider is the cleanest way to swap a fixture
/// repository for a real one — which is exactly what keeps demo data out of
/// production. **Do not introduce a second state-management framework.**

/// Which persona the development harness is showing. Ignored in production,
/// where the fixture repository is never constructed.
///
/// Written as a Notifier rather than the older StateProvider, which Riverpod 3
/// removed.
class DevelopmentPersonaNotifier extends Notifier<DevelopmentPersona> {
  @override
  DevelopmentPersona build() => DevelopmentPersona.activeOrder;

  void select(DevelopmentPersona persona) => state = persona;
}

final developmentPersonaProvider =
    NotifierProvider<DevelopmentPersonaNotifier, DevelopmentPersona>(
      DevelopmentPersonaNotifier.new,
    );

/// Lets the development harness force a failure so the error screens can be seen
/// without breaking anything.
class DevelopmentForcedFailureNotifier extends Notifier<HomeFailureKind?> {
  @override
  HomeFailureKind? build() => null;

  void select(HomeFailureKind? kind) => state = kind;
}

final developmentForcedFailureProvider =
    NotifierProvider<DevelopmentForcedFailureNotifier, HomeFailureKind?>(
      DevelopmentForcedFailureNotifier.new,
    );

final featureFlagsProvider = Provider<FeatureFlags>(
  (Ref ref) => const FeatureFlags.defaults(),
);

final analyticsProvider = Provider<Analytics>(
  (Ref ref) => AppEnvironment.current.isProduction
      ? const NoopAnalytics()
      : const DebugAnalytics(),
);

final connectivityServiceProvider = Provider<ConnectivityService>((Ref ref) {
  // In development the controllable implementation lets the offline banner be
  // demonstrated; in production it is the honest always-online default until
  // real detection lands.
  final ConnectivityService service = AppEnvironment.current.allowsFixtures
      ? ControllableConnectivity()
      : const AlwaysOnlineConnectivity();
  ref.onDispose(service.dispose);
  return service;
});

final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((
  Ref ref,
) {
  final ConnectivityService service = ref.watch(connectivityServiceProvider);
  // The stream only carries *changes*, so the current value is emitted first or
  // the banner would not appear until connectivity next flipped.
  return service.changes.transform(
    StreamTransformer<ConnectivityStatus, ConnectivityStatus>.fromHandlers(
      handleData: (
        ConnectivityStatus data,
        EventSink<ConnectivityStatus> sink,
      ) => sink.add(data),
    ),
  );
});

/// The single seam between the app and its data.
///
/// This is the provider a future module overrides with an API-backed
/// implementation, and the one tests override with a stub. Because the fixture
/// branch is guarded by a compile-time constant, a production build cannot
/// resolve to it.
final homeRepositoryProvider = Provider<HomeRepository>((Ref ref) {
  if (!AppEnvironment.current.allowsFixtures) {
    // The name is real from Module 03 onwards — it comes from the signed-in
    // account. The journey and the order are still absent because the modules
    // that create them do not exist yet, and inventing either would be a lie
    // told to a real customer.
    return UnconfiguredHomeRepository(
      customerName:
          ref.watch(authControllerProvider).customer?.fullName ?? 'there',
    );
  }

  return FixtureHomeRepository(
    persona: ref.watch(developmentPersonaProvider),
    failure: ref.watch(developmentForcedFailureProvider),
  );
});

/// The home screen's state. `FutureProvider` gives loading, data and error for
/// free, which is why the screen has exactly three branches and no manual flags.
final homeDashboardProvider = FutureProvider.autoDispose<HomeDashboard>(
  (Ref ref) {
    // Kept alive briefly so switching tabs and coming straight back does not
    // re-fetch and flash a skeleton at somebody who never really left.
    final link = ref.keepAlive();
    final Timer timer = Timer(const Duration(minutes: 2), link.close);
    ref.onDispose(timer.cancel);

    return ref.watch(homeRepositoryProvider).loadDashboard();
  },
  // Automatic retry is switched OFF deliberately.
  //
  // Riverpod 3 retries a failed provider on its own with exponential backoff.
  // That is wrong here: a traveller in a signal dead zone would have the app
  // quietly re-requesting in a loop — spending battery and mobile data on
  // requests that cannot succeed — while the "Try again" button in front of
  // them becomes decorative. Recovery is an explicit user action, and the
  // offline banner is what tells them when it is worth taking.
  retry: (int retryCount, Object error) => null,
);

/// Where a session is persisted between launches.
///
/// The real store on every platform the app ships to; tests override it with the
/// in-memory one because there is no Keychain in a test binary.
final sessionStoreProvider = Provider<SessionStore>(
  (Ref ref) => SecureSessionStore(),
);

/// The HTTP client, wired to read the current token from secure storage.
///
/// The token is read per request through a callback rather than captured once,
/// so a sign-out or a re-issued session takes effect on the very next call
/// instead of leaving a stale credential inside a long-lived object.
final apiClientProvider = Provider<ApiClient>((Ref ref) {
  final SessionStore store = ref.watch(sessionStoreProvider);
  final ApiClient client = ApiClient(
    tokenReader: () async => (await store.read())?.accessToken,
    // One rejected authenticated request ends the session app-wide. Reading the
    // controller lazily (rather than watching) keeps this provider from being
    // rebuilt every time the auth state changes, which would recreate the HTTP
    // client mid-flight.
    onAuthenticationFailure: (ApiErrorCode code) => unawaited(
      ref
          .read(authControllerProvider.notifier)
          .handleAuthenticationFailure(code),
    ),
  );
  ref.onDispose(client.close);
  return client;
});

/// The seam between the auth screens and the API. Overridden in widget tests
/// with a fake that can produce every failure the server can.
final authRepositoryProvider = Provider<AuthRepository>(
  (Ref ref) => ApiAuthRepository(ref.watch(apiClientProvider)),
);
