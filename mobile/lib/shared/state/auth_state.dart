import '../../domain/models/customer.dart';

/// Who is signed in, as far as the app knows.
///
/// A sealed hierarchy so that every screen and the router guard must handle each
/// case explicitly. The one that matters most is [AuthRestoring]: without it the
/// router cannot tell "nobody is signed in" from "we have not looked yet", and a
/// returning customer sees the welcome screen flash before their home appears.
sealed class AuthState {
  const AuthState();

  bool get isAuthenticated => this is AuthAuthenticated;

  Customer? get customer =>
      this is AuthAuthenticated ? (this as AuthAuthenticated).customer : null;
}

/// Reading secure storage on launch. Not a loading spinner — a state the router
/// waits in, so no redirect happens until the answer is known.
class AuthRestoring extends AuthState {
  const AuthRestoring();
}

/// No session, or the customer signed out.
class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.reason});

  /// Why, when it was not the customer's own choice — a revoked or expired
  /// token. Lets the welcome screen explain rather than appearing at random.
  final SignedOutReason? reason;
}

/// Signed in, with the profile the server last gave us.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.customer);

  @override
  final Customer customer;
}

enum SignedOutReason {
  /// The server rejected the token: expired, revoked, or the account was
  /// disabled while the app was closed.
  sessionExpired,

  /// The customer tapped sign out.
  userRequested,
}
