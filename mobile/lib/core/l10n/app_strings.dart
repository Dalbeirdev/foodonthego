import 'package:flutter/widgets.dart';

/// Every user-visible string in the customer app.
///
/// Widgets read `AppStrings.of(context)` rather than holding literals, so adding
/// a language later is a new subclass and a delegate — not a hunt through every
/// screen. This is a deliberately small hand-rolled implementation instead of
/// `gen-l10n`: with one language it gives the same separation without an ARB
/// pipeline and a code-generation step in CI. The moment a second language is
/// commissioned, this class becomes the interface `gen-l10n` implements.
///
/// Strings that name a module ("Module 05") are development scaffolding and are
/// only ever rendered where `AppEnvironment.showsDevelopmentNotices` allows.
@immutable
class AppStrings {
  const AppStrings();

  static const AppStrings _english = AppStrings();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? _english;

  // --- brand ---------------------------------------------------------------
  String get appName => 'FoodOnTheGo';
  String get tagline => 'Order ahead. Eat on time.';

  // --- greetings -----------------------------------------------------------
  String greetingMorning(String name) => 'Good morning, $name';
  String greetingAfternoon(String name) => 'Good afternoon, $name';
  String greetingEvening(String name) => 'Good evening, $name';
  String get greetingSubtitleIdle => 'Ready for your next journey?';

  // --- journey planner -----------------------------------------------------
  String get plannerTitle => 'Where are you travelling today?';
  String get plannerFromLabel => 'From';
  String get plannerToLabel => 'To';
  String get plannerCurrentLocation => 'Use my current location';
  String get plannerDestinationHint => 'Where are you going?';
  String get plannerCta => 'Plan a journey';

  // --- journey card --------------------------------------------------------
  String get journeySectionTitle => 'Your journey';
  String get journeyViewCta => 'View journey';
  String get journeyRemaining => 'remaining';
  String get journeyNextPickup => 'Next pickup';

  // --- order card ----------------------------------------------------------
  String get orderSectionTitle => 'Your order';
  String get orderViewCta => 'View order';
  String orderReference(String reference) => 'Order $reference';
  String orderItemCount(int count) => count == 1 ? '1 item' : '$count items';
  String get orderPickupIn => 'Pickup in about';
  String get orderPickupNow => 'Ready now';

  // --- how it works --------------------------------------------------------
  String get howItWorksTitle => 'How FoodOnTheGo works';
  String get howItWorksStep1Title => 'Tell us your route';
  String get howItWorksStep1Body =>
      'Origin and destination — Delhi to Jaipur, say.';
  String get howItWorksStep2Title => 'Pick a kitchen on the way';
  String get howItWorksStep2Body =>
      'Restaurants a short detour from your route, with the detour in minutes.';
  String get howItWorksStep3Title => 'Order before you arrive';
  String get howItWorksStep3Body =>
      'The kitchen cooks to your arrival time, not to when you tapped.';
  String get howItWorksStep4Title => 'Collect and go';
  String get howItWorksStep4Body =>
      'Ready as you pull in — not an hour early, not made on arrival.';

  // --- quick actions -------------------------------------------------------
  String get quickActionsTitle => 'Quick actions';
  String get quickActionOrders => 'Orders';
  String get quickActionSavedPlaces => 'Saved places';
  String get quickActionSupport => 'Support';

  // --- navigation ----------------------------------------------------------
  String get navHome => 'Home';
  String get navTrips => 'Trips';
  String get navOrders => 'Orders';
  String get navNotifications => 'Alerts';
  String get navProfile => 'Profile';
  String get navNotificationsFull => 'Notifications';

  // --- empty states --------------------------------------------------------
  String get tripsEmptyTitle => 'No journeys yet';
  String get tripsEmptyBody =>
      'Plan a journey and FoodOnTheGo will find restaurants conveniently placed along your route.';
  String get ordersEmptyTitle => 'No orders yet';
  String get ordersEmptyBody =>
      'Your current and past FoodOnTheGo orders will appear here.';
  String get notificationsEmptyTitle => "You're all caught up";
  String get notificationsEmptyBody =>
      'Order and journey updates will appear here.';

