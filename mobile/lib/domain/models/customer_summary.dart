/// The signed-in customer, as the home screen needs them.
///
/// Deliberately not the full account: the home screen needs a name to greet and
/// initials for an avatar, and asking for more than that would couple this screen
/// to a profile shape that Module 03 has not designed yet.
class CustomerSummary {
  const CustomerSummary({required this.fullName, this.avatarUrl});

  final String fullName;
  final String? avatarUrl;

  /// The name to greet with. "Rahul Krishnamurthy Sharma" greeted in full reads
  /// like a letter from a bank, so a greeting uses the first name only.
  String get greetingName {
    final String trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  /// At most two initials, from the first and last name parts.
  ///
  /// A middle name is skipped rather than included: three letters in a 40dp
  /// circle stops being an avatar and starts being a word.
  String get initials {
    final List<String> parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}
