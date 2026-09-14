/**
 * Who is signed in, and how the app finds out.
 *
 * The token lives in sessionStorage rather than localStorage: it is cleared
 * when the tab closes, which is the safer default for a browser that may be
 * shared, and it is never put in a cookie readable by script on another path.
 * Restart Module 03 owns how a token is obtained; this owns only how one is
 * kept, offered and discarded.
 */

const STORAGE_KEY = 'fotg.customer.session';

export interface CustomerSession {
  readonly token: string;
}

/**
 * Three states, not two.
 *
 * 'restoring' exists because the difference between "not signed in" and "we
 * have not looked yet" is the whole auth-flash bug: a guard that treats the
 * second as the first sends a returning customer to the sign-in screen for a
 * frame before bouncing them back.
 */
export type SessionState =
  | { readonly status: 'restoring' }
  | { readonly status: 'authenticated'; readonly session: CustomerSession }
  | { readonly status: 'anonymous' };

export const readStoredSession = (): CustomerSession | null => {
  try {
    const raw = window.sessionStorage.getItem(STORAGE_KEY);
    if (raw === null || raw === '') return null;

    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return null;

    const token = (parsed as { token?: unknown }).token;
    return typeof token === 'string' && token !== '' ? { token } : null;
  } catch {
    // Storage can throw outright — private windows, blocked site data. An app
    // that cannot read a token is signed out, which is a safe answer, not a
    // crash on the first line of the first render.
    return null;
  }
};

export const writeStoredSession = (session: CustomerSession): void => {
  try {
    window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  } catch {
    /* Signed in for this page load only. Better than refusing to sign in. */
  }
};

export const clearStoredSession = (): void => {
  try {
    window.sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    /* Nothing useful to do; the in-memory state is cleared by the caller. */
  }
};
