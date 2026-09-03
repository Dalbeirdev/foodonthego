import '../models/auth_models.dart';
import '../models/customer.dart';

/// Everything the app can do about who is signed in.
///
/// An interface so the screens depend on the flow rather than on `http`, and so
/// a widget test can drive every branch — expired code, rate limit, suspended
/// account — without a server.
abstract interface class AuthRepository {
  /// Asks the server to send a code to [phone].
  ///
  /// [phone] is whatever the customer typed; the server normalizes it and its
  /// answer is authoritative.
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String countryCode,
  });

  /// Submits a code. Either signs in or hands back a registration token.
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String countryCode,
    required String code,
  });

  /// Creates the account for the number bound to [registrationToken].
  ///
  /// There is no `phone` parameter, and that is the security property: the
  /// number comes from the token, so a client cannot verify one number and
  /// register another.
  Future<AuthSession> register({
    required String registrationToken,
    required String firstName,
    String? lastName,
    String? email,
  });

  /// Re-reads the signed-in customer from the server.
  Future<Customer> currentCustomer();

  /// Revokes the current token server-side.
  Future<void> logout();
}
