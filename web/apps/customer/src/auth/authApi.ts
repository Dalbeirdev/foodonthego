import { ApiError, apiRequest } from '@fotg/ui';

/**
 * The three authentication calls, and nothing else.
 *
 * Every shape here is the server's, verified against
 * `CustomerOtpController` rather than guessed. The screens below depend on
 * these types, so a contract change breaks a typecheck instead of a customer.
 */

export interface OtpRequested {
  readonly phone_masked: string;
  readonly expires_in_seconds: number;
  readonly resend_available_in_seconds: number;
  readonly otp_length: number;
}

export interface SignedIn {
  readonly registration_required: false;
  readonly access_token: string;
  readonly token_type: string;
  readonly expires_at: string | null;
  readonly user: { readonly first_name?: string | null };
}

export interface RegistrationRequired {
  readonly registration_required: true;
  readonly registration_token: string;
  readonly registration_token_expires_in_seconds: number;
  readonly phone_masked: string;
}

export type VerifyResult = SignedIn | RegistrationRequired;

export const requestOtp = (phone: string): Promise<OtpRequested> =>
  apiRequest<OtpRequested>('/api/v1/auth/customer/otp/request', {
    method: 'POST',
    body: { phone },
  }).then((r) => r.data);

export const verifyOtp = (phone: string, otp: string): Promise<VerifyResult> =>
  apiRequest<VerifyResult>('/api/v1/auth/customer/otp/verify', {
    method: 'POST',
    body: { phone, otp },
  }).then((r) => r.data);

export const register = (registrationToken: string, firstName: string, lastName: string): Promise<SignedIn> =>
  apiRequest<SignedIn>('/api/v1/auth/customer/register', {
    method: 'POST',
    body: {
      registration_token: registrationToken,
      first_name: firstName,
      // The phone is NOT sent. It comes from the registration token, which the
      // server issued against the verified challenge — so a caller cannot
      // register one number having proved control of another.
      ...(lastName.trim() === '' ? {} : { last_name: lastName.trim() }),
    },
  }).then((r) => r.data);

export const signOut = (token: string): Promise<void> =>
  apiRequest('/api/v1/auth/logout', { method: 'POST', token })
    .then(() => undefined)
    // A logout that fails on the server must still clear the client. Leaving a
    // customer signed in because the revoke call timed out is the wrong way to
    // fail: the local session is the one in front of them.
    .catch(() => undefined);

/**
 * The server's message, when it is safe to show, and a fixed sentence when it
 * is not.
 *
 * The codes below are written for customers — "Incorrect code", "That code has
 * expired" — and the server owns their wording so the same words appear on
 * every platform. Anything else gets a generic line: an unrecognised error may
 * carry a database message, a provider response or a stack frame, and none of
 * those belongs in front of a customer.
 */
const SAFE_CODES = new Set([
  'INVALID_PHONE',
  'UNSUPPORTED_PHONE_REGION',
  'OTP_INVALID',
  'OTP_EXPIRED',
  'OTP_ATTEMPTS_EXCEEDED',
  'OTP_RATE_LIMITED',
  'OTP_RESEND_TOO_SOON',
  'OTP_SEND_FAILED',
  'VALIDATION_FAILED',
  'REGISTRATION_EXPIRED',
  'ACCOUNT_SUSPENDED',
  'ACCOUNT_DISABLED',
]);

export const messageFor = (error: unknown): string => {
  if (!(error instanceof ApiError)) return 'Something went wrong. Please try again.';
  if (error.code === 'NETWORK_ERROR') return "You're offline. Connect to the internet to sign in.";
  return SAFE_CODES.has(error.code) ? error.message : 'Something went wrong. Please try again.';
};
