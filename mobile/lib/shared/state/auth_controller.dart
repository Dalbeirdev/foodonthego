import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../data/auth/session_store.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/models/customer.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';
import 'providers.dart';

/// The app's single source of truth for who is signed in.
///
/// Every screen reads this; none of them keeps its own copy. That is what makes
/// "signed out on one screen" mean signed out everywhere, including the router
/// guard, without any screen having to notify another.
///
/// The controller owns the *session*, not the sign-in flow. Requesting and
/// verifying codes belong to the screens driving them, because a half-finished
/// OTP is not app-wide state — abandoning it should leave nothing behind.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Restoration is kicked off here rather than in main() so that the very
    // first frame already has a state to render and the router has something to
    // wait on.
    Future<void>.microtask(restore);
    return const AuthRestoring();
  }

  SessionStore get _store => ref.read(sessionStoreProvider);

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// Reads persisted credentials and confirms them with the server.
  ///
  /// Both halves matter. Trusting storage alone would show a signed-in shell to
  /// somebody whose token was revoked while the app was closed, and then 401 on
  /// the first real request. Requiring the network would lock a customer out in
  /// a tunnel, so a session that fails to *reach* the server is kept.
  Future<void> restore() async {
    state = const AuthRestoring();

    final AuthSession? stored = await _store.read();

    if (stored == null) {
      state = const AuthSignedOut();
      return;
    }

    if (stored.isExpired) {
      // The server told us when this would stop working, so there is no need to
      // ask it.
      await _store.clear();
      state = const AuthSignedOut(reason: SignedOutReason.sessionExpired);
      return;
    }

    // Optimistic: show the stored profile immediately, then correct it.
    state = AuthAuthenticated(stored.customer);

    try {
      final Customer fresh = await _auth.currentCustomer();
      await _store.write(
        AuthSession(
          accessToken: stored.accessToken,
          expiresAt: stored.expiresAt,
          customer: fresh,
        ),
      );
      state = AuthAuthenticated(fresh);
    } on ApiException catch (error) {
      if (_endsSession(error.code)) {
        await _store.clear();
        state = const AuthSignedOut(reason: SignedOutReason.sessionExpired);
      }
      // Any other failure — no network, a 500, a timeout — leaves the restored
      // session in place. A backend outage must not sign everybody out.
    }
  }

  /// Accepts a session produced by sign-in or registration.
  Future<void> accept(AuthSession session) async {
    await _store.write(session);
    state = AuthAuthenticated(session.customer);
  }

  /// Records a profile the customer just changed.
  ///
  /// The session is the app's single source of truth for who is signed in, so a
  /// name edited on the profile screen has to land here — otherwise the home
  /// greeting keeps the old one until the next cold start. The token is
  /// unchanged; only the profile attached to it moves.
  Future<void> updateProfile(Customer customer) async {
    final AuthSession? stored = await _store.read();

    if (stored != null) {
      await _store.write(
        AuthSession(
          accessToken: stored.accessToken,
          expiresAt: stored.expiresAt,
          customer: customer,
        ),
      );
    }

    if (state is AuthAuthenticated) {
      state = AuthAuthenticated(customer);
    }
  }

  /// Signs out.
  ///
  /// Local state is cleared **first and unconditionally**. If the server call
  /// fails, the customer is still signed out on this device — the alternative
  /// is a sign-out button that does nothing when the network is down, which is
  /// the moment somebody handing their phone over most needs it to work. The
  /// token is revoked server-side on a best-effort basis, and expires anyway.
  Future<void> logout() async {
    final Future<void> revoke = _revokeQuietly();

    await _store.clear();
    state = const AuthSignedOut(reason: SignedOutReason.userRequested);

    await revoke;
  }

  Future<void> _revokeQuietly() async {
    try {
      await _auth.logout();
    } on ApiException {
      // Already invalid, or unreachable. Neither changes the local outcome.
    }
  }

  /// Called when any authenticated request comes back rejected, so one 401
  /// anywhere in the app ends the session everywhere.
  Future<void> handleAuthenticationFailure(ApiErrorCode code) async {
    if (!_endsSession(code)) return;
    if (state is! AuthAuthenticated) return;

    await _store.clear();
    state = const AuthSignedOut(reason: SignedOutReason.sessionExpired);
  }

  /// Codes that mean this credential will never work again.
  ///
  /// Note that FORBIDDEN is not here: being refused one endpoint does not mean
  /// the session is invalid, and signing somebody out over a permission check
  /// would be both wrong and confusing.
  bool _endsSession(ApiErrorCode code) =>
      code == ApiErrorCode.unauthenticated ||
      code == ApiErrorCode.accountSuspended ||
      code == ApiErrorCode.accountDisabled;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
