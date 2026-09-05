import 'package:intl/intl.dart';

/// An amount of money, as minor units and a currency.
///
/// The single money type in the customer app, and the only place a price is
/// turned into something a person reads. Three rules are enforced here so that
/// no screen has to remember them:
///
/// 1. **Never a double.** ₹249.90 stored as a binary float is 249.90000000000001,
///    and a menu of them summed at checkout is off by a rupee for reasons no
///    customer will accept. The wire format is an integer count of paise and
///    the app keeps it that way.
///
/// 2. **The currency travels with the amount.** An integer on its own is not a
///    price; 24900 is ₹249 or $249 depending on something a widget three files
///    away cannot see.
///
/// 3. **The symbol is not hard-coded into logic.** [format] is the only thing
///    in the app that decides what a price looks like, and it asks `intl` using
///    the customer's own locale rather than concatenating a rupee sign.
class Money implements Comparable<Money> {
  const Money({required this.amountMinor, required this.currency});

  /// The amount in the currency's smallest unit — paise for INR.
  final int amountMinor;

  /// ISO 4217, upper case.
  final String currency;

  /// How many minor units make one major unit.
  ///
  /// Not every currency is a hundred: the yen has no minor unit at all, and
  /// treating ¥500 as five yen would be a hundredfold error. Unknown currencies
  /// fall back to two places, which is right far more often than it is wrong.
  static const Map<String, int> _subunits = <String, int>{
    'INR': 100,
    'USD': 100,
    'EUR': 100,
    'GBP': 100,
    'JPY': 1,
  };

  int get subunits => _subunits[currency] ?? 100;

  /// The number of decimal places this currency is written with.
  int get decimalDigits => switch (subunits) {
    1 => 0,
    1000 => 3,
    _ => 2,
  };

  bool get isZero => amountMinor == 0;

  /// True when the amount has no fractional part — ₹249 rather than ₹249.50.
  bool get isWhole => amountMinor % subunits == 0;

  /// Reads `{"amount_minor": 24900, "currency": "INR"}`.
  ///
  /// Returns null rather than guessing. A price that cannot be read is not
  /// rendered as zero and not rendered as "—" next to an "Add" button: the
  /// caller drops the item, because an item whose price is unknown is an item
  /// nobody can be asked to buy.
  static Money? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final Object? raw = json['amount_minor'];
    final Object? currency = json['currency'];

    // Deliberately not `num`: a double here means the server has started
    // sending rupees, and silently rounding it would introduce exactly the
    // error this class exists to prevent.
    final int? amount = switch (raw) {
      final int value => value,
      final String value => int.tryParse(value),
      _ => null,
    };

    if (amount == null || amount < 0) return null;
    if (currency is! String || currency.length != 3) return null;

    return Money(amountMinor: amount, currency: currency.toUpperCase());
  }

  /// The price as a person reads it, in their locale.
  ///
  /// Whole amounts lose their decimals — a menu of "₹249.00" reads like a
  /// spreadsheet — but anything with paise keeps them, because ₹249.50 shown
  /// as ₹249 is a lie about the price.
  String format({String? locale}) {
    final NumberFormat formatter = NumberFormat.simpleCurrency(
      locale: locale ?? Intl.getCurrentLocale(),
      name: currency,
      decimalDigits: isWhole ? 0 : decimalDigits,
    );

    return formatter.format(amountMinor / subunits);
  }

  /// What a screen reader should say.
  ///
  /// "₹249" is announced by some engines as "rupee two four nine". Spelling the
  /// currency out is longer to read and correct to hear.
  String spokenLabel({String? locale}) {
    final String amount = NumberFormat.decimalPattern(
      locale ?? Intl.getCurrentLocale(),
    ).format(isWhole ? amountMinor ~/ subunits : amountMinor / subunits);

    return switch (currency) {
      'INR' => '$amount rupees',
      'USD' => '$amount dollars',
      'EUR' => '$amount euros',
      'GBP' => '$amount pounds',
      'JPY' => '$amount yen',
      _ => '$amount $currency',
    };
  }

  @override
  int compareTo(Money other) {
    // Comparing two currencies by their raw integers would rank ¥500 above
    // ₹400 for reasons that have nothing to do with value. Refused rather than
    // answered wrongly.
    if (other.currency != currency) {
      throw ArgumentError('cannot compare $currency with ${other.currency}');
    }

    return amountMinor.compareTo(other.amountMinor);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => 'Money($amountMinor $currency)';
}
