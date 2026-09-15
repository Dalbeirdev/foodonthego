import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { SignInScreen } from './SignInScreen.js';
import { SessionProvider } from '../session/SessionProvider.js';

/**
 * The web sign-in flow.
 *
 * The backend's own security — hashing, expiry, replay, attempt limits, rate
 * limiting, suspension — is covered by 58 tests in the Laravel suite and is not
 * re-asserted here. What these cover is the part that only exists on the web:
 * that the screens are wired to the real endpoints, that a rejected code is
 * reported in the server's words and not the client's, that a second tap cannot
 * issue a second code, and that the number a customer typed is never echoed
 * back at full length.
 */

const jsonResponse = (body: unknown, status = 200) => ({
  ok: status >= 200 && status < 300,
  status,
  headers: new Headers({ 'X-Request-Id': 'req-1' }),
  text: async () => JSON.stringify(body),
});

const ok = (data: unknown) => jsonResponse({ data, meta: { request_id: 'req-1' } });
const fail = (code: string, message: string, status = 422) =>
  jsonResponse({ error: { code, message, request_id: 'req-1' } }, status);

const otpIssued = {
  phone_masked: '+91 ••••••2736',
  expires_in_seconds: 300,
  resend_available_in_seconds: 30,
  otp_length: 6,
};

const renderFlow = () =>
  render(
    <SessionProvider>
      <MemoryRouter initialEntries={['/login']}>
        <Routes>
          <Route path="/login" element={<SignInScreen />} />
          <Route path="/" element={<div>HOME REACHED</div>} />
          <Route path="/orders" element={<div>ORDERS REACHED</div>} />
        </Routes>
      </MemoryRouter>
    </SessionProvider>,
  );

beforeEach(() => window.sessionStorage.clear());
afterEach(() => vi.unstubAllGlobals());

const enterPhone = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.type(screen.getByLabelText(/Mobile number/i), '9888772736');
  await user.click(screen.getByRole('button', { name: /Send code/i }));
};

describe('requesting a code', () => {
  it('sends the number in E.164 and moves to the code screen', async () => {
    const mock = vi.fn().mockResolvedValue(ok(otpIssued));
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();

    renderFlow();
    await enterPhone(user);

    await waitFor(() => expect(screen.getByText(/Enter the code/i)).toBeInTheDocument());

    const body = JSON.parse(String(mock.mock.calls[0]?.[1]?.body));
    // The country code is joined on the client; the server normalises again and
    // is authoritative. What matters is that a bare national number is never
    // what identifies the account.
    expect(body.phone).toBe('+919888772736');
    expect(String(mock.mock.calls[0]?.[0])).toBe('/api/v1/auth/customer/otp/request');
  });

  it('shows the server-masked number and never the full one', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(ok(otpIssued)));
    const user = userEvent.setup();

    renderFlow();
    await enterPhone(user);

    await waitFor(() => expect(screen.getByText(/\+91 ••••••2736/)).toBeInTheDocument());
    // The masking is the server's. A client that re-derived it could disagree
    // with the SMS the customer is looking at.
    expect(screen.queryByText(/9888772736/)).not.toBeInTheDocument();
  });

  it('cannot issue two codes from two taps', async () => {
    let resolve: (v: unknown) => void = () => {};
    const mock = vi.fn().mockReturnValue(new Promise((r) => { resolve = r; }));
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();

    renderFlow();
    await user.type(screen.getByLabelText(/Mobile number/i), '9888772736');
    const button = screen.getByRole('button', { name: /Send code/i });
    await user.click(button);
    await user.click(button);

    // Each extra code is an SMS somebody pays for and one less resend the
    // customer has left.
    expect(mock).toHaveBeenCalledTimes(1);
    resolve(ok(otpIssued));
  });

  it('reports a rate limit in the server’s words', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      fail('OTP_RATE_LIMITED', 'Too many attempts. Please try again later.', 429),
    ));
    const user = userEvent.setup();

    renderFlow();
    await enterPhone(user);

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/Too many attempts/i));
  });

  it('does not show an unrecognised server error to the customer', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      fail('SERVER_ERROR', 'SQLSTATE[HY000]: near "SELECT": syntax error', 500),
    ));
    const user = userEvent.setup();

    renderFlow();
    await enterPhone(user);

    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument());
    expect(screen.getByRole('alert')).toHaveTextContent('Something went wrong. Please try again.');
    expect(screen.queryByText(/SQLSTATE/)).not.toBeInTheDocument();
  });
});

