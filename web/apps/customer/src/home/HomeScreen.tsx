import { Link } from 'react-router-dom';
import { ArrowRight, MapPin, RefreshCw, ReceiptText } from 'lucide-react';
import { Button, Card } from '@fotg/ui';
import { useSession } from '../session/SessionProvider.js';
import { useHome, type HomeOrder, type HomeTrip } from './useHome.js';
import { AppLoading } from '../shell/AppLoading.js';
import './home.css';

/**
 * Morning / afternoon / evening, for the greeting only.
 *
 * Presentation, never a business rule: nothing on this screen changes what the
 * server would decide. Pickup windows, opening hours and order timing are all
 * settled server-side against authoritative time.
 */
const partOfDay = (now: Date): string => {
  const hour = now.getHours();
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
};

/**
 * The greeting line.
 *
 * Falls back to the product name rather than to a placeholder. "Good evening,
 * undefined" and "Customer #123" are both worse than not using a name at all,
 * and both are what happens when a screen assumes the profile has loaded.
 */
const greeting = (firstName: string | null | undefined, now: Date): string =>
  typeof firstName === 'string' && firstName.trim() !== ''
    ? `${partOfDay(now)}, ${firstName.trim()}`
    : 'Welcome to FoodOnTheGo';

const journeyLine = (trip: HomeTrip): string => {
  const from = trip.origin?.display_name?.trim();
  const to = trip.destination?.display_name?.trim();
  // Both halves or neither. "Delhi → " reads as a rendering bug.
  return from && to ? `${from} → ${to}` : 'Journey in progress';
};

const ActiveTripCard = ({ trip }: { trip: HomeTrip }) => (
  <Card>
    <div className="home__card-head">
      <MapPin size={18} aria-hidden="true" />
      <h2 className="home__card-title">Your journey</h2>
    </div>
    <p className="home__card-line">{journeyLine(trip)}</p>
    {/* The CTA goes to the journey, which exists. It deliberately does not say
        "Find food on this route": restaurant listing is Restart Module 07 and
        a dead CTA is worse than no CTA. */}
    <Link className="home__card-cta" to={`/trips/${trip.uuid}`}>
      View journey <ArrowRight size={16} aria-hidden="true" />
    </Link>
  </Card>
);

const ActiveOrderCard = ({ order }: { order: HomeOrder }) => (
  <Card>
    <div className="home__card-head">
      <ReceiptText size={18} aria-hidden="true" />
      <h2 className="home__card-title">Your order</h2>
    </div>
    <p className="home__card-line">{order.restaurant?.name ?? 'Order in progress'}</p>
    <p className="home__card-meta">
      {/* Straight from the server. Nothing here derives or predicts a status,
          and no ETA is shown — the ETA engine does not exist yet. */}
      {order.order_number ? <span>{order.order_number}</span> : null}
      {order.status ? <span className="home__status">{order.status.replaceAll('_', ' ').toLowerCase()}</span> : null}
    </p>
    <Link className="home__card-cta" to={`/orders/${order.uuid}`}>
      Track order <ArrowRight size={16} aria-hidden="true" />
    </Link>
  </Card>
);

export const HomeScreen = () => {
  const { state: sessionState } = useSession();
  const token = sessionState.status === 'authenticated' ? sessionState.session.token : '';
  const { state, reload } = useHome(token);
  const now = new Date();

  if (state.status === 'loading') return <AppLoading />;

  if (state.status === 'failed') {
    return (
      <div className="home">
        <h1 className="home__greeting-title">Welcome to FoodOnTheGo</h1>
        <Card>
          <h2 className="home__card-title">We couldn&rsquo;t load your home screen</h2>
          <p className="home__card-line">Check your connection and try again.</p>
          {/* The request id, because it is the one string support can search
              for and find this exact request in the server log. */}
          {state.error.requestId ? <p className="home__card-meta">Reference: {state.error.requestId}</p> : null}
          <Button onClick={reload}>
            <RefreshCw size={16} aria-hidden="true" /> Try again
          </Button>
        </Card>

        {/* Still offered. A customer whose home data failed can still plan a
            journey, and taking that away turns a bad request into a dead app. */}
        <Card>
          <h2 className="home__card-title">Where are you travelling today?</h2>
          <Link className="home__cta" to="/trips/plan">
            Plan a journey <ArrowRight size={18} aria-hidden="true" />
          </Link>
        </Card>
      </div>
    );
  }

  const { customer, active_trip: trip, active_order: order } = state.data;

  return (
    <div className="home">
      <header className="home__greeting">
        <h1 className="home__greeting-title">{greeting(customer?.first_name, now)}</h1>
        <p className="home__greeting-sub">Order ahead and collect it on your way.</p>
      </header>

      <section className="home__hero" aria-labelledby="journey-cta">
        <h2 className="home__hero-title" id="journey-cta">
          Where are you travelling today?
        </h2>
        <p className="home__hero-sub">
          Tell us your route and we&rsquo;ll find food worth stopping for along it.
        </p>
        <Link className="home__cta" to="/trips/plan">
          Plan a journey <ArrowRight size={18} aria-hidden="true" />
        </Link>
      </section>

      <div className="home__grid">
        {trip ? (
          <ActiveTripCard trip={trip} />
        ) : (
          <Card>
            <h2 className="home__card-title">No active journey</h2>
            <p className="home__card-line">
              Plan a journey to discover food along your route.
            </p>
          </Card>
        )}

        {/* Absent rather than empty. An "Active order: none" card on every home
            screen is a permanent reminder of nothing. */}
        {order ? <ActiveOrderCard order={order} /> : null}
      </div>
    </div>
  );
};
