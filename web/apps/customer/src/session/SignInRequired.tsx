import { Card } from '@fotg/ui';
import '../home/home.css';

/**
 * What an unauthenticated visitor meets at /login.
 *
 * Restart Module 03 owns phone entry, the one-time code and what happens after
 * it verifies. This owns only the route existing and being honest — so the
 * guard has somewhere real to send people, the URL is not a 404, and nobody
 * has to invent a sign-in form that would later be thrown away.
 *
 * Deliberately no fake form and no fake credentials.
 */
export const SignInRequired = () => (
  <div className="home">
    <header className="home__greeting">
      <h1 className="home__greeting-title">Sign in to FoodOnTheGo</h1>
      <p className="home__greeting-sub">Order ahead and collect it on your way.</p>
    </header>
    <Card>
      <h2 className="home__card-title">Signing in on the web is not available yet</h2>
      <p className="home__card-line">
        Phone sign-in arrives with the next release of the web app. In the meantime the
        FoodOnTheGo mobile app can sign you in.
      </p>
    </Card>
  </div>
);
