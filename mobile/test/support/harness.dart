import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:foodonthego/app.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/core/routing/app_router.dart';
import 'package:foodonthego/core/theme/app_theme.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
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

/// Boots the whole application against a stubbed repository, so navigation tests
/// exercise the real router rather than an approximation of it.
Widget wrapApp({
  required HomeRepository repository,
  ThemeData? theme,
  ConnectivityService? connectivity,
  String initialLocation = '/',
}) {
  return ProviderScope(
    // The list type is inferred: `Override` is not exported from
    // flutter_riverpod, and importing it from a transitive package to write an
    // annotation the compiler can work out itself is not worth the coupling.
    overrides: [
      homeRepositoryProvider.overrideWithValue(repository),
      if (connectivity != null)
        connectivityServiceProvider.overrideWithValue(connectivity),
      routerProvider.overrideWith((Ref ref) {
        final GoRouter router = createRouter(initialLocation: initialLocation);
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
