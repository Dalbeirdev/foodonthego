import { useState } from 'react';
import { LogOut } from 'lucide-react';
import { Card } from '@fotg/ui';
import { useSession } from './SessionProvider.js';
import { signOut } from '../auth/authApi.js';
import '../home/home.css';

/**
 * Profile, which for now is one working control: sign out.
 *
 * Restart Module 04 owns the details and saved addresses. Sign-out lives here
 * because authentication is this module's and a customer who can sign in and
 * not out has half a session.
 */
export const ProfileScreen = () => {
  const { state, signOut: clearSession } = useSession();
  const [busy, setBusy] = useState(false);

  return (
    <div className="home">
      <header className="home__greeting">
        <h1 className="home__greeting-title">Profile</h1>
      </header>

      <Card>
        <p className="home__card-line">Your details and saved addresses will appear here.</p>
      </Card>

      <Card>
        <h2 className="home__card-title">Sign out</h2>
        <p className="home__card-line">
          You&rsquo;ll need your mobile number and a new code to sign back in.
        </p>
        <button
          className="home__card-cta"
          type="button"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            // Revoke on the server first so the token is dead even if the
            // browser keeps a copy. Then clear locally — and clear it whether
            // or not the revoke succeeded, because the session in front of the
            // customer is the one they asked to end.
            if (state.status === 'authenticated') await signOut(state.session.token);
            clearSession();
          }}
        >
          <LogOut size={16} aria-hidden="true" />
          {busy ? 'Signing out' : 'Sign out'}
        </button>
      </Card>
    </div>
  );
};