  // --- profile -------------------------------------------------------------
  String get profilePersonalInformation => 'Personal information';
  String get profileSavedAddresses => 'Saved addresses';
  String get profilePaymentMethods => 'Payment methods';
  String get profileOrderHistory => 'Order history';
  String get profileNotifications => 'Notification preferences';
  String get profileHelp => 'Help & support';
  String get profileLegal => 'Terms & conditions';
  String get profilePrivacy => 'Privacy policy';
  String get profileAbout => 'About FoodOnTheGo';
  String get profileSignOut => 'Sign out';
  String get profileAccountSection => 'Account';
  String get profilePreferencesSection => 'Preferences';
  String get profileSupportSection => 'Support & legal';

  // --- connectivity / errors / loading -------------------------------------
  String get offlineTitle => 'You are offline';
  String get offlineBody => 'Showing the latest information we have.';
  String get offlineReconnected => 'Back online';
  String get errorGenericTitle => 'Something went wrong';
  String get errorGenericBody =>
      'We could not load this just now. Please try again.';
  String get errorOfflineTitle => 'No connection';
  String get errorOfflineBody =>
      'Check your signal and try again. Highway coverage can be patchy.';
  String get errorServerTitle => 'FoodOnTheGo is unavailable';
  String get errorServerBody =>
      'The service is not responding. We are looking into it.';
  String get errorTimeoutTitle => 'That took too long';
  String get errorTimeoutBody =>
      'The connection timed out before we heard back.';
  String get retry => 'Try again';
  String get loading => 'Loading';

  // --- authentication ------------------------------------------------------
  String get authWelcomeTitle => 'Eat well on the road';
  String get authWelcomeBody =>
      'Tell us your route, order from a kitchen on the way, and collect it '
      'without waiting.';
  String get authWelcomeCta => 'Continue with mobile number';
  String get authWelcomeLegal =>
      'By continuing you agree to our Terms and Privacy Policy.';
  String get authSessionExpiredNotice =>
      'You were signed out. Please sign in again.';

  String get authPhoneTitle => 'What is your mobile number?';
  String get authPhoneBody =>
      'We will send a one-time code to confirm it is you.';
  String get authPhoneLabel => 'Mobile number';
  String get authPhoneCta => 'Send code';
  String get authCountryPickerTitle => 'Select country';
  String get authPhoneTooShort => 'That number looks too short.';
  String get authPhoneNotMobile =>
      'Enter a mobile number — we need to send a text.';

  String get authOtpTitle => 'Enter the code';
  String authOtpSentTo(String masked) => 'Sent to $masked';
  String get authOtpCta => 'Verify';
  String get authOtpResend => 'Resend code';
  String authOtpResendIn(int seconds) => 'Resend code in ${seconds}s';
  String get authOtpChangeNumber => 'Change number';
  String authOtpExpiresIn(String time) => 'Code expires in $time';
  String get authOtpExpiredNotice => 'That code has expired.';

  String get authRegisterTitle => 'Tell us your name';
  String get authRegisterBody =>
      'So the kitchen knows who is collecting the order.';
  String get authFirstNameLabel => 'First name';
  String get authLastNameLabel => 'Last name (optional)';
  String get authEmailLabel => 'Email (optional)';
  String get authEmailHelper =>
      'For receipts. We will not email you otherwise.';
  String get authRegisterCta => 'Create account';
  String get authFirstNameRequired => 'Please enter your first name.';
  String get authEmailInvalid => 'That email address does not look right.';

  String get authSignOutTitle => 'Sign out?';
  String get authSignOutBody =>
      'You will need your mobile number to sign back in.';
  String get authSignOutConfirm => 'Sign out';
  String get authCancel => 'Cancel';

