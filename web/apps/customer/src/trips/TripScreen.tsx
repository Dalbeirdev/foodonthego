import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { CheckCircle2, Flag, MapPin, RefreshCw } from 'lucide-react';
import { Button, Card } from '@fotg/ui';
import { useSession } from '../session/SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';
import { fetchTrip, type Trip, type TripEndpoint } from './tripsApi.js';
import { isSessionOver, messageFor } from './tripErrors.js';
import { endpointLabel } from './TripsScreen.js';
import './trips.css';

/**
 * One journey — the handoff Restart Module 06 will take over.
 *
 * It loads the trip from the server by id rather than reading anything the
 * planner handed it. That is the whole point of the handoff being an id: this
 * screen works when it is opened from a bookmark, from a refresh, or from the
 * planner, and all three show the same thing — the row, which is authoritative.
 *
 * A trip belonging to somebody else answers the same 404 as one that does not
 * exist, so the URL is not an oracle for which journeys are real.
 */

const Endpoint = ({
  icon,
  label,
  endpoint,
}: {
  icon: React.ReactNode;
  label: string;
  endpoint: TripEndpoint;
}) => (
  <div className="trip__endpoint">
    <span className="trip__endpoint-icon" aria-hidden="true">
      {icon}
    </span>
    <span className="trip__endpoint-text">
      <span className="trip__endpoint-label">{label}</span>
      <span className="trip__endpoint-primary">
        {endpointLabel(endpoint.display_name, endpoint.formatted_address)}
      </span>
      {endpoint.formatted_address !== null && endpoint.formatted_address !== '' ? (
        <span className="trip__endpoint-secondary">{endpoint.formatted_address}</span>
      ) : null}
    </span>
  </div>
);

export const TripScreen = () => {
  const { tripId = '' } = useParams();
  const { state: sessionState, signOut } = useSession();
  const token = sessionState.status === 'authenticated' ? sessionState.session.token : '';

  const [trip, setTrip] = useState<Trip | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reloads, setReloads] = useState(0);

  useEffect(() => {
    if (token === '' || tripId === '') return;
    const controller = new AbortController();
    setTrip(null);
    setError(null);

    void (async () => {
      try {
        const response = await fetchTrip({ token, signal: controller.signal }, tripId);
        setTrip(response.data);
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
  }, [token, tripId, reloads, signOut]);

  if (error !== null) {
    return (
      <div className="trip">
        <h1 className="trip__title">Journey</h1>
        <Card>
          <p className="trips__error" role="alert">
            {error}
          </p>
          <Button onClick={() => setReloads((n) => n + 1)} icon={<RefreshCw size={16} />}>
            Try again
          </Button>
          <Link className="trip__back" to="/trips">
            Back to your trips
          </Link>
        </Card>
      </div>
    );
  }

  if (trip === null) return <AppLoading />;

  return (
    <div className="trip">
      <header className="trip__head">
        <h1 className="trip__title">Your journey</h1>
        <p className="trip__saved">
          <CheckCircle2 size={16} aria-hidden="true" /> Saved
        </p>
      </header>

      <Card className="trip__card">
        <Endpoint icon={<MapPin size={18} />} label="From" endpoint={trip.origin} />
        <div className="trip__rule" aria-hidden="true" />
        <Endpoint icon={<Flag size={18} />} label="To" endpoint={trip.destination} />
      </Card>

      {/*
        Said plainly, because it is true and because the alternative is a blank
        map that reads as a broken feature. Route calculation, distance, travel
        time and the restaurants along the way are Restart Module 06 and later;
        nothing on this screen estimates any of them.
      */}
      <Card className="trip__pending">
        <h2 className="trip__pending-title">Route not calculated yet</h2>
        <p className="trip__pending-line">
          Your journey is saved. Working out the route, the distance and the food along it is
          the next thing we&rsquo;re building.
        </p>
        <p className="trip__pending-meta">
          Reference: <code>{trip.id}</code>
        </p>
      </Card>

      <Link className="trip__back" to="/trips">
        Back to your trips
      </Link>
    </div>
  );
};
