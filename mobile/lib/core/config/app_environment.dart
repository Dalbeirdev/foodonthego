/// Which build this is.
///
/// Set at compile time with `--dart-define=FOTG_ENV=production`. It is a
/// compile-time constant on purpose: `const` means the Dart compiler can prove
/// which branch is dead in a release build and tree-shake it, so development
/// fixtures are not merely unused in production — they are not in the binary.
enum AppEnvironment {
  development,
  staging,
  production;

  static const String _raw = String.fromEnvironment(
    'FOTG_ENV',
    defaultValue: 'development',
  );

  static const AppEnvironment current = _raw == 'production'
      ? AppEnvironment.production
      : _raw == 'staging'
      ? AppEnvironment.staging
      : AppEnvironment.development;

  bool get isProduction => this == AppEnvironment.production;

  /// The single switch that decides whether demo data may exist at all.
  ///
  /// Nothing else in the app is allowed to ask "am I in development?" to decide
  /// what data to show — that question is answered once, here, and the answer is
  /// expressed by which repository gets injected.
  bool get allowsFixtures => this != AppEnvironment.production;

  /// Whether a screen may say "coming in Module 05".
  ///
  /// Development scaffolding must never be shown to a real customer, so in
  /// production a not-yet-built feature is hidden by its feature flag instead.
  bool get showsDevelopmentNotices => this != AppEnvironment.production;

  String get label => switch (this) {
    AppEnvironment.development => 'Development',
    AppEnvironment.staging => 'Staging',
    AppEnvironment.production => 'Production',
  };
}