  // Error messages, keyed by the API's machine-readable code. The app never
  // branches on server prose — see core/network/api_error_code.dart.
  String get authErrorInvalidPhone => 'Enter a valid mobile number.';
  String get authErrorUnsupportedRegion =>
      'FoodOnTheGo is not available in that country yet.';
  String get authErrorOtpSendFailed =>
      "We couldn't send your code. Please try again in a moment.";
  String get authErrorOtpInvalid =>
      "That code isn't correct. Check it and try again.";
  String get authErrorOtpExpired => 'That code has expired. Request a new one.';
  String get authErrorOtpTooManyAttempts =>
      'Too many incorrect attempts. Request a new code.';
  String authErrorOtpResendTooSoon(int seconds) =>
      'Please wait ${seconds}s before requesting another code.';
  String get authErrorOtpRateLimited =>
      'Too many requests. Please wait a little before trying again.';
  String get authErrorRegistrationExpired =>
      'That took a while — please verify your number again.';
  String get authErrorAccountSuspended =>
      'Your account is currently unavailable. Please contact support.';
  String get authErrorAccountDisabled =>
      'This account is no longer active. Please contact support.';
  String get authErrorOffline =>
      'No connection. Check your signal and try again.';
  String get authErrorGeneric => 'Something went wrong. Please try again.';
  String authErrorReference(String requestId) => 'Reference: $requestId';

  // --- profile ------------------------------------------------------------
  String get profileManage => 'Manage profile';
  String get profileEditTitle => 'Personal information';
  String get profileEditSubtitle =>
      'This is the name the kitchen sees when you collect an order.';
  String get profileMobileLabel => 'Mobile number';
  String get profileVerified => 'Verified';
  String get profilePhoneLocked =>
      'Your mobile number is how we recognise you. Contact support to change it.';
  String get profileSave => 'Save changes';
  String get profileSaved => 'Profile updated';
  String get profileNoEmail => 'No email added';
  String get profileEmailUnverified =>
      'Used for receipts only. We do not verify email addresses yet.';

  // --- saved addresses -----------------------------------------------------
  String get addressesTitle => 'Saved addresses';
  String get addressesEmptyTitle => 'No saved addresses yet';
  String get addressesEmptyBody =>
      'Save Home, Work or anywhere else you travel from — it makes planning a '
      'journey a single tap.';
  String get addressesAdd => 'Add address';
  String get addressesAddFirst => 'Add your first address';
  String get addressDefault => 'Default';
  String get addressSetDefault => 'Set as default';
  String get addressDefaultChanged => 'Default address updated';
  String get addressEdit => 'Edit';
  String addressOptionsFor(String label) => 'Options for $label';
  String get addressDelete => 'Remove';
  String addressDeleteTitle(String label) => 'Remove "$label"?';
  String get addressDeleteBody =>
      'This saved address will be removed from your account.';
  String get addressDeleted => 'Address removed';
  String get addressSaved => 'Address saved';
  String get addressUpdated => 'Address updated';
  String addressCountLimit(int limit) =>
      'You can save up to $limit addresses. Remove one to add another.';

  // --- address form --------------------------------------------------------
  String get addressFormAddTitle => 'Add address';
  String get addressFormEditTitle => 'Edit address';
  String get addressTypeLabel => 'What is this place?';
  String get addressTypeHome => 'Home';
  String get addressTypeWork => 'Work';
  String get addressTypeOther => 'Other';
  String get addressLabelField => 'Name this place';
  String get addressLabelHint => 'Parents\' house, Jaipur office…';
  String get addressLine1Field => 'Flat, house or building';
  String get addressLine2Field => 'Street or area (optional)';
  String get addressLandmarkField => 'Landmark (optional)';
  String get addressCityField => 'City';
  String get addressStateField => 'State';
  String get addressPostalField => 'PIN code';
  String get addressPostalFieldGeneric => 'Postal code';
  String get addressCountryField => 'Country';
  String get addressMakeDefault => 'Make this my default address';
  String get addressFormSave => 'Save address';

