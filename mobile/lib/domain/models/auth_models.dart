import 'customer.dart';

/// What the server said after we asked it to send a code.
///
/// Note what is absent: the code. The API never returns it and this class has
/// nowhere to put it.
class OtpRequestResult {
  const OtpRequestResult({
    required this.maskedPhone,
    required this.expiresInSeconds,
    required this.resendAvailableInSeconds,
    required this.otpLength,
  });

  factory OtpRequestResult.fromJson(Map<String, dynamic> json) =>
      OtpRequestResult(
        maskedPhone: json['phone_masked'] as String? ?? '',
        expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 300,
        resendAvailableInSeconds:
            (json['resend_available_in_seconds'] as num?)?.toInt() ?? 30,
        otpLength: (json['otp_length'] as num?)?.toInt() ?? 6,
      );

  final String maskedPhone;
  final int expiresInSeconds;
  final int resendAvailableInSeconds;
  final int otpLength;
}

/// The two things a correct code can mean.
///
/// A sealed class rather than a nullable-everything bag: the compiler then makes
/// the caller handle both, and there is no state where a screen has neither a
/// session nor a registration token and has to guess.
sealed class OtpVerifyResult {
  const OtpVerifyResult();
}

/// A returning customer. There is an account, and now there is a session.
class OtpSignedIn extends OtpVerifyResult {
  const OtpSignedIn(this.session);

  final AuthSession session;
}

/// A new number. The account does not exist yet, and this token — not the phone
/// number — is what registration is allowed to act on.
class OtpRegistrationRequired extends OtpVerifyResult {
  const OtpRegistrationRequired({
    required this.registrationToken,
    required this.expiresInSeconds,
  });

  final String registrationToken;
  final int expiresInSeconds;
}

/// An authenticated session: the credential and who it belongs to.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.customer,
    this.expiresAt,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String? ?? '',
    expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    customer: Customer.fromJson(
      (json['user'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    ),
  );

  final String accessToken;
  final DateTime? expiresAt;
  final Customer customer;

  /// Whether the token has already expired according to the server's own stated
  /// expiry. Checked on restore so a cold start does not show a signed-in shell
  /// that 401s on its first request.
  bool get isExpired {
    final DateTime? at = expiresAt;
    return at != null && at.isBefore(DateTime.now());
  }

  /// Never logged, never printed. The default `toString` of a class holding a
  /// bearer token is a leak waiting for a debug print.
  @override
  String toString() => 'AuthSession(customer: ${customer.id})';
}
