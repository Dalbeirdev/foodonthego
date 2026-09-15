import { useMemo } from 'react';
import { Link, useParams } from 'react-router-dom';
import { AlertTriangle, ArrowRight, Check, Flag, Loader2, MapPin, RefreshCw } from 'lucide-react';
import { Button, Card } from '@fotg/ui';
import { useSession } from '../session/SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';
import { endpointLabel } from '../trips/TripsScreen.js';
import { toNumber, type TripEndpoint } from '../trips/tripsApi.js';
import { useRoute } from './useRoute.js';
import { isSyntheticProvider, type TripRoute } from './routeApi.js';
import { RouteMap, type MapRoute } from './RouteMap.js';
import {
  formatCalculatedAt,
  formatDistance,
  formatDuration,
  formatTrafficLine,
  optionLabel,
} from './format.js';
import type { Bounds } from './polyline.js';
import './route.css';

/**
 * Your route: the map, the numbers, the alternatives, and the way onwards.
 *
 * Three rules decide almost everything on this screen:
 *
 *  - **The map is never the only representation.** Every fact it shows is also
 *    in text, because a map is unusable to a screen reader and unavailable to
 *    anybody whose tiles will not load — which, in this build, is everybody.
 *  - **Nothing is claimed that the provider did not supply.** No traffic line
 *    without a traffic figure, no "Fastest" without a comparison that supports
 *    it, no alternatives that were not returned.
 *  - **The client is authoritative for nothing.** Distance, duration, traffic,
 *    geometry and which route is selected all come from the server's answer.
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
  <div className="route__endpoint">
    <span className="route__endpoint-icon" aria-hidden="true">
      {icon}
    </span>
    <span className="route__endpoint-text">
      <span className="route__endpoint-label">{label}</span>
      <span className="route__endpoint-primary">
        {endpointLabel(endpoint.display_name, endpoint.formatted_address)}
      </span>
    </span>
  </div>
);

const RouteOption = ({
  route,
  label,
  isBusy,
  onSelect,
}: {
  route: TripRoute;
  label: string;
  isBusy: boolean;
  onSelect: () => void;
}) => {
  const traffic = formatTrafficLine(route.duration_seconds, route.traffic_duration_seconds);

  return (
    <li>
      <button
        type="button"
        className={`route-option ${route.is_selected ? 'route-option--selected' : ''}`}
        onClick={onSelect}
        disabled={isBusy || route.is_selected}
        aria-pressed={route.is_selected}
        /* The whole card in one accessible name, so choosing between routes
           does not require reading four separate nodes in sequence. */
        aria-label={`${label}. ${formatDistance(route.distance_meters)}, about ${formatDuration(
          route.traffic_duration_seconds ?? route.duration_seconds,
        )}.${route.is_selected ? ' Currently selected.' : ' Choose this route.'}`}
      >
        <span className="route-option__head">
          <span className="route-option__label">{label}</span>
          {route.is_selected ? (
            <span className="route-option__selected">
              <Check size={15} aria-hidden="true" /> Selected
            </span>
          ) : null}
          {isBusy ? <Loader2 size={15} className="route__spin" aria-hidden="true" /> : null}
        </span>

        <span className="route-option__figures">
          <span className="route-option__duration">
            {formatDuration(route.traffic_duration_seconds ?? route.duration_seconds)}
          </span>
          <span className="route-option__distance">{formatDistance(route.distance_meters)}</span>
        </span>

        {/* Only ever rendered when the provider actually returned a traffic
            figure. `formatTrafficLine` returns null otherwise. */}
        {traffic !== null ? <span className="route-option__traffic">{traffic}</span> : null}
      </button>
    </li>
  );
};