  String get addressLabelRequired => 'Give this address a name.';
  String get addressLine1Required => 'Enter the flat, building or street.';
  String get addressCityRequired => 'Enter the city.';
  String get addressStateRequired => 'Enter the state.';
  String get addressPostalRequired => 'Enter the PIN code.';
  String addressPostalInvalid(String example) =>
      'That does not look right — a PIN code looks like $example.';

  // Error messages, keyed by the API's machine-readable code.
  String get customerErrorOffline =>
      'No connection. Your changes have not been saved.';
  String get customerErrorSaveOffline =>
      'You need a connection to save this. Nothing has been changed.';
  String get customerErrorAddressGone =>
      'That address is no longer saved to your account.';
  String get customerErrorGeneric => 'Something went wrong. Please try again.';
  String get customerRetry => 'Try again';

  // --- trips: the list (Module 05) -----------------------------------------
  String get tripsTitle => 'Your journeys';
  String get tripsPlan => 'Plan a journey';
  String get tripsPlanFirst => 'Plan your first journey';
  String get tripsScopeOpen => 'Planned';
  String get tripsScopeCancelled => 'Discarded';
  String get tripsCancelledEmptyTitle => 'Nothing discarded';
  String get tripsCancelledEmptyBody =>
      'Journeys you call off will be listed here.';
  String get tripsLoadFailed => "We couldn't load your journeys.";
  String tripOptionsFor(String route) => 'Options for $route';
  String get tripCancelledLabel => 'DISCARDED';

  /// What the app can honestly say about a journey before Module 06 exists.
  ///
  /// Not "0 km", not "about 5 hours", not a progress bar. There is no route
  /// yet — no distance, no travel time, no corridor — and a placeholder number
  /// is read as a real one by everybody who sees it.
  String get tripRouteNotCalculated => 'Route not calculated yet';
  String get tripCreatedAtLabel => 'Planned';

  // --- trips: the planner ---------------------------------------------------
  String get tripPlannerTitle => 'Plan a journey';
  String get tripPlannerFrom => 'Setting off from';
  String get tripPlannerTo => 'Going to';
  String get tripPlannerFromHint => 'Choose your starting point';
  String get tripPlannerToHint => 'Choose your destination';
  String get tripPlannerSwap => 'Swap starting point and destination';
  String get tripPlannerClear => 'Clear';
  String tripPlannerClearFor(String label) => 'Clear $label';
  String get tripPlannerCreate => 'Create journey';
  String get tripPlannerCreating => 'Creating your journey…';
  String get tripCreated => 'Journey created';

  /// Said on the planner, plainly, so nobody waits for a map that is not coming.
  String get tripPlannerRouteLater =>
      'Route and travel time arrive with the next release. This saves where you '
      'are going.';

  // --- trips: choosing a place ---------------------------------------------
  String get placePickerOriginTitle => 'Where are you setting off from?';
  String get placePickerDestinationTitle => 'Where are you going?';
  String get placePickerCurrentLocation => 'Use my current location';

  /// What an unnamed device fix is called once it is one end of a journey.
  ///
  /// Not the row's own label: "Use my current location" is an instruction, and a
  /// journey listed as "Use my current location → Jaipur" reads as a button
  /// somebody pressed rather than a place they set off from.
  String get placeCurrentLocationName => 'Current location';
  String get placePickerCurrentLocationHint => 'We ask your device just once';
  String get placePickerLocating => 'Finding you…';
  String get placePickerSaved => 'Saved addresses';
  String get placePickerSavedEmpty =>
      'You have no saved addresses yet. Search for a place instead.';
  String get placePickerSearchLabel => 'Search for a place';
  String get placePickerSearchHint => 'Airport, station, hotel, area…';
  String get placePickerSearchClear => 'Clear the search';
  String get placePickerTypeMore => 'Keep typing to search.';
  String get placePickerNoResults =>
      'No places matched that. Try a different spelling or a nearby landmark.';
  String get placePickerSearchFailed =>
      "We couldn't search for places just now.";
  String get placePickerResolveFailed =>
      "We couldn't pin down that place. Choose another result.";
  String get placePickerManageAddresses => 'Manage saved addresses';

