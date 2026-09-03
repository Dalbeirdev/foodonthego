/// Every route path in the customer app, in one place.
///
/// Declared as constants so a typo is a compile error rather than a silent
/// navigation to nowhere, and so a future deep-link table has something to map
/// onto. Paths are top-level and stable — a later module adds `/trips/:id`
/// beneath an existing branch instead of reorganising the tree.
class Routes {
  const Routes._();

  static const String home = '/';

  /// Authentication. Deliberately top-level rather than nested under the shell:
  /// these screens have no bottom navigation, because a customer who is not
  /// signed in has nowhere else to be.
  static const String welcome = '/welcome';
  static const String authPhone = '/auth/phone';
  static const String authOtp = '/auth/otp';
  static const String authRegister = '/auth/register';

  /// Every route that an unauthenticated visitor may reach.
  static const Set<String> unauthenticated = <String>{
    welcome,
    authPhone,
    authOtp,
    authRegister,
  };

  static const String trips = '/trips';
  static const String orders = '/orders';
  static const String notifications = '/notifications';
  static const String profile = '/profile';

  /// The controlled destination for anything not built yet. Takes the feature
  /// name and owning module as query parameters so one screen serves them all.
  static const String comingSoon = '/coming-soon';

  static String comingSoonFor({
    required String feature,
    required String module,
  }) =>
      '$comingSoon?feature=${Uri.encodeComponent(feature)}&module=${Uri.encodeComponent(module)}';
}
