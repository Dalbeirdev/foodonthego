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
  String get greetingSubtitleTravelling => 'Here is how your journey is going.';

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