  /// A saved address that was never located. Offering it anyway would mean
  /// inventing a position for it.
  String get placeSavedNotLocated => 'No location saved';
  String get placeSavedNotLocatedHelp =>
      'This address has no location saved, so it cannot be one end of a '
      'journey. Search for it instead.';

  // --- addresses: locating one ---------------------------------------------
  String get addressLocationHeading => 'Location';
  String get addressNotLocated => 'Not located yet';
  String get addressLocateCta => 'Find this address';
  String get addressChangeLocation => 'Change';
  String get addressLocateHelp =>
      'Locate an address and you can set off from it, or travel to it, without '
      'typing it again.';
  String get addressLocateSheetTitle => 'Find this address';

  // --- trips: location permission ------------------------------------------
  String get locationDeniedTitle => 'Location not shared';
  String get locationDeniedBody =>
      'No problem — search for your starting point instead, or allow location '
      'and try again.';
  String get locationDeniedForeverTitle => 'Location is blocked';
  String get locationDeniedForeverBody =>
      'Location is turned off for FoodOnTheGo in your device settings. You can '
      'turn it back on there, or just search for your starting point.';
  String get locationOpenSettings => 'Open settings';
  String get locationSettingsUnavailable =>
      'We could not open settings. You will find FoodOnTheGo under your '
      "device's app permissions.";
  String get locationServicesOffTitle => 'Location is switched off';
  String get locationServicesOffBody =>
      'Location services are off on this device. Turn them on, or search for '
      'your starting point instead.';
  String get locationTimeoutTitle => 'We could not find you';
  String get locationTimeoutBody =>
      'Your device did not report a location in time. This is common indoors. '
      'Try again, or search for your starting point.';
  String get locationUnavailableTitle => 'Location unavailable';
  String get locationUnavailableBody =>
      'Your device could not provide a location. Search for your starting '
      'point instead.';
  String get locationRetry => 'Try again';
  String get locationSearchInstead => 'Search instead';
  String get locationCoarseWarning =>
      'This location is approximate. Check it is where you are setting off '
      'from.';

  // --- trips: detail and discarding ----------------------------------------
  String get tripDetailTitle => 'Journey';
  String get tripDetailDiscard => 'Discard journey';
  String get tripDiscardTitle => 'Discard this journey?';
  String get tripDiscardBody =>
      'The journey stays in your history, marked as discarded.';
  String get tripDiscardConfirm => 'Discard';
  String get tripDiscardKeep => 'Keep it';
  String get tripDiscarded => 'Journey discarded';
  String get tripReadOnlyCancelled =>
      'This journey is discarded, so it can no longer be changed.';

  // --- trips: validation and failure ---------------------------------------
  String get tripErrorOriginRequired =>
      'Choose where you are setting off from.';
  String get tripErrorDestinationRequired => 'Choose where you are going.';
  String get tripErrorSamePlace =>
      'Choose a destination different from your starting point.';
  String get tripErrorInvalidCoordinates =>
      "That place has no location we can use. Choose another.";
  String get tripErrorSavedAddressNotLocated =>
      'That saved address has no location saved. Search for it instead.';
  String get tripErrorNotEditable =>
      'This journey can no longer be changed. Pull to refresh.';
  String get tripErrorGone => 'That journey is no longer on your account.';
  String get tripErrorCreateFailed =>
      "We couldn't create that journey. Please try again.";
  String tripErrorLimit(int limit) =>
      'You can have up to $limit planned journeys. Discard one to plan another.';

