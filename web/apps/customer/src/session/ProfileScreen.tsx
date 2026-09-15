import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, LogOut, MapPin } from 'lucide-react';
import { Card } from '@fotg/ui';
import { useSession } from './SessionProvider.js';
import { signOut } from '../auth/authApi.js';
import '../home/home.css';

/**
 * Profile: sign out, and saved places.
 *
 * Restart Module 04 owns this screen properly — name, phone, email, the full
 * address surface. It was never run for Customer Web, so what is here is the
 * part Restart Module 05 could not do without: saved places, because the trip
 * planner is required to offer Home, Work and Other and cannot offer what a
 * browser has no way to create. The rest stays a recorded gap.
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
        <div className="home__card-head">
          <MapPin size={18} aria-hidden="true" />
          <h2 className="home__card-title">Saved places</h2>
        </div>
        <p className="home__card-line">
          Home, work and anywhere else you travel from — ready to pick when you plan a journey.
        </p>
        <Link className="home__card-cta" to="/profile/addresses">
          Manage saved places <ArrowRight size={16} aria-hidden="true" />
        </Link>
      </Card>

      <Card>
        <p className="home__card-line">Your name, phone and email will appear here.</p>
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
