import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, MapPin, Plus, RefreshCw } from 'lucide-react';
import { Button, Card } from '@fotg/ui';
import { useSession } from '../session/SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';
import { fetchTrips, type Trip } from './tripsApi.js';
import { isSessionOver, messageFor } from './tripErrors.js';
import './trips.css';

/** The journeys this customer has planned. */

export const endpointLabel = (name: string | null, address: string | null): string =>
  name?.trim() || address?.trim() || 'Somewhere';

/**
 * What the route says today.
 *
 * Read straight off the trip. Nothing here maps NOT_CALCULATED to "0 km" or to
 * an empty distance, which would read as a route that came back empty rather
 * than one that has not been asked for yet.
 */
const routeLine = (trip: Trip): string => {
  if (trip.status === 'CANCELLED') return 'Discarded';
  if (trip.route_status === 'READY') return 'Route ready';
  if (trip.route_status === 'CALCULATING') return 'Working out your route…';
  if (trip.route_status === 'FAILED' || trip.route_status === 'NO_ROUTE') return 'No route yet';
  return 'Route not calculated yet';
};

const TripRow = ({ trip }: { trip: Trip }) => (
  <Card className="trip-row">
    <div className="trip-row__ends">
      <MapPin size={16} aria-hidden="true" />
      <span className="trip-row__text">
        {endpointLabel(trip.origin.display_name, trip.origin.formatted_address)}
        <span aria-hidden="true"> → </span>
        <span className="trip-row__to-sr">to </span>
        {endpointLabel(trip.destination.display_name, trip.destination.formatted_address)}
      </span>
    </div>
    <p className="trip-row__meta">{routeLine(trip)}</p>
    <Link className="trip-row__cta" to={`/trips/${trip.id}`}>
      View journey <ArrowRight size={16} aria-hidden="true" />
    </Link>
  </Card>
);

export const TripsScreen = () => {
  const { state: sessionState, signOut } = useSession();
  const token = sessionState.status === 'authenticated' ? sessionState.session.token : '';
  const [trips, setTrips] = useState<readonly Trip[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reloads, setReloads] = useState(0);

  useEffect(() => {
    if (token === '') return;
    const controller = new AbortController();
    setTrips(null);
    setError(null);

    void (async () => {
      try {
        const response = await fetchTrips({ token, signal: controller.signal });
        /*
         | Checked, not assumed.
         |
         | `response.data` is typed as an array and is one in every case this
         | endpoint produces — but the type is a cast over `unknown`, not a
         | guarantee. When a stubbed run handed this screen an object instead,
         | `.map` threw during render and React unmounted the whole tree: a
         | blank white tab with the failure only in the console. An empty list
         | is a wrong answer; a blank page is a broken app.
         */
        setTrips(Array.isArray(response.data) ? response.data : []);
      } catch (caught) {
        if (caught instanceof Error && caught.name === 'AbortError') return;
        if (isSessionOver(caught)) {
          signOut();
          return;
        }
        setError(messageFor(caught));
      }
    })();

    return () => controller.abort();
  }, [token, reloads, signOut]);

  if (error !== null) {
    return (
      <div className="trips">
        <h1 className="trips__title">Trips</h1>
        <Card>
          <p className="trips__error" role="alert">
            {error}
          </p>
          <Button onClick={() => setReloads((n) => n + 1)} icon={<RefreshCw size={16} />}>
            Try again
          </Button>
        </Card>
      </div>
    );
  }

  if (trips === null) return <AppLoading />;

  return (
    <div className="trips">
      <header className="trips__head">
        <h1 className="trips__title">Trips</h1>
        <Link className="trips__new" to="/trips/plan">
          <Plus size={16} aria-hidden="true" /> Plan a journey
        </Link>
      </header>

      {trips.length === 0 ? (
        <Card>
          <h2 className="trips__empty-title">No journeys yet</h2>
          <p className="trips__empty-line">
            Plan one and we&rsquo;ll find food along your route.
          </p>
          <Link className="trips__new trips__new--block" to="/trips/plan">
            Plan a journey <ArrowRight size={16} aria-hidden="true" />
          </Link>
        </Card>
      ) : (
        <ul className="trips__list">
          {trips.map((trip) => (
            <li key={trip.id}>
              <TripRow trip={trip} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};
