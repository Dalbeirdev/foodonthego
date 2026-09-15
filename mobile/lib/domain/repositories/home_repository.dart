import '../models/home_dashboard.dart';

/// The boundary the home screen depends on.
///
/// The screen knows this interface and nothing about where the data comes from.
/// Module 02 supplies a fixture implementation in development and an empty one
/// in production; a later module supplies one backed by the Laravel API, and no
/// widget changes.
abstract interface class HomeRepository {
  Future<HomeDashboard> loadDashboard();
}

/// Thrown when a dashboard cannot be loaded.
///
/// A domain-level failure with a `kind`, not a raw exception: the UI branches on
/// the kind to choose its message, and never renders an exception string — a
/// customer should not see a socket error, and a stack trace in a screenshot is
/// an information leak.
class HomeLoadFailure implements Exception {
  const HomeLoadFailure(this.kind);

  final HomeFailureKind kind;
}

enum HomeFailureKind { offline, timeout, serverUnavailable, unknown }
