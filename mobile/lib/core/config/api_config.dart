/// Where the app talks to.
///
/// Set at compile time: `--dart-define=FOTG_API_BASE_URL=https://api.example.com`.
/// A compile-time constant rather than a runtime setting, for the same reason as
/// [AppEnvironment]: a release binary should not contain a switch that points it
/// at a development server, and there is no in-app field an attacker can use to
/// redirect a customer's credentials somewhere else.
class ApiConfig {
  const ApiConfig._();

  /// The default is the Android emulator's alias for the host machine's
  /// localhost, which is the address a developer running `php artisan serve`
  /// actually needs. `localhost` inside an emulator is the emulator itself.
  static const String _rawBaseUrl = String.fromEnvironment(
    'FOTG_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Trailing slashes are stripped so path joining is unambiguous.
  static String get baseUrl {
    String url = _rawBaseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static const String apiVersion = 'v1';

  static Uri uri(String path) {
    final String suffix = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl/api/$apiVersion$suffix');
  }

  /// A request that has not answered in this long is not going to.
  ///
  /// Ten seconds rather than the platform default of a minute or more: a
  /// traveller on a train with one bar needs to be told the network is bad, not
  /// left watching a spinner through a tunnel.
  static const Duration requestTimeout = Duration(seconds: 10);
}
