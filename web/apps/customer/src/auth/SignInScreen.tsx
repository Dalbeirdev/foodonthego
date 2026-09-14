import { useCallback, useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ArrowRight, Loader2 } from 'lucide-react';
import { useSession } from '../session/SessionProvider.js';
import { messageFor, register, requestOtp, verifyOtp } from './authApi.js';
import './auth.css';

/**
 * The whole sign-in flow, as one state machine.
 *
 * Three screens share one component because they share one piece of state: the
 * phone number. Splitting them across routes would mean either putting the
 * number in the URL — where it lands in history, logs and the Referer header —
 * or holding it in a store that outlives the flow. Neither is worth a prettier
 * address bar.
 *
 * The step is not in the URL for the same reason; `/verify-otp` reached by a
 * back button or a bookmark has no challenge behind it and can only fail.
 */
type Step =
  | { readonly name: 'phone' }
  | { readonly name: 'otp'; readonly phone: string; readonly masked: string; readonly length: number; readonly resendIn: number }
  | { readonly name: 'register'; readonly token: string; readonly masked: string };

const COUNTRY_CODE = '+91';

export const SignInScreen = () => {
  const { signIn } = useSession();
  const navigate = useNavigate();
  const location = useLocation();

  const [step, setStep] = useState<Step>({ name: 'phone' });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Where the guard wanted to go. Only ever a path this app produced — never a
  // value from a query string, which is how open redirects happen.
  const intended = (location.state as { from?: string } | null)?.from;
  const safeReturn = typeof intended === 'string' && intended.startsWith('/') && !intended.startsWith('//')
    ? intended
    : '/';

  const finish = useCallback(
    (token: string) => {
      signIn({ token });
      navigate(safeReturn, { replace: true });
    },
    [signIn, navigate, safeReturn],
  );

  return (
    <main className="auth">
      <div className="auth__panel">
        <div className="auth__brand">
          <span className="auth__mark" aria-hidden="true">F</span>
          <span className="auth__wordmark">FoodOnTheGo</span>
        </div>

        {step.name === 'phone' ? (
          <PhoneStep
            busy={busy}
            error={error}
            onSubmit={async (national) => {
              setBusy(true);
              setError(null);
              try {
                const phone = `${COUNTRY_CODE}${national}`;
                const issued = await requestOtp(phone);
                setStep({
                  name: 'otp',
                  phone,
                  masked: issued.phone_masked,
                  length: issued.otp_length,
                  resendIn: issued.resend_available_in_seconds,
                });
              } catch (caught) {
                setError(messageFor(caught));
              } finally {
                setBusy(false);
              }
            }}
          />
        ) : null}

        {step.name === 'otp' ? (
          <OtpStep
            step={step}
            busy={busy}
            error={error}
            onChangeNumber={() => {
              setError(null);
              setStep({ name: 'phone' });
            }}
            onResend={async () => {
              setBusy(true);
              setError(null);
              try {
                const issued = await requestOtp(step.phone);
                setStep({ ...step, resendIn: issued.resend_available_in_seconds });
              } catch (caught) {
                setError(messageFor(caught));
              } finally {
                setBusy(false);
              }
            }}
            onSubmit={async (code) => {
              setBusy(true);
              setError(null);
              try {
                const result = await verifyOtp(step.phone, code);
                if (result.registration_required) {
                  setStep({ name: 'register', token: result.registration_token, masked: result.phone_masked });
                } else {
                  finish(result.access_token);
                }
              } catch (caught) {
                setError(messageFor(caught));
              } finally {
                setBusy(false);
              }
            }}
          />
        ) : null}

        {step.name === 'register' ? (
          <RegisterStep
            masked={step.masked}
            busy={busy}
            error={error}
            onSubmit={async (firstName, lastName) => {
              setBusy(true);
              setError(null);
              try {
                finish((await register(step.token, firstName, lastName)).access_token);
              } catch (caught) {
                setError(messageFor(caught));
              } finally {
                setBusy(false);
              }
            }}
          />
        ) : null}
      </div>
    </main>
  );
};

const Problem = ({ message }: { message: string | null }) =>
  message === null ? null : (
    // role="alert" so a screen reader announces the failure. Colour and an icon
    // are not enough on their own — an error nobody is told about is not an
    // error message.
    <p className="auth__error" role="alert">
      {message}
    </p>
  );

