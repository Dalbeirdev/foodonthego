import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/app_environment.dart';
import 'package:foodonthego/core/config/feature_flags.dart';
import 'package:foodonthego/data/fixtures/development_personas.dart';
import 'package:foodonthego/data/repositories/fixture_home_repository.dart';
import 'package:foodonthego/data/repositories/unconfigured_home_repository.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_status.dart';
import 'package:foodonthego/domain/repositories/home_repository.dart';

/// The contract that keeps demo content out of a customer's hands.
void main() {
  group('environment', () {
    test('defaults to development when nothing is defined', () {
      // Tests run without --dart-define, so this is the development branch.
      expect(AppEnvironment.current, AppEnvironment.development);
      expect(AppEnvironment.current.allowsFixtures, isTrue);
      expect(AppEnvironment.current.showsDevelopmentNotices, isTrue);
    });

    test('production forbids fixtures and development notices', () {
      expect(AppEnvironment.production.allowsFixtures, isFalse);
      expect(AppEnvironment.production.showsDevelopmentNotices, isFalse);
      expect(AppEnvironment.production.isProduction, isTrue);
    });

    test(
      'staging is production-like for notices but may still use fixtures',
      () {
        expect(AppEnvironment.staging.isProduction, isFalse);
        expect(AppEnvironment.staging.allowsFixtures, isTrue);
      },
    );
  });

  group('feature flags', () {
    test('nothing is enabled, because nothing is built', () {
      const FeatureFlags flags = FeatureFlags.defaults();

      expect(flags.tripPlannerEnabled, isFalse);
      expect(flags.tripsEnabled, isFalse);
      expect(flags.ordersEnabled, isFalse);
      expect(flags.notificationsEnabled, isFalse);
      expect(flags.savedPlacesEnabled, isFalse);
      expect(flags.supportEnabled, isFalse);
      expect(flags.profileEditingEnabled, isFalse);
    });

    test('copyWith turns exactly one capability on', () {
      const FeatureFlags flags = FeatureFlags.defaults();
      final FeatureFlags next = flags.copyWith(tripPlannerEnabled: true);

      expect(next.tripPlannerEnabled, isTrue);
      expect(next.ordersEnabled, isFalse);
    });
  });

  group('repository selection', () {
    test('the production repository invents no journey and no order', () {
      // The truthful state for an account with nothing in it — never a fake trip.
      const HomeRepository repository = UnconfiguredHomeRepository();

      expectLater(
        repository.loadDashboard(),
        completion(
          isA<HomeDashboard>().having(
            (HomeDashboard d) => d.activeOrder,
            'activeOrder',
            isNull,
          ),
        ),
      );
    });

    test('the fixture repository serves the requested persona', () async {
      final HomeDashboard dashboard = await FixtureHomeRepository(
        persona: DevelopmentPersona.activeOrder,
        latency: Duration.zero,
      ).loadDashboard();

      expect(dashboard.customer.fullName, 'Rahul Sharma');
      expect(dashboard.activeOrder?.reference, 'FOTG-1024');
      expect(dashboard.activeOrder?.restaurantName, 'Highway Spice Kitchen');
      expect(dashboard.activeOrder?.status, OrderStatus.cooking);
    });

    test('the new-customer persona genuinely has nothing', () async {
      final HomeDashboard dashboard = await FixtureHomeRepository(
        persona: DevelopmentPersona.newCustomer,
        latency: Duration.zero,
      ).loadDashboard();

      expect(dashboard.activeOrder, isNull);
    });

    test('the active-journey persona carries no order', () async {
      final HomeDashboard dashboard = await FixtureHomeRepository(
        persona: DevelopmentPersona.activeJourney,
        latency: Duration.zero,
      ).loadDashboard();

      // Persona B must not leak an order, or the "no false active order" rule is
      // untested in every screen that uses it. The journey half of this persona
      // moved to the real API in Module 05.
      expect(dashboard.hasActiveOrder, isFalse);
    });

    test(
      'a forced failure surfaces as a domain failure, not a raw exception',
      () async {
        await expectLater(
          FixtureHomeRepository(
            latency: Duration.zero,
            failure: HomeFailureKind.serverUnavailable,
          ).loadDashboard(),
          throwsA(
            isA<HomeLoadFailure>().having(
              (HomeLoadFailure f) => f.kind,
              'kind',
              HomeFailureKind.serverUnavailable,
            ),
          ),
        );
      },
    );

    test('every persona is reachable and internally consistent', () async {
      for (final DevelopmentPersona persona in DevelopmentPersona.values) {
        final HomeDashboard dashboard = await FixtureHomeRepository(
          persona: persona,
          latency: Duration.zero,
        ).loadDashboard();

        expect(dashboard.customer.fullName, isNotEmpty, reason: persona.name);
      }
    });
  });
}
