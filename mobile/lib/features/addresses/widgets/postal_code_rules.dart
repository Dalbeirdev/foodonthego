/// Per-country postal-code rules, mirroring `App\Support\Address\PostalCode`.
///
/// Duplicated deliberately rather than fetched: the form needs to pick a
/// keyboard and give feedback before the first keystroke reaches a server. A
/// wrong guess here costs nothing because the server re-validates, and it is
/// only ever allowed to be more permissive than the server, never less.
class PostalCodeRule {
  const PostalCodeRule({
    required this.pattern,
    required this.required,
    required this.isNumeric,
    this.example,
  });

  final RegExp? pattern;
  final bool required;

  /// Whether a numeric keypad is the right keyboard. A UK postcode typed on one
  /// is impossible to enter.
  final bool isNumeric;

  final String? example;

  static const PostalCodeRule _unknown = PostalCodeRule(
    pattern: null,
    required: false,
    isNumeric: false,
  );

  static PostalCodeRule forCountry(String iso) => switch (iso.toUpperCase()) {
    // PIN code: six digits, first not zero.
    'IN' => PostalCodeRule(
      pattern: RegExp(r'^[1-9]\d{5}$'),
      required: true,
      isNumeric: true,
      example: '110016',
    ),
    // The UAE has no postal code system in general use.
    'AE' => _unknown,
    'GB' => PostalCodeRule(
      pattern: RegExp(
        r'^[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}$',
        caseSensitive: false,
      ),
      required: true,
      isNumeric: false,
      example: 'SW1A 1AA',
    ),
    'US' => PostalCodeRule(
      pattern: RegExp(r'^\d{5}(-\d{4})?$'),
      required: true,
      isNumeric: true,
      example: '10001',
    ),
    // A country with no rule here is accepted. Blocking would make an address
    // impossible to save, which is worse than a postcode nobody checked.
    _ => _unknown,
  };

  bool matches(String value) {
    final RegExp? rule = pattern;
    if (rule == null) return value.length <= 16;

    return rule.hasMatch(value.trim());
  }
}