const PhoneStep = ({
  busy,
  error,
  onSubmit,
}: {
  busy: boolean;
  error: string | null;
  onSubmit: (national: string) => void;
}) => {
  const [national, setNational] = useState('');

  return (
    <form
      className="auth__form"
      onSubmit={(event) => {
        event.preventDefault();
        if (!busy) onSubmit(national.trim());
      }}
      noValidate
    >
      <h1 className="auth__title">What is your mobile number?</h1>
      <p className="auth__sub">We&rsquo;ll send a one-time code to confirm it&rsquo;s you.</p>

      <label className="auth__label" htmlFor="phone">
        Mobile number
      </label>
      <div className="auth__phone">
        <span className="auth__cc" aria-hidden="true">{COUNTRY_CODE}</span>
        <input
          id="phone"
          className="auth__input"
          // tel + numeric so a phone shows the number pad, and autoComplete so
          // the browser offers the number it already knows.
          type="tel"
          inputMode="numeric"
          autoComplete="tel-national"
          autoFocus
          value={national}
          onChange={(e) => setNational(e.target.value.replace(/\D/g, ''))}
          aria-describedby={error ? 'phone-error' : undefined}
          aria-invalid={error !== null}
        />
      </div>
      <span className="sr-only" id="phone-country">Country code {COUNTRY_CODE}</span>

      <div id="phone-error">
        <Problem message={error} />
      </div>

      {/* Disabled while a request is in flight: a second tap would issue a
          second code and burn the customer's resend allowance. */}
      <button className="auth__cta" type="submit" disabled={busy || national.length === 0}>
        {busy ? <Loader2 className="auth__spin" size={18} aria-hidden="true" /> : null}
        {busy ? 'Sending code' : 'Send code'}
        {busy ? null : <ArrowRight size={18} aria-hidden="true" />}
      </button>
    </form>
  );
};

const OtpStep = ({
  step,
  busy,
  error,
  onSubmit,
  onResend,
  onChangeNumber,
}: {
  step: Extract<Step, { name: 'otp' }>;
  busy: boolean;
  error: string | null;
  onSubmit: (code: string) => void;
  onResend: () => void;
  onChangeNumber: () => void;
}) => {
  const [code, setCode] = useState('');
  const [resendIn, setResendIn] = useState(step.resendIn);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => setResendIn(step.resendIn), [step.resendIn]);

  useEffect(() => {
    if (resendIn <= 0) return;
    const id = window.setInterval(() => setResendIn((n) => (n <= 1 ? 0 : n - 1)), 1000);
    return () => window.clearInterval(id);
  }, [resendIn]);

  useEffect(() => inputRef.current?.focus(), []);

  return (
    <form
      className="auth__form"
      onSubmit={(event) => {
        event.preventDefault();
        if (!busy) onSubmit(code.trim());
      }}
      noValidate
    >
      <h1 className="auth__title">Enter the code</h1>
      {/* The masked number comes from the server. The client never renders the
          number it typed back at full length. */}
      <p className="auth__sub">Sent to {step.masked}</p>

      <button className="auth__link" type="button" onClick={onChangeNumber}>
        Change number
      </button>

      <label className="auth__label" htmlFor="otp">
        {step.length}-digit code
      </label>
      <input
        id="otp"
        ref={inputRef}
        className="auth__input auth__input--otp"
        type="text"
        inputMode="numeric"
        // The attribute that makes iOS and Android offer the code from the SMS
        // without the app ever reading messages. No READ_SMS permission.
        autoComplete="one-time-code"
        maxLength={step.length}
        value={code}
        onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
        aria-describedby={error ? 'otp-error' : undefined}
        aria-invalid={error !== null}
      />

      <div id="otp-error">
        <Problem message={error} />
      </div>

      <button className="auth__cta" type="submit" disabled={busy || code.length !== step.length}>
        {busy ? <Loader2 className="auth__spin" size={18} aria-hidden="true" /> : null}
        {busy ? 'Verifying' : 'Verify'}
      </button>

      {/* The countdown is cosmetic. The server refuses an early resend on its
          own clock, so a wrong device clock or a backgrounded tab cannot buy
          an extra code. */}
      <button className="auth__link" type="button" onClick={onResend} disabled={busy || resendIn > 0}>
        {resendIn > 0 ? `Resend code in ${resendIn}s` : 'Resend code'}
      </button>
    </form>
  );
};

const RegisterStep = ({
  masked,
  busy,
  error,
  onSubmit,
}: {
  masked: string;
  busy: boolean;
  error: string | null;
  onSubmit: (firstName: string, lastName: string) => void;
}) => {
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');

  return (
    <form
      className="auth__form"
      onSubmit={(event) => {
        event.preventDefault();
        if (!busy) onSubmit(firstName.trim(), lastName);
      }}
      noValidate
    >
      <h1 className="auth__title">What should we call you?</h1>
      <p className="auth__sub">Your number {masked} is confirmed.</p>

      {/* Shown, not editable, and not submitted. The account is created against
          the number inside the registration token, so there is nothing here for
          a customer to change and nothing for an attacker to substitute. */}

      <label className="auth__label" htmlFor="first-name">First name</label>
      <input
        id="first-name"
        className="auth__input"
        autoComplete="given-name"
        autoFocus
        value={firstName}
        onChange={(e) => setFirstName(e.target.value)}
        aria-invalid={error !== null}
      />

      <label className="auth__label" htmlFor="last-name">Last name <span className="auth__optional">(optional)</span></label>
      <input
        id="last-name"
        className="auth__input"
        autoComplete="family-name"
        value={lastName}
        onChange={(e) => setLastName(e.target.value)}
      />

      <Problem message={error} />

      <button className="auth__cta" type="submit" disabled={busy || firstName.trim() === ''}>
        {busy ? <Loader2 className="auth__spin" size={18} aria-hidden="true" /> : null}
        {busy ? 'Creating your account' : 'Continue'}
      </button>
    </form>
  );
};
