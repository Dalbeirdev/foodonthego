/// What collects the food.
///
/// A pickup credential is authentication material, not a reference number.
/// Knowing an order number must never be enough to walk away with somebody's
/// dinner; this is the thing that is, which is why it lives on its own endpoint,
/// is fetched when it is about to be shown, and is not part of the order.
///
/// **Not persisted by the app.** There is deliberately no toJson and no cache
/// write. A code sitting in shared preferences is a code in every backup, every
/// crash report and every device somebody sells. Re-fetching costs one request
/// against a server that derives it on demand.
class PickupCredential {
  const PickupCredential({
    required this.code,
    required this.qrPayload,
    required this.version,
    this.expiresAt,
  });

  /// The short code a customer reads out at the counter.
  final String code;

  /// The opaque payload a QR image encodes. Never displayed as text.
  final String qrPayload;

  /// Bumped when a credential is rotated, invalidating what came before.
  final int version;

  final DateTime? expiresAt;

  static PickupCredential? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;

    final Object? code = value['code'];
    final Object? payload = value['qr_payload'];

    // Both or neither. A half-populated credential would render a screen with a
    // code and no QR, or worse a QR built from an empty string, and either is a
    // customer standing at a counter with something that does not work.
    if (code is! String || code.isEmpty) return null;
    if (payload is! String || payload.isEmpty) return null;

    return PickupCredential(
      code: code,
      qrPayload: payload,
      version: value['credential_version'] is int
          ? value['credential_version'] as int
          : 1,
      expiresAt: DateTime.tryParse(value['expires_at'] as String? ?? ''),
    );
  }

  /// How a screen reader says the code.
  ///
  /// Character by character, because "7K4M9PQ2" read as a word is unusable and
  /// a customer relying on a screen reader has to be able to say this out loud
  /// to somebody behind a counter. The QR is not an accessible alternative to
  /// anything — it cannot be read aloud at all — so this is the accessible
  /// path, not a fallback.
  String get spokenCode => code.split('').join(' ');

  /// Deliberately not the code. If this object is interpolated into a log line
  /// or an error message, the message must not become the credential.
  @override
  String toString() => 'PickupCredential(v$version)';
}
