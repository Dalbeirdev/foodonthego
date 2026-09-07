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

  /// The accessible name of a card's View button.
  ///
  /// A list of twelve buttons all called "View" is a list a screen-reader user
  /// cannot navigate: they have to leave the button, find the card's label,
  /// and come back.
  String discoveryViewNamed(String name) => 'View $name';

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

  // --- Module 08: search, filters, sorting ---------------------------------
  String get discoverySearchHint => 'Search restaurants or cuisines';
  String get discoverySearchLabel => 'Search stops on your route';
  String get discoverySearchClear => 'Clear search';

  String get discoveryFilters => 'Filters';
  String get discoveryFiltersOpen => 'Filter these stops';
  String discoveryFilterCount(int count) =>
      count == 1 ? '1 filter' : '$count filters';
  String get discoveryFiltersApply => 'Show results';
  String discoveryFiltersApplyCount(int count) =>
      count == 1 ? 'Show 1 stop' : 'Show $count stops';
  String get discoveryFiltersClear => 'Clear all';
  String get discoveryFiltersClearOne => 'Remove this filter';
  String get discoveryFiltersNone =>
      'There is nothing to filter on this route yet.';

  String get discoveryFilterCuisine => 'Cuisine';
  String get discoveryFilterFacilities => 'Facilities';
  String get discoveryFilterPrice => 'Price';
  String get discoveryFilterAvailability => 'Availability';
  String get discoveryFilterOpenNow => 'Open now';
  String get discoveryFilterAcceptingOrders => 'Taking orders';
  String get discoveryFilterDetour => 'Detour';

  /// Spelled out under the group, because "any of these" and "all of these" are
  /// different promises and a customer who assumes the wrong one is sent to a
  /// restaurant that does not have what they needed.
  String get discoveryFilterCuisineHint => 'Any of these';
  String get discoveryFilterFacilitiesHint => 'All of these';

  String discoveryFilterOption(String label, int count) => '$label ($count)';

  String get discoveryDetourAny => 'Any detour';
  String discoveryDetourUnder(String duration) => 'Under $duration';

  String get discoverySort => 'Sort';
  String get discoverySortOpen => 'Change the order';
  String discoverySortBy(String label) => 'Sorted by $label';
  String get discoverySortRecommended => 'Recommended';
  String get discoverySortLowestDetour => 'Shortest detour';
  String get discoverySortSoonest => 'Soonest on your route';
  String get discoverySortHighestRated => 'Highest rated';
  String get discoverySortPriceLow => 'Price: low to high';

  /// The customer's filters removed everything. Distinct from
  /// [discoveryEmptyTitle], which means the road itself has nothing on it.
  String get discoveryFilteredEmptyTitle => 'No stops match your filters';
  String discoveryFilteredEmptyBody(int eligible) => eligible == 1
      ? 'There is 1 stop on this route. None of them match what you chose.'
      : 'There are $eligible stops on this route. None of them match what you '
            'chose.';
  String get discoveryFilteredEmptyCta => 'Clear filters';

  String get discoverySearchEmptyTitle => 'Nothing matched your search';
  String discoverySearchEmptyBody(String term) =>
      'We found no stops on this route matching "$term".';
  String get discoverySearchEmptyCta => 'Clear search';

  /// The count line above the list. Says "of" only while something is hiding
  /// results, so an unfiltered screen is not made to look filtered.
  String discoveryResultCountFiltered(int shown, int eligible) =>
      shown == 1 ? '1 of $eligible stops' : '$shown of $eligible stops';

  String get discoveryLoadMore => 'Show more stops';
  String get discoveryRefining => 'Updating your stops…';

  /// Never silently swallowed: a filter this build can build and the server
  /// refuses is our bug, and the customer needs a way out of it.
  String get discoveryFiltersRejectedTitle => "We couldn't apply those filters";
  String get discoveryFiltersRejectedBody =>
      'Something about that combination was not understood. Clearing your '
      'filters will get you back to the full list.';

  // --- Module 09: restaurant details ---------------------------------------
  String get restaurantDetailTitle => 'Restaurant';
  String get restaurantLoading => 'Loading this restaurant…';

  String get restaurantViewMenu => 'View menu';
  String get restaurantMenuUnavailablePaused => 'Not accepting orders';
  String get restaurantMenuUnavailableClosed => 'Closed right now';
  String get restaurantMenuUnavailableGone => 'Unavailable';
  String get restaurantBrowseMenuWhileClosed => 'Browse the menu';

  /// Availability, in the customer's words rather than the server's codes.
  String get restaurantOpenAccepting => 'Open · Accepting orders';
  String get restaurantOpenPaused => 'Open · Not accepting orders right now';
  String get restaurantClosedNow => 'Closed';
  String get restaurantClosedPermanently => 'Unavailable';
  String get restaurantAvailabilityUnknown => 'Opening times unknown';

  String get restaurantPausedBannerTitle => 'Not taking orders right now';
  String get restaurantPausedBannerBody =>
      'The kitchen has paused orders. You can still look at the menu.';
  String get restaurantClosedBannerTitle => 'Closed right now';
  String restaurantOpensAt(String when) => 'Opens $when';
  String get restaurantGoneBannerTitle => 'This restaurant is unavailable';
  String get restaurantGoneBannerBody =>
      'It is no longer taking orders through FoodOnTheGo.';

  // Sections.
  String get restaurantAbout => 'About';
  String get restaurantFacilities => 'Facilities';
  String get restaurantOpeningHours => 'Opening hours';
  String get restaurantHoursToday => 'Today';
  String get restaurantHoursShowAll => 'View all hours';
  String get restaurantHoursHide => 'Hide hours';
  String get restaurantHoursClosedDay => 'Closed';
  String restaurantHoursOvernight(String window) => '$window (overnight)';
  String restaurantHoursTimezone(String zone) => 'Times shown for $zone';
  String get restaurantLocation => 'Location';
  String get restaurantViewOnRoute => 'View on your route';
  String get restaurantCallLabel => 'Call the restaurant';
  String get restaurantOnYourRoute => 'On your route';

  /// Day names, Monday first, matching the server's 0-based day index.
  String weekdayName(int dayOfWeek) => switch (dayOfWeek) {
    0 => 'Monday',
    1 => 'Tuesday',
    2 => 'Wednesday',
    3 => 'Thursday',
    4 => 'Friday',
    5 => 'Saturday',
    _ => 'Sunday',
  };

  // Gallery.
  String restaurantGalleryPosition(int index, int total) => '$index / $total';
  String restaurantGallerySemantics(String name, int index, int total) =>
      'Photograph $index of $total of $name';
  String get restaurantNoImages => 'No photographs yet';

  // Failure states.
  String get restaurantErrorTitle => "We couldn't load this restaurant";
  String get restaurantErrorBody => 'Please try again in a moment.';
  String get restaurantGoneTitle => 'This restaurant is no longer available';
  String get restaurantGoneBody =>
      'It was on your route a moment ago and has since stopped taking orders.';
  String get restaurantOutsideRouteTitle => 'Not on this journey';
  String get restaurantOutsideRouteBody =>
      "This restaurant isn't on the route you've selected, so we can't tell "
      'you how far off it is.';
  String get restaurantBackToList => 'Back to restaurants';
  String get restaurantTryAgain => 'Try again';

  String get restaurantOfflineCached => 'Offline · showing what we last loaded';
  String restaurantOfflineAge(String age) =>
      'Last updated $age ago. Opening times may have changed.';

  // --- menu (Module 10) ----------------------------------------------------
  //
  // Every string here that describes a dish describes what the operator
  // published. There is no wording for a guessed diet, an inferred spice
  // level or an invented allergen, because there is no such data to describe.

  String get menuTitle => 'Menu';
  String menuTitleFor(String restaurant) => '$restaurant · Menu';
  String get menuViewMenu => 'View menu';
  String get menuSearchHint => 'Search this menu';
  String get menuSearchClear => 'Clear search';
  String get menuSearchLabel => 'Search the menu';
  String menuSearchResults(int count) => count == 1 ? '1 item' : '$count items';
  String menuCategoryItemCount(int count) =>
      count == 1 ? '1 item' : '$count items';

  /// The selector chip row. Named for a screen reader, which otherwise
  /// announces a row of bare words with no idea what they select.
  String get menuCategorySelector => 'Menu sections';
  String menuJumpToCategory(String name) => 'Jump to $name';

  // Item metadata. Each of these is shown only when the restaurant published
  // the underlying field.
  String get menuVeg => 'Veg';
  String get menuNonVeg => 'Non-veg';
  String get menuVegan => 'Vegan';
  String get menuEgg => 'Contains egg';
  String menuDietarySemantics(String label) => 'Dietary: $label';

  String get menuSpiceMild => 'Mild';
  String get menuSpiceMedium => 'Medium';
  String get menuSpiceHot => 'Hot';
  String menuSpiceSemantics(String label) => 'Spice level: $label';

  /// Preparation time. Worded so it cannot be read as a pickup time: it is
  /// what the kitchen says the dish takes, and it says nothing about the queue
  /// ahead of the customer or the drive to get there.
  String menuPreparationTime(int minutes) => '$minutes min to cook';
  String menuPreparationSemantics(int minutes) =>
      'Takes about $minutes minutes to cook. This is not a pickup time.';

  String get menuSoldOut => 'Sold out';
  String menuSoldOutSemantics(String item) => '$item is sold out';
  String get menuUnavailableNow => 'Not available right now';

  String get menuNoPhotograph => 'No photograph';

  /// The banner above the list when the kitchen cannot take an order.
  String get menuBrowseOnlyClosed => "Closed now — you can still browse";
  String get menuBrowseOnlyPaused =>
      'Not taking orders right now — you can still browse';
  String get menuBrowseOnlyPermanently => 'Permanently closed';

  // Empty states. Two of them, because they are different problems: a
  // restaurant that has published nothing, and a search that found nothing.
  String get menuEmptyTitle => 'No menu yet';
  String menuEmptyBody(String restaurant) =>
      "$restaurant hasn't published a menu here yet.";
  String get menuSearchEmptyTitle => 'Nothing matched';
  String menuSearchEmptyBody(String term) =>
      'No items on this menu match "$term".';
  String get menuSearchEmptyAction => 'Clear search';
  String get menuSearchTooLong =>
      "That's longer than this menu's search can take. Try a shorter phrase.";

  // Failure states.
  String get menuErrorTitle => "We couldn't load this menu";
  String get menuErrorBody => 'Please try again in a moment.';
  String get menuTryAgain => 'Try again';
  String get menuBackToRestaurant => 'Back to restaurant';
  String get menuOfflineCached => 'Offline · showing what we last loaded';
  String menuOfflineAge(String age) =>
      'Last updated $age ago. Prices and availability may have changed.';

  // The read-only preview sheet.
  String get menuItemPreviewTitle => 'Item details';
  String get menuItemClose => 'Close';
  String get menuItemErrorTitle => "We couldn't load this item";
  String get menuItemGoneTitle => 'No longer on the menu';
  String get menuItemGoneBody =>
      'This item was on the menu a moment ago and has since been taken off.';

  /// Module 10 stops at browsing. The sheet says so rather than showing a
  /// disabled "Add" button, which would promise a cart that does not exist.
  String get menuItemBrowseOnly => 'Ordering opens soon';
  String get menuItemBrowseOnlyBody =>
      "You can browse the full menu. Choosing options and ordering aren't "
      'available yet.';

  // --- item customization and the cart (Module 11) --------------------------
  //
  // Two rules run through all of it. A rule is stated before the customer can
  // break it, not after — "Required · choose 1" above the options rather than
  // an error below them. And nothing here promises the kitchen will do
  // something: a note is a request, and the wording says so.

  String get itemDetailTitle => 'Item';

  // Sizes.
  String get itemChooseSize => 'Choose a size';
  String get itemSizeRequired => 'Required';
  String itemSizeSemantics(String name, String price) => '$name. $price';
  String get itemUnavailableOption => 'Unavailable';

  // Modifier groups. The rule is spelled out under the heading, in words, so a
  // customer never has to discover it by being refused.
  String get itemRequired => 'Required';
  String get itemOptional => 'Optional';
  String itemChooseExactly(int n) => n == 1 ? 'Choose 1' : 'Choose $n';
  String itemChooseUpTo(int n) => n == 1 ? 'Choose 1' : 'Choose up to $n';
  String itemChooseBetween(int min, int max) => 'Choose $min to $max';
  String itemGroupSemantics(String name, String rule) => '$name. $rule';
  String itemOptionSemantics(String name, String price, bool selected) =>
      '$name. $price. ${selected ? 'Selected' : 'Not selected'}';
  String get itemNoExtraCharge => 'No extra charge';
  String itemAddsPrice(String price) => 'Adds $price';
  String itemGroupFull(int max) =>
      max == 1 ? 'You can choose 1.' : 'You can choose up to $max.';
  String itemChooseToContinue(int min) => min == 1
      ? 'Choose 1 option to continue.'
      : 'Choose $min options to continue.';

  // Quantity.
  String get itemQuantity => 'Quantity';
  String itemQuantitySemantics(int n) => 'Quantity, $n';
  String get itemQuantityIncrease => 'Add one more';
  String get itemQuantityDecrease => 'Remove one';
  String itemQuantityMax(int max) => 'Up to $max at a time.';

  // Special instructions. Deliberately not a promise.
  String get itemNoteLabel => 'Special instructions';
  String get itemNoteHint => 'Add a note for the restaurant';
  String get itemNoteOptional => 'Optional';
  String get itemNoteCaveat =>
      "The kitchen will see this and will do what they can.";
  String itemNoteRemaining(int n) => '$n characters left';

  // The sticky bar.
  String itemAddToCart(String total) => 'Add to cart · $total';
  String get itemAddChooseOptions => 'Choose required options';
  String get itemAdding => 'Adding…';
  String get itemSoldOut => 'Sold out';
  String get itemRestaurantPaused => 'Not taking orders right now';
  String get itemRestaurantClosed => 'Closed right now';

  // What happened.
  String get itemAddedToCart => 'Added to cart';
  String itemAddedToCartCount(int items) =>
      items == 1 ? '1 item in your cart' : '$items items in your cart';
  String get itemViewCart => 'View cart';

  // Failures, each with the move that fixes it.
  String get itemAddFailedTitle => "We couldn't add this";
  String get itemAddFailedBody => 'Please try again in a moment.';
  String get itemAddRetry => 'Try again';
  String get itemOfflineTitle => "You're offline";
  String get itemOfflineBody =>
      'Connect to the internet to add this to your cart. Your choices are kept.';
  String get itemSoldOutTitle => 'Just sold out';
  String get itemSoldOutBody =>
      'The kitchen has run out while you were choosing. Review your selection.';
  String get itemNotAcceptingTitle => 'Not taking orders';
  String get itemNotAcceptingBody =>
      "This restaurant isn't accepting orders right now. You can still browse.";

  String get itemCartConflictTitle => 'Your cart has other items';
  String itemCartConflictBody(String restaurant) =>
      'Your cart has items from $restaurant. Finish or empty that order before '
      'starting a new one.';

  /// The price-change refusal. The old and the new figure are both shown,
  /// because "the price changed" without saying to what is not information.
  String get itemPriceChangedTitle => 'The price changed';
  String itemPriceChangedBody(String from, String to) =>
      'This item was $from and is now $to. Review the new price before adding.';
  String itemPriceChangedAccept(String price) => 'Add at $price';
  String get itemPriceChangedCancel => 'Not now';

  String get itemLoadFailedTitle => "We couldn't load this item";
  String get itemGoneTitle => 'No longer on the menu';

  // --- home: the current journey -------------------------------------------
  String get homeCurrentJourney => 'Your journey';
  String get homeJourneyViewAll => 'All journeys';

  // --- the cart (Module 12) -------------------------------------------------
  String get cartTitle => 'Your cart';
  String get cartOpen => 'Cart';
  String cartFrom(String restaurant) => 'From $restaurant';
  String cartItemCount(int items) => items == 1 ? '1 item' : '$items items';

  // Empty, and not treated as a failure: a customer who has added nothing has
  // a cart with nothing in it.
  String get cartEmptyTitle => 'Nothing in your cart yet';
  String get cartEmptyBody =>
      'Find a place to stop along your route and add something you fancy.';
  String get cartEmptyAction => 'Find somewhere to eat';

  // Lines.
  String get cartQuantityLabel => 'Quantity';
  String cartDecreaseFor(String item) => 'One fewer $item';
  String cartIncreaseFor(String item) => 'One more $item';
  String cartRemoveFor(String item) => 'Remove $item';
  String get cartRemove => 'Remove';
  String cartNote(String note) => 'Note: $note';
  String get cartEachPrice => 'each';

  // The order summary. Named exactly, because "charges" tells a customer
  // nothing about what they are paying for.
  String get cartSummaryTitle => 'Order summary';
  String get cartSubtotal => 'Subtotal';
  String get cartTax => 'Taxes';
  String get cartPackagingFee => 'Packaging';
  String get cartPlatformFee => 'Service fee';
  String get cartTotal => 'Total';
  String get cartTotalsNote =>
      'Worked out by FoodOnTheGo. You pay this at the counter.';

  // Emptying, which is destructive and therefore confirmed.
  String get cartEmptyCart => 'Empty cart';
  String get cartEmptyConfirmTitle => 'Empty your cart?';
  String get cartEmptyConfirmBody =>
      'Everything in it will be removed. This cannot be undone.';
  String get cartEmptyConfirmAction => 'Empty cart';
  String get cartKeep => 'Keep it';

  // What revalidation found. Two kinds, because the customer's move differs:
  // a price they look at and accept, a missing dish they have to deal with.
  String get cartPricesChangedTitle => 'Prices have changed';
  String get cartPricesChangedBody =>
      'Check the updated figures before you order.';
  String get cartNeedsAttentionTitle => 'Some items need your attention';
  String get cartNeedsAttentionBody =>
      "You'll need to remove or change these before ordering.";
  String get cartKitchenClosedTitle => 'This kitchen has stopped taking orders';
  String get cartKitchenClosedBody =>
      'Your cart is safe. Try again later, or pick somewhere else on your route.';
  String get cartPriceWas => 'Was';
  String get cartPriceNow => 'Now';
  String get cartUnavailableHere => 'No longer available';
  String get cartRecheck => 'Check again';

  // Failures, each with the move that fixes it.
  String get cartLoadFailedTitle => "We couldn't load your cart";
  String get cartLoadFailedBody => 'Please try again in a moment.';
  String get cartOfflineTitle => "You're offline";
  String get cartOfflineBody =>
      'These figures were last checked when you had a connection.';
  String get cartRetry => 'Try again';
  String get cartEditFailed => "That didn't take. Please try again.";
  String get cartEditOffline => "You're offline — that change wasn't saved.";
  String get cartLineGone => 'That item is no longer in your cart.';
  String get cartQuantityRefused => "You can't have that many of one item.";
  String get cartPriceChangedNow =>
      'The price has changed. Have a look before you continue.';
  String get cartTripGoneTitle => 'That journey is gone';
  String get cartTripGoneBody =>
      'Plan a journey to start a cart along your route.';

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
