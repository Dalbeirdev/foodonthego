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
