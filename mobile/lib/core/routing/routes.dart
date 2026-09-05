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

  /// Profile and saved addresses (Module 04). Pushed over the Profile branch
  /// rather than sitting in the shell, so the bottom bar stays put and Android
  /// back returns to the list the customer came from.
  static const String profileEdit = 'edit';
  static const String savedAddresses = 'addresses';
  static const String addressForm = 'form';

  /// Absolute forms, for the places that need one.
  static const String profileEditPath = '/profile/edit';
  static const String savedAddressesPath = '/profile/addresses';
  static const String addressFormPath = '/profile/addresses/form';

  /// The trip planner (Module 05). Pushed over the Trips branch for the same
  /// reason: the bottom bar stays put, and Android back returns to the list.
  ///
  /// `plan` is declared before `:tripId` in the router, or "/trips/plan" would
  /// be read as a journey whose id is the word "plan".
  static const String tripPlan = 'plan';
  static const String tripDetail = ':tripId';

  /// The route review screen (Module 06), nested under the journey it belongs
  /// to — a route has no existence away from one.
  static const String tripRoute = 'route';

  /// Restaurants along the selected route (Module 07). Nested under the route
  /// it belongs to, because discovery has no meaning without one — and because
  /// Android back from here lands on the route the customer came from.
  static const String tripRestaurants = 'restaurants';

  static const String tripPlanPath = '/trips/plan';

  static String tripDetailPath(String id) => '/trips/$id';

  static String tripRoutePath(String id) => '/trips/$id/route';

  static String tripRestaurantsPath(String id) =>
      '/trips/$id/route/restaurants';

  /// One of those restaurants (Module 09). Nested under discovery, so Android
  /// back and the iOS swipe both land on the list the customer came from —
  /// with its search, filters and sort still in place.
  static const String restaurantDetail = ':restaurantId';

  static String restaurantDetailPath(String tripId, String restaurantId) =>
      '/trips/$tripId/route/restaurants/$restaurantId';

  /// The controlled destination for anything not built yet. Takes the feature
  /// name and owning module as query parameters so one screen serves them all.
  static const String comingSoon = '/coming-soon';

  static String comingSoonFor({
    required String feature,
    required String module,
  }) =>
      '$comingSoon?feature=${Uri.encodeComponent(feature)}&module=${Uri.encodeComponent(module)}';
}
