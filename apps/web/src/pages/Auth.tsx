import { useState, type FormEvent } from 'react';
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router-dom';
import { ApiRequestError } from '../api/client.js';
import { useAuth } from '../state/auth.js';
import { Banner } from '../components/ui.js';

const useNextPath = (): string => {
  const [params] = useSearchParams();
  const next = params.get('next');
  // Only same-site paths are honoured. Reflecting an arbitrary `next` into a
  // redirect is how a sign-in page becomes an open redirect for phishing.
  return next && next.startsWith('/') && !next.startsWith('//') ? next : '/';
};

export const Login = () => {
  const { login, user } = useAuth();
  const navigate = useNavigate();
  const next = useNextPath();
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (user) return <Navigate to={next} replace />;

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setIsSubmitting(true);
    setError(null);
    const form = new FormData(event.currentTarget);

    try {
      await login({ email: String(form.get('email')), password: String(form.get('password')) });
      navigate(next, { replace: true });
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not sign you in.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="page container auth-shell">
      <h1>Sign in</h1>
      {error ? <Banner>{error}</Banner> : null}
      <form className="card stack" onSubmit={(event) => void submit(event)}>
        <fieldset>
          <label>
            Email
            <input name="email" type="email" required autoComplete="email" />
          </label>
          <label>
            Password
            <input name="password" type="password" required autoComplete="current-password" />
          </label>
        </fieldset>
        <button type="submit" className="button-primary button-block" disabled={isSubmitting}>
          {isSubmitting ? 'Signing in…' : 'Sign in'}
        </button>
        <p className="faint">
          No account? <Link to={`/register?next=${encodeURIComponent(next)}`}>Create one</Link>
        </p>
      </form>
    </div>
  );
};

export const Register = () => {
  const { register, user } = useAuth();
  const navigate = useNavigate();
  const next = useNextPath();
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (user) return <Navigate to={next} replace />;

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setIsSubmitting(true);
    setError(null);
    const form = new FormData(event.currentTarget);

    try {
      await register({
        email: String(form.get('email')),
        password: String(form.get('password')),
        fullName: String(form.get('fullName')),
        role: String(form.get('role')) as 'customer' | 'restaurant_owner' | 'courier',
      });
      navigate(next, { replace: true });
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not create your account.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="page container auth-shell">
      <h1>Create an account</h1>
      {error ? <Banner>{error}</Banner> : null}
      <form className="card stack" onSubmit={(event) => void submit(event)}>
        <fieldset>
          <label>
            Your name
            <input name="fullName" required maxLength={120} autoComplete="name" />
          </label>
          <label>
            Email
            <input name="email" type="email" required autoComplete="email" />
          </label>
          <label>
            Password
            <input name="password" type="password" required minLength={10} autoComplete="new-password" />
            <span className="faint">At least 10 characters. Length beats punctuation.</span>
          </label>
          <label>
            I want to
            <select name="role" defaultValue="customer">
              <option value="customer">Order food</option>
              <option value="restaurant_owner">Run a restaurant</option>
              <option value="courier">Deliver orders</option>
            </select>
          </label>
        </fieldset>
        <button type="submit" className="button-primary button-block" disabled={isSubmitting}>
          {isSubmitting ? 'Creating your account…' : 'Create account'}
        </button>
        <p className="faint">
          Already have one? <Link to={`/login?next=${encodeURIComponent(next)}`}>Sign in</Link>
        </p>
      </form>
    </div>
  );
};