  // --- routes and maps (Module 06) -----------------------------------------
  String get routeTitle => 'Your route';
  String get routeCalculating => 'Finding the best route…';
  String get routeMapLoading => 'Loading the map…';
  String get routeCalculate => 'Calculate route';
  String get routeRecalculate => 'Calculate again';
  String get routeRetry => 'Try again';
  String get routeRecenter => 'Recentre';
  String get routeRecenterHint => 'Fit the route back into view';
  String get routeDistanceLabel => 'Distance';
  String get routeDurationLabel => 'Travel time';
  String get routeTrafficLabel => 'Current traffic';
  String get routeAlternativesTitle => 'Alternative routes';
  String get routeRecommended => 'Recommended';
  String get routeAlternative => 'Alternative';
  String get routeSelected => 'Selected';
  String routeSelectAction(String summary) => 'Choose the route $summary';
  String get routeOriginMarker => 'Starting point';
  String get routeDestinationMarker => 'Destination';

  /// Said next to a traffic figure, because nothing is refreshing it.
  String get routeTrafficNotLive =>
      'Traffic as it was when this route was worked out.';

  /// The one honest thing to say about travel time in this module.
  ///
  /// Module 06 knows how long the *driving* takes. It does not know when
  /// somebody will reach a restaurant, which is a different question involving
  /// where they are now and how long a kitchen takes.
  String get routeTravelTimeOnly =>
      'Driving time from the route. Pickup timing arrives with restaurants.';

  // --- routes: the states that are not a route ------------------------------
  String get routeNotCalculatedTitle => 'No route yet';
  String get routeNotCalculatedBody =>
      'Work out the driving route between your two places.';
  String get routeNoRouteTitle => "We couldn't find a driving route";
  String get routeNoRouteBody =>
      'There is no road route between those two places. Try changing one of '
      'them.';
  String get routeChangeOrigin => 'Change starting point';
  String get routeChangeDestination => 'Change destination';
  String get routeFailedTitle => "We couldn't work out your route";
  String get routeFailedBody =>
      'Something went wrong at our end. Please try again.';
  String get routeTimeoutTitle => 'That took too long';
  String get routeTimeoutBody =>
      'Working out your route timed out. Please try again.';
  String get routeRateLimitedTitle => 'Route planning is busy';
  String get routeRateLimitedBody =>
      'Too many routes are being worked out right now. Please try again in a '
      'moment.';
  String get routeStaleTitle => 'This journey has changed';
  String get routeStaleBody =>
      'Your starting point or destination moved since this route was worked '
      'out. Calculate it again.';
  String get routeOfflineTitle => "You're offline";
  String get routeOfflineBody =>
      'Connect to the internet to work out this route.';
  String get routeOfflineCached =>
      'Offline · showing your last calculated route';

  /// Shown when the map itself cannot draw but the route data is fine.
  String get routeMapUnavailableTitle => 'Map unavailable';
  String get routeMapUnavailableBody =>
      'The map cannot be shown on this device, but your route details are '
      'below.';

  /// Shown over any route that did not come from a real routing provider.
  String get routeDevelopmentProvider =>
      'Development data — this is not a real road route.';

  String get routeContinueCta => 'Find food on this route';

  // --- Module 07: restaurants along the route -------------------------------
  String get discoveryTitle => 'Food on your route';
  String discoverySubtitle(String from, String to) => '$from → $to';

  String get discoveryMapTab => 'Map';
  String get discoveryListTab => 'List';
  String get discoveryToggleHint => 'Switch between map and list';

  String get discoveryLoading => 'Finding food stops along your route…';

  /// Deliberately not "No results". A traveller needs to know whether the
  /// problem is the road, the platform, or the moment.
  String get discoveryEmptyTitle => 'No stops on this route yet';
  String discoveryEmptyBody(String corridor) =>
      "We couldn't find a FoodOnTheGo partner within $corridor of your route. "
      "We're adding more, so it's worth checking again.";
  String get discoveryEmptyChangeRoute => 'Change route';
  String get discoveryEmptyBackToJourney => 'Back to journey';