describe('verifying a code', () => {
  const reachOtpScreen = async (user: ReturnType<typeof userEvent.setup>, mock: ReturnType<typeof vi.fn>) => {
    mock.mockResolvedValueOnce(ok(otpIssued));
    renderFlow();
    await enterPhone(user);
    await waitFor(() => expect(screen.getByText(/Enter the code/i)).toBeInTheDocument());
  };

  it('signs an existing customer in and lands them Home', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();
    await reachOtpScreen(user, mock);

    mock.mockResolvedValueOnce(ok({
      registration_required: false,
      access_token: 'a-real-looking-token',
      token_type: 'Bearer',
      expires_at: null,
      user: { first_name: 'Rahul' },
    }));

    await user.type(screen.getByLabelText(/6-digit code/i), '424242');
    await user.click(screen.getByRole('button', { name: /^Verify$/i }));

    await waitFor(() => expect(screen.getByText('HOME REACHED')).toBeInTheDocument());
    expect(JSON.parse(window.sessionStorage.getItem('fotg.customer.session') ?? '{}').token)
      .toBe('a-real-looking-token');
  });

  it('sends a new number to registration rather than Home', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();
    await reachOtpScreen(user, mock);

    mock.mockResolvedValueOnce(ok({
      registration_required: true,
      registration_token: 'registration-token',
      registration_token_expires_in_seconds: 900,
      phone_masked: '+91 ••••••2736',
    }));

    await user.type(screen.getByLabelText(/6-digit code/i), '424242');
    await user.click(screen.getByRole('button', { name: /^Verify$/i }));

    await waitFor(() => expect(screen.getByText(/What should we call you/i)).toBeInTheDocument());
    // No session yet. A token is issued only once an account exists behind it.
    expect(window.sessionStorage.getItem('fotg.customer.session')).toBeNull();
  });

  it('reports a wrong code without helping the guesser', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();
    await reachOtpScreen(user, mock);

    mock.mockResolvedValueOnce(fail('OTP_INVALID', 'Incorrect code. Please try again.'));

    await user.type(screen.getByLabelText(/6-digit code/i), '000000');
    await user.click(screen.getByRole('button', { name: /^Verify$/i }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('Incorrect code. Please try again.'));
    // No attempts-remaining count, no hint about the real code's shape.
    expect(screen.getByRole('alert').textContent).not.toMatch(/attempt|remaining|\d of \d/i);
    expect(window.sessionStorage.getItem('fotg.customer.session')).toBeNull();
  });

  it('reports an expired code as expired', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();
    await reachOtpScreen(user, mock);

    mock.mockResolvedValueOnce(fail('OTP_EXPIRED', 'That code has expired. Request a new one.'));

    await user.type(screen.getByLabelText(/6-digit code/i), '424242');
    await user.click(screen.getByRole('button', { name: /^Verify$/i }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/expired/i));
  });

  it('lets the customer go back and change the number', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();
    await reachOtpScreen(user, mock);

    await user.click(screen.getByRole('button', { name: /Change number/i }));

    await waitFor(() => expect(screen.getByText(/What is your mobile number/i)).toBeInTheDocument());
  });

  it('holds the resend button shut until the server says otherwise', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();
    await reachOtpScreen(user, mock);

    // The countdown is the server's number, not a constant in the client.
    expect(screen.getByRole('button', { name: /Resend code in \d+s/i })).toBeDisabled();
  });
});

