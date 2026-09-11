/// The countries FoodOnTheGo serves, mirroring `PhoneNormalizer::COUNTRIES` on
/// the backend.
///
/// Duplicated deliberately rather than fetched: the country picker must render
/// instantly on a cold start with no network, and a wrong guess here costs
/// nothing because the server re-validates and its answer wins. When a market is
/// added, both lists change — the contract is recorded in
/// docs/18-customer-authentication.md.
class SupportedCountry {
  const SupportedCountry({
    required this.callingCode,
    required this.iso,
    required this.name,
    required this.nationalDigits,
    required this.mobilePrefixes,
    required this.flag,
  });

  /// Without the `+`, e.g. `91`.
  final String callingCode;
  final String iso;
  final String name;

  /// How many digits the national part has.
  final int nationalDigits;

  /// Leading digits a mobile number can start with. Empty means "no rule" —
  /// the US does not separate mobile numbers by prefix.
  final List<String> mobilePrefixes;

  final String flag;

  String get dialCode => '+$callingCode';

  /// A local check, for a keyboard that can disable the button before a round
  /// trip. It is **not** validation: the server decides, and this is only ever
  /// allowed to be more permissive than helpful, never to let something through
  /// the server would reject silently.
  bool looksPlausible(String digits) {
    if (digits.length != nationalDigits) return false;
    if (mobilePrefixes.isEmpty) return true;
    return mobilePrefixes.contains(digits[0]);
  }

  static const SupportedCountry india = SupportedCountry(
    callingCode: '91',
    iso: 'IN',
    name: 'India',
    nationalDigits: 10,
    mobilePrefixes: <String>['6', '7', '8', '9'],
    flag: '🇮🇳',
  );

  static const List<SupportedCountry> all = <SupportedCountry>[
    india,
    SupportedCountry(
      callingCode: '971',
      iso: 'AE',
      name: 'United Arab Emirates',
      nationalDigits: 9,
      mobilePrefixes: <String>['5'],
      flag: '🇦🇪',
    ),
    SupportedCountry(
      callingCode: '44',
      iso: 'GB',
      name: 'United Kingdom',
      nationalDigits: 10,
      mobilePrefixes: <String>['7'],
      flag: '🇬🇧',
    ),
    SupportedCountry(
      callingCode: '1',
      iso: 'US',
      name: 'United States',
      nationalDigits: 10,
      mobilePrefixes: <String>[],
      flag: '🇺🇸',
    ),
  ];

  /// India is the launch market, so it is the default rather than a guess from
  /// the SIM — reading the SIM's country requires a permission this screen has
  /// no other reason to ask for.
  static const SupportedCountry fallback = india;
}

/// Strips everything that is not a digit, and the national trunk `0`.
///
/// "09876543210" and "9876543210" are the same subscriber. Treating them as
/// different accounts is a real bug, so the trunk prefix goes here as well as on
/// the server.
String normalizeNationalDigits(String input) {
  final String digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('0')
      ? digits.replaceFirst(RegExp(r'^0+'), '')
      : digits;
}

/// Masks an E.164 number the way the server does: calling code visible, all but
/// the last four national digits replaced.
///
/// `+919876543210` becomes `+91 ••••••3210`. The calling code stays because it
/// is not identifying on its own and because it tells a customer with numbers in
/// two countries which one this is.
String maskE164(String e164) {
  if (!e164.startsWith('+')) return e164;

  final String digits = e164.substring(1);

  // Longest calling code first, so '1' never shadows '91' or '971'.
  final List<SupportedCountry> byCodeLength =
      <SupportedCountry>[...SupportedCountry.all]..sort(
        (SupportedCountry a, SupportedCountry b) =>
            b.callingCode.length.compareTo(a.callingCode.length),
      );

  for (final SupportedCountry country in byCodeLength) {
    if (!digits.startsWith(country.callingCode)) continue;

    final String national = digits.substring(country.callingCode.length);
    if (national.length <= 4) {
      return '+${country.callingCode} ${'•' * national.length}';
    }

    final String hidden = '•' * (national.length - 4);
    return '+${country.callingCode} $hidden${national.substring(national.length - 4)}';
  }

  // A number from a country this build does not know. Mask everything but the
  // last four rather than showing it in full.
  if (digits.length <= 4) return e164;
  return '+${'•' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
}