  /// There *are* restaurants. None of them can take an order.
  String get discoveryClosedOnlyTitle => 'Nothing open right now';
  String get discoveryClosedOnlyBody =>
      'There are stops along your route, but none of them are taking orders at '
      'the moment. They are listed below.';

  String get discoveryErrorTitle => "We couldn't load restaurants";
  String get discoveryErrorBody =>
      "Something went wrong finding stops on your route. Please try again.";
  String get discoveryRateLimitedTitle => 'Just a moment';
  String get discoveryRateLimitedBody =>
      "You've searched a few times in quick succession. Please wait a moment "
      'and try again.';
  String get discoveryRouteNotReadyTitle => 'Work out your route first';
  String get discoveryRouteNotReadyBody =>
      'We need a calculated route before we can find food on it.';
  String get discoveryRouteNotReadyCta => 'Go to route';
  String get discoveryOfflineTitle => "You're offline";
  String get discoveryOfflineBody =>
      'Connect to the internet to find restaurants on this route.';
  String get discoveryOfflineCached =>
      'Offline · showing the stops we last found. Opening times may have '
      'changed.';
  String get discoveryTryAgain => 'Try again';

  /// Shown when the route these were found along did not come from a real
  /// routing provider — the same honesty the route screen applies.
  String get discoveryDevelopmentProvider =>
      'Development data — these stops were found along a stand-in route.';

  // Restaurant card.
  String discoveryDistanceAhead(String distance) => '$distance ahead';
  String discoveryTimeAhead(String duration) => 'About $duration ahead';
  String discoveryDetour(String duration) => '$duration detour';
  String discoveryOffRoute(String distance) => '$distance off your route';
  String get discoveryDetourUnknown => 'Detour unknown';
  String get discoveryBacktrack => 'Behind you';

  String get discoveryAvailabilityOpen => 'Open';
  String get discoveryAvailabilityClosed => 'Closed';
  String get discoveryAvailabilityOpeningSoon => 'Opens soon';
  String get discoveryAvailabilityClosingSoon => 'Closing soon';
  String get discoveryAvailabilityPaused => 'Not accepting orders';
  String get discoveryAvailabilityUnknown => 'Hours unknown';

  String get discoveryViewRestaurant => 'View';

  /// Price level, spelled out. The rupee symbols alone are a visual convention
  /// a screen reader cannot convey.
  String priceLevelLabel(int level) => switch (level) {
    1 => 'Inexpensive',
    2 => 'Moderate',
    3 => 'Expensive',
    _ => 'Very expensive',
  };

  String get discoveryNoRating => 'New';

  String discoveryRestaurantSemantics({
    required String name,
    required String cuisines,
    required String availability,
    required String ahead,
    String? detour,
    String? offRoute,
  }) =>
      '$name, $cuisines, $availability, $ahead'
      '${detour == null ? '' : ', approximately $detour'}'
      '${offRoute == null ? '' : ', $offRoute'}';

  String discoveryResultCount(int count) =>
      count == 1 ? '1 stop on your route' : '$count stops on your route';

  String get discoveryRecentre => 'Fit the whole route back into view';

  // --- home: the current journey -------------------------------------------
  String get homeCurrentJourney => 'Your journey';
  String get homeJourneyViewAll => 'All journeys';

  // --- development scaffolding (never shown in production) -----------------
  String get notBuiltYet => 'Not built yet';
  String comingInModule(String module) => 'Arrives in $module.';
  String get placeholderBody =>
      'This screen is navigation scaffolding. It holds no data and calls no API.';
  String get developmentDataNotice =>
      'Development preview — this is fixture data, not a real journey or order.';
}

/// Registers [AppStrings] with the widget tree.
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  /// English only for now. A new locale is added here and in [load]; nothing in
  /// the widget tree changes.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppStrings> load(Locale locale) async => const AppStrings();

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