describe('registration', () => {
  it('creates the account and never submits a phone number', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();

    mock.mockResolvedValueOnce(ok(otpIssued));
    renderFlow();
    await enterPhone(user);
    await waitFor(() => expect(screen.getByText(/Enter the code/i)).toBeInTheDocument());

    mock.mockResolvedValueOnce(ok({
      registration_required: true,
      registration_token: 'registration-token',
      registration_token_expires_in_seconds: 900,
      phone_masked: '+91 ••••••2736',
    }));
    await user.type(screen.getByLabelText(/6-digit code/i), '424242');
    await user.click(screen.getByRole('button', { name: /^Verify$/i }));
    await waitFor(() => expect(screen.getByText(/What should we call you/i)).toBeInTheDocument());

    mock.mockResolvedValueOnce(ok({
      registration_required: false,
      access_token: 'new-account-token',
      token_type: 'Bearer',
      expires_at: null,
      user: { first_name: 'Rahul' },
    }));
    await user.type(screen.getByLabelText(/First name/i), 'Rahul');
    await user.click(screen.getByRole('button', { name: /Continue/i }));

    await waitFor(() => expect(screen.getByText('HOME REACHED')).toBeInTheDocument());

    const body = JSON.parse(String(mock.mock.calls[2]?.[1]?.body));
    expect(body.registration_token).toBe('registration-token');
    // The account is created against the number inside the token. A phone in
    // this body would be a number the caller chose rather than proved.
    expect(body).not.toHaveProperty('phone');
    // And nothing that would let a caller pick their own privileges.
    for (const forbidden of ['role', 'status', 'is_admin', 'phone_verified', 'restaurant_id']) {
      expect(body).not.toHaveProperty(forbidden);
    }
  });

  it('will not submit without a first name', async () => {
    const mock = vi.fn();
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();

    mock.mockResolvedValueOnce(ok(otpIssued));
    renderFlow();
    await enterPhone(user);
    await waitFor(() => expect(screen.getByText(/Enter the code/i)).toBeInTheDocument());

    mock.mockResolvedValueOnce(ok({
      registration_required: true,
      registration_token: 't',
      registration_token_expires_in_seconds: 900,
      phone_masked: '+91 ••••••2736',
    }));
    await user.type(screen.getByLabelText(/6-digit code/i), '424242');
    await user.click(screen.getByRole('button', { name: /^Verify$/i }));
    await waitFor(() => expect(screen.getByText(/What should we call you/i)).toBeInTheDocument());

    expect(screen.getByRole('button', { name: /Continue/i })).toBeDisabled();
  });
});

describe('the sign-in screen itself', () => {
  it('asks for a one-time code in the way the OS can autofill', async () => {
    const mock = vi.fn().mockResolvedValue(ok(otpIssued));
    vi.stubGlobal('fetch', mock);
    const user = userEvent.setup();

    renderFlow();
    await enterPhone(user);
    await waitFor(() => expect(screen.getByText(/Enter the code/i)).toBeInTheDocument());

    // autocomplete="one-time-code" is what lets iOS and Android offer the code
    // from the SMS. It is the reason this app needs no SMS-reading permission.
    expect(screen.getByLabelText(/6-digit code/i)).toHaveAttribute('autocomplete', 'one-time-code');
    expect(screen.getByLabelText(/6-digit code/i)).toHaveAttribute('inputmode', 'numeric');
  });

  it('offers a numeric keyboard for the phone and never a password field', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(ok(otpIssued)));
    renderFlow();

    const phone = screen.getByLabelText(/Mobile number/i);
    expect(phone).toHaveAttribute('type', 'tel');
    expect(phone).toHaveAttribute('inputmode', 'numeric');
    // A password manager filling a saved password into an OTP box is a real
    // and confusing failure; there is no password input anywhere in this flow.
    expect(document.querySelector('input[type="password"]')).toBeNull();
  });
});
