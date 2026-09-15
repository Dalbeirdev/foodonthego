import '../../core/network/api_client.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/models/customer.dart';
import '../../domain/repositories/auth_repository.dart';

/// The real implementation, talking to `/api/v1` on the Laravel backend.
///
/// It is a thin translation layer on purpose: [ApiClient] already unwraps the
/// envelope and turns a failure into an `ApiException`, so everything here is
/// route names and JSON shapes. Business rules live on the server, where a
/// modified client cannot skip them.
class ApiAuthRepository implements AuthRepository {
  const ApiAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String countryCode,
  }) async {
    final Map<String, dynamic> data = await _client.post(
      '/auth/customer/otp/request',
      body: <String, dynamic>{'phone': phone, 'country_code': countryCode},
    );

    return OtpRequestResult.fromJson(data);
  }

  @override
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String countryCode,
    required String code,
  }) async {
    final Map<String, dynamic> data = await _client.post(
      '/auth/customer/otp/verify',
      body: <String, dynamic>{
        'phone': phone,
        'country_code': countryCode,
        'otp': code,
      },
    );

    if (data['registration_required'] == true) {
      return OtpRegistrationRequired(
        registrationToken: data['registration_token'] as String? ?? '',
        expiresInSeconds:
            (data['registration_token_expires_in_seconds'] as num?)?.toInt() ??
            900,
      );
    }

    return OtpSignedIn(AuthSession.fromJson(data));
  }

  @override
  Future<AuthSession> register({
    required String registrationToken,
    required String firstName,
    String? lastName,
    String? email,
  }) async {
    final Map<String, dynamic> data = await _client.post(
      '/auth/customer/register',
      body: <String, dynamic>{
        'registration_token': registrationToken,
        'first_name': firstName,
        // Sent as null rather than omitted so an empty optional field is
        // unambiguous on the server side.
        'last_name': (lastName?.trim().isEmpty ?? true)
            ? null
            : lastName!.trim(),
        'email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
      },
    );

    return AuthSession.fromJson(data);
  }

  @override
  Future<Customer> currentCustomer() async {
    final Map<String, dynamic> data = await _client.get(
      '/customer/me',
      authenticated: true,
    );

    return Customer.fromJson(data);
  }

  @override
  Future<void> logout() async {
    await _client.post('/auth/logout', authenticated: true);
  }
}