export const RouteScreen = () => {
  const { tripId = '' } = useParams();
  const { state: sessionState, signOut } = useSession();
  const token = sessionState.status === 'authenticated' ? sessionState.session.token : '';

  const { state, refresh, select, selecting } = useRoute(token, tripId, signOut);
  const now = new Date();

  const payload = 'data' in state ? state.data : null;
  const trip = payload?.trip ?? null;
  const routes = payload?.routes ?? [];
  const selected = routes.find((route) => route.is_selected) ?? null;

  const mapRoutes = useMemo<MapRoute[]>(
    () =>
      routes.map((route) => ({
        id: route.route_id,
        encodedPolyline: route.encoded_polyline,
        isSelected: route.is_selected,
      })),
    [routes],
  );

  const bounds = useMemo<Bounds | null>(() => {
    const source = selected ?? routes[0];
    if (source === undefined) return null;

    const north = toNumber(source.bounds.north);
    const south = toNumber(source.bounds.south);
    const east = toNumber(source.bounds.east);
    const west = toNumber(source.bounds.west);

    return north !== null && south !== null && east !== null && west !== null
      ? { north, south, east, west }
      : null;
  }, [selected, routes]);

  if (state.status === 'loading') return <AppLoading />;

  const originLabel = trip ? endpointLabel(trip.origin.display_name, trip.origin.formatted_address) : '';
  const destinationLabel = trip
    ? endpointLabel(trip.destination.display_name, trip.destination.formatted_address)
    : '';

  const header = (
    <header className="route__head">
      <h1 className="route__title">Your route</h1>
      <Link className="route__back" to="/trips">
        All trips
      </Link>
    </header>
  );

  const endpoints =
    trip !== null ? (
      <Card className="route__endpoints">
        <Endpoint icon={<MapPin size={18} />} label="From" endpoint={trip.origin} />
        <div className="route__rule" aria-hidden="true" />
        <Endpoint icon={<Flag size={18} />} label="To" endpoint={trip.destination} />
      </Card>
    ) : null;

  if (state.status === 'calculating') {
    return (
      <div className="route">
        {header}
        {endpoints}
        <Card className="route__status">
          <p className="route__status-line" role="status">
            <Loader2 size={18} className="route__spin" aria-hidden="true" /> Working out your
            route…
          </p>
          <p className="route__status-sub">This takes a few seconds.</p>
        </Card>
      </div>
    );
  }

  if (state.status === 'noRoute') {
    return (
      <div className="route">
        {header}
        {endpoints}
        <Card className="route__status">
          <h2 className="route__status-title">No driving route found</h2>
          <p className="route__status-sub">
            We could not find a road route between these two places. Try a different starting point
            or destination.
          </p>
          <Link className="route__cta-secondary" to="/trips/plan">
            Change journey <ArrowRight size={16} aria-hidden="true" />
          </Link>
        </Card>
      </div>
    );
  }

  if (state.status === 'failed') {
    return (
      <div className="route">
        {header}
        {endpoints}
        <Card className="route__status">
          <h2 className="route__status-title">We could not work out your route</h2>
          <p className="route__status-sub" role="alert">
            {state.message}
          </p>
          <div className="route__status-actions">
            <Button onClick={refresh} icon={<RefreshCw size={16} />}>
              Try again
            </Button>
            <Link className="route__cta-secondary" to="/trips/plan">
              Change journey
            </Link>
          </div>
        </Card>
      </div>
    );
  }

  const synthetic = selected !== null && isSyntheticProvider(selected.provider);
  const calculatedAt = formatCalculatedAt(selected?.calculated_at, now);
  const trafficLine = formatTrafficLine(
    selected?.duration_seconds,
    selected?.traffic_duration_seconds,
  );

  return (
    <div className="route">
      {header}
      {endpoints}

      {/*
        Shown for any route whose provider is not a real one. The backend stores
        the provider name on every row precisely so a synthetic figure stays
        identifiable — and a screen that rendered "236 km, 3 hr 56 min" with no
        such notice would be presenting a straight line as a route.
      */}
      {synthetic ? (
        <p className="route__synthetic" role="note">
          <AlertTriangle size={16} aria-hidden="true" />
          <span>
            <strong>These figures are not a real route.</strong> No routing provider is configured,
            so the distance and time below come from a straight-line stand-in, not from the roads.
          </span>
        </p>
      ) : null}

      <RouteMap
        routes={mapRoutes}
        bounds={bounds}
        originLabel={originLabel}
        destinationLabel={destinationLabel}
      />

      {/*
        The same facts the map shows, in text. Not a fallback — it is always
        here, because the map is not readable by a screen reader and this is
        what makes the screen usable without one.
      */}
      <Card className="route__summary">
        <h2 className="route__summary-title">
          {originLabel} <span aria-hidden="true">→</span>
          <span className="route__sr-only"> to </span> {destinationLabel}
        </h2>

        <dl className="route__figures">
          <div>
            <dt>Distance</dt>
            <dd>{formatDistance(selected?.distance_meters)}</dd>
          </div>
          <div>
            <dt>Estimated travel time</dt>
            <dd>{formatDuration(selected?.duration_seconds)}</dd>
          </div>
        </dl>

        {trafficLine !== null ? (
          <p className="route__traffic">{trafficLine}</p>
        ) : (
          /* Said out loud rather than left blank, so nobody reads the travel
             time above as traffic-aware when it is not. */
          <p className="route__no-traffic">Traffic information is not available for this route.</p>
        )}

        {calculatedAt !== null ? <p className="route__calculated">{calculatedAt}</p> : null}

        <Button
          variant="ghost"
          size="sm"
          onClick={refresh}
          icon={<RefreshCw size={15} />}
          className="route__refresh"
        >
          Work it out again
        </Button>
      </Card>

      {routes.length > 1 ? (
        <section className="route__options" aria-labelledby="route-options-title">
          <h2 className="route__options-title" id="route-options-title">
            Choose your route
          </h2>
          <ul className="route__options-list">
            {routes.map((route, index) => (
              <RouteOption
                key={route.route_id}
                route={route}
                label={optionLabel(route, routes, index)}
                isBusy={selecting === route.route_id}
                onSelect={() => select(route.route_id)}
              />
            ))}
          </ul>
        </section>
      ) : (
        /* One route is a perfectly good answer and is reported as one, rather
           than as a missing feature. Nothing here invents a second option. */
        <p className="route__single" role="note">
          Your provider returned one route for this journey.
        </p>
      )}

      {/*
        The handoff. Enabled only with a selected route, because restaurant
        discovery is "along this route" and there is nothing to be along without
        one. Restart Module 07 owns what happens next; until then the
        destination says so rather than dead-ending.
      */}
      <Link
        className={`route__cta ${selected === null ? 'route__cta--disabled' : ''}`}
        to={selected === null ? '#' : `/trips/${tripId}/restaurants?route=${selected.route_id}`}
        aria-disabled={selected === null}
        onClick={(event) => {
          if (selected === null) event.preventDefault();
        }}
      >
        Find food on this route <ArrowRight size={18} aria-hidden="true" />
      </Link>
    </div>
  );
};
