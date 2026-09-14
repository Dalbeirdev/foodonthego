/// Which build this is.
///
/// Set at compile time with `--dart-define=FOTG_ENV=production`. It is a
/// compile-time constant on purpose: `const` means the Dart compiler can prove
/// which branch is dead in a release build and tree-shake it, so development
/// fixtures are not merely unused in production — they are not in the binary.
enum AppEnvironment {
  development,

  /// A deployment shown to somebody reviewing the product.
  ///
  /// Real server, real database, real money arithmetic — and stand-in
  /// providers where no credentials exist, which is why it is not staging.
  /// The two flags below pull in opposite directions here ON PURPOSE:
  /// **no fixtures, but every development notice**. A reviewer must not be
  /// shown invented journeys, and must be told when a figure came from a
  /// stand-in.
  ///
  /// It exists because `deploy/web.Dockerfile` has always passed
  /// `FOTG_ENV=review`, and until this enum knew the word it fell through to
  /// `development` — which would have put a debug panel and fixture data on a
  /// public URL. A value that is not recognised looking exactly like a value
  /// that is, is the fault this whole enum exists to prevent.
  review,

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
      : _raw == 'review'
      ? AppEnvironment.review
      : AppEnvironment.development;

  /// Whether [_raw] named an environment this enum knows.
  ///
  /// A `const` cannot throw, so an unrecognised value still resolves to
  /// `development` — it has to resolve to something. What this exposes is the
  /// fact that it did, so a test can fail on it rather than a reviewer
  /// discovering it. `app_environment_values_test.dart` reads every
  /// `FOTG_ENV=` in the repository and asserts each one is recognised.
  static const bool isRecognised =
      _raw == 'production' ||
      _raw == 'staging' ||
      _raw == 'review' ||
      _raw == 'development';

  bool get isProduction => this == AppEnvironment.production;

  /// The single switch that decides whether demo data may exist at all.
  ///
  /// Nothing else in the app is allowed to ask "am I in development?" to decide
  /// what data to show — that question is answered once, here, and the answer is
  /// expressed by which repository gets injected.
  ///
  /// **Review is on the production side of this line.** A reviewer looking at
  /// a public deployment must see what the server actually holds — an invented
  /// journey on the home screen, or a floating debug panel offering to switch
  /// personas and force failures, would make the whole exercise worthless
  /// because nothing on screen could be trusted as real.
  bool get allowsFixtures =>
      this != AppEnvironment.production && this != AppEnvironment.review;

  /// Whether a screen may say "coming in Module 05", or that a figure on it
  /// came from a stand-in rather than a real provider.
  ///
  /// Development scaffolding must never be shown to a real customer, so in
  /// production a not-yet-built feature is hidden by its feature flag instead.
  ///
  /// **Review is on the development side of this line**, which is the opposite
  /// of [allowsFixtures] and deliberate. The review deployment computes routes
  /// as straight lines between two points, and a distance that is arithmetic
  /// rather than roads looks exactly like one that is not. Telling the reviewer
  /// so is the difference between a limitation and a misleading claim.
  bool get showsDevelopmentNotices => this != AppEnvironment.production;

  String get label => switch (this) {
    AppEnvironment.development => 'Development',
    AppEnvironment.review => 'Review',
    AppEnvironment.staging => 'Staging',
    AppEnvironment.production => 'Production',
  };
}
