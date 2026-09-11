import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/auth_models.dart';
import '../../domain/models/customer.dart';

/// Where a session lives between app launches.
///
/// An interface because the platform implementation cannot run in a widget test
/// — there is no Keychain in the test binary — and because the requirement here
/// is "the token is not readable by another app", which is a platform promise
/// rather than something this codebase can implement.
abstract interface class SessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

/// The real one: Keychain on iOS, KeyStore-backed encrypted storage on Android.
///
/// What must never happen, and does not here:
///
///  - the token in `SharedPreferences` unencrypted, which is world-readable on
///    a rooted device;
///  - the token in a log line or a crash report;
///  - the token in an analytics event.
///
/// The customer profile is stored alongside it, so a cold start can render a
/// name immediately instead of showing a blank shell while `/customer/me`
/// answers. It is refreshed from the server on every launch regardless.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // AndroidOptions' defaults in v11 are already the strong path:
            // AES-GCM for the value, wrapped by an RSA key held in the Android
            // KeyStore. (The old `encryptedSharedPreferences: true` flag was
            // removed in v11 because that is now the only behaviour.)
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              // Not synced to iCloud and not restored to a different device
              // from a backup: a session is bound to the handset it was issued
              // to, and a restored backup should require signing in again.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const String _tokenKey = 'fotg.auth.access_token';
  static const String _expiryKey = 'fotg.auth.expires_at';
  static const String _customerKey = 'fotg.auth.customer';

  @override
  Future<AuthSession?> read() async {
    final String? token = await _storage.read(key: _tokenKey);
    final String? customerJson = await _storage.read(key: _customerKey);

    if (token == null || token.isEmpty || customerJson == null) return null;

    try {
      final Object? decoded = jsonDecode(customerJson);
      if (decoded is! Map<String, dynamic>) return null;

      return AuthSession(
        accessToken: token,
        expiresAt: DateTime.tryParse(
          await _storage.read(key: _expiryKey) ?? '',
        ),
        customer: Customer.fromJson(decoded),
      );
    } on FormatException {
      // Storage written by an older build with a different shape. Discard it
      // rather than crash on every launch — the customer signs in again once.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    await _storage.write(key: _tokenKey, value: session.accessToken);
    await _storage.write(
      key: _customerKey,
      value: jsonEncode(session.customer.toJson()),
    );

    final DateTime? expiresAt = session.expiresAt;
    if (expiresAt != null) {
      await _storage.write(key: _expiryKey, value: expiresAt.toIso8601String());
    } else {
      await _storage.delete(key: _expiryKey);
    }
  }

  @override
  Future<void> clear() async {
    // Deleted individually rather than with deleteAll(), which would also wipe
    // anything a later module stores under its own keys.
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
    await _storage.delete(key: _customerKey);
  }
}

/// In-memory storage for tests and for the web live-view build.
///
/// It does not persist, which is the honest behaviour: there is no secure store
/// to persist to. Not used by any mobile build.
class InMemorySessionStore implements SessionStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
