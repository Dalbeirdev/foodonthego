import '../../core/config/app_environment.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/repositories/home_repository.dart';
import '../fixtures/development_personas.dart';

/// Serves a development persona.
///
/// The constructor asserts the environment allows fixtures, so wiring this into
/// a production build fails loudly in debug and — because the check is on a
/// compile-time constant — cannot be reached at all in release.
class FixtureHomeRepository implements HomeRepository {
  FixtureHomeRepository({
    this.persona = DevelopmentPersona.activeOrder,
    this.latency = const Duration(milliseconds: 450),
    this.failure,
  }) : assert(
         AppEnvironment.current.allowsFixtures,
         'FixtureHomeRepository must never be constructed in a production build.',
       );

  final DevelopmentPersona persona;

  /// A deliberate delay so the skeleton state is exercised in development rather
  /// than flashing past. Tests pass `Duration.zero`.
  final Duration latency;

  /// When set, the repository fails instead of returning data — this is how the
  /// error and offline screens are demonstrated without unplugging anything.
  final HomeFailureKind? failure;

  @override
  Future<HomeDashboard> loadDashboard() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failure != null) throw HomeLoadFailure(failure!);
    return DevelopmentFixtures.dashboardFor(persona);
  }
}
