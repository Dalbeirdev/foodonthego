import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowRight, ArrowUpDown, Flag, Loader2, MapPin, X } from 'lucide-react';
import { Button, Card } from '@fotg/ui';
import { useSession } from '../session/SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';
import { fetchSavedAddresses, createTrip, type SavedAddress } from './tripsApi.js';
import { isSamePlace, type LocationSelection } from './location.js';
import { LocationPicker, type PickerEnd } from './LocationPicker.js';
import { isSessionOver, messageFor } from './tripErrors.js';
import './trips.css';

/**
 * Plan a journey.
 *
 * One screen, two fields, one button. The complexity that exists — three ways
 * to name a place, six ways for the browser's location to fail, a provider that
 * bills per keystroke if you let it — lives in `LocationPicker`, `usePlaceSearch`
 * and `useCurrentLocation`. What is left here is the part the customer thinks
 * about: where from, where to, go.
 *
 * This screen calculates no route, shows no distance and quotes no ETA. Those
 * belong to Restart Module 06, and a planner that guessed at them would be
 * inventing the one number this product's whole promise rests on.
 */

const newIdempotencyKey = (): string =>
  typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `t-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;

const LocationField = ({
  id,
  label,
  placeholder,
  icon,
  selection,
  onOpen,
  onClear,
}: {
  id: string;
  label: string;
  placeholder: string;
  icon: React.ReactNode;
  selection: LocationSelection | null;
  onOpen: () => void;
  onClear: () => void;
}) => (
  <div className="planner__field">
    <span className="planner__field-label" id={`${id}-label`}>
      {label}
    </span>

    <div className="planner__field-row">
      <button
        type="button"
        className={`planner__field-button ${selection === null ? 'planner__field-button--empty' : ''}`}
        onClick={onOpen}
        /* The accessible name carries the label *and* the choice, so a screen
           reader announces "Origin, Home, 12 Test Road" rather than leaving the
           listener to infer which field they are on. */
        aria-label={
          selection === null
            ? `${label}. ${placeholder}`
            : `${label}, ${selection.displayName}${selection.formattedAddress ? `, ${selection.formattedAddress}` : ''}. Change`
        }
      >
        <span className="planner__field-icon" aria-hidden="true">
          {icon}
        </span>
        {selection === null ? (
          <span className="planner__field-placeholder">{placeholder}</span>
        ) : (
          <span className="planner__field-text">
            <span className="planner__field-primary">{selection.displayName}</span>
            {selection.formattedAddress !== null && selection.formattedAddress !== '' ? (
              <span className="planner__field-secondary">{selection.formattedAddress}</span>
            ) : null}
          </span>
        )}
      </button>

      {selection !== null ? (
        <Button
          variant="ghost"
          size="sm"
          aria-label={`Clear ${label.toLowerCase()}`}
          onClick={onClear}
          icon={<X size={16} />}
        />
      ) : null}
    </div>
  </div>
);

export const TripPlannerScreen = () => {
  const { state: sessionState, signOut } = useSession();
  const token = sessionState.status === 'authenticated' ? sessionState.session.token : '';
  const navigate = useNavigate();

  const [origin, setOrigin] = useState<LocationSelection | null>(null);
  const [destination, setDestination] = useState<LocationSelection | null>(null);
  const [picker, setPicker] = useState<PickerEnd | null>(null);

  const [addresses, setAddresses] = useState<readonly SavedAddress[]>([]);
  const [addressesState, setAddressesState] = useState<'loading' | 'ready' | 'failed'>('loading');
  const [addressReloads, setAddressReloads] = useState(0);

  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  /**
   * One key per planned journey, minted on mount and rotated only after a trip
   * is actually created.
   *
   * This is what makes a double tap and a lost response the same thing: both
   * are the same request twice, both carry this key, and the server answers the
   * second from the first. A key minted per attempt would make every retry a
   * new journey — which is the bug this is here to prevent.
   */
  const idempotencyKeyRef = useRef<string>(newIdempotencyKey());

  const reloadAddresses = useCallback(() => setAddressReloads((n) => n + 1), []);

  useEffect(() => {
    if (token === '') return;
    const controller = new AbortController();
    setAddressesState('loading');

    void (async () => {
      try {
        const response = await fetchSavedAddresses({ token, signal: controller.signal });
        setAddresses(Array.isArray(response.data) ? response.data : []);
        setAddressesState('ready');
      } catch (caught) {
        if (caught instanceof Error && caught.name === 'AbortError') return;
        if (isSessionOver(caught)) {
          signOut();
          return;
        }
        // Not fatal. Search and current location still work, and a planner that
        // refused to open because a *list* failed would be worse than one
        // missing a shortcut.
        setAddressesState('failed');
      }
    })();

    return () => controller.abort();
  }, [token, addressReloads, signOut]);

  // Coming back from adding an address must show it. The alternative — a reload
  // or a sign-out — is what "saved addresses do not appear" looks like from the
  // outside.
  useEffect(() => {
    const onFocus = () => reloadAddresses();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [reloadAddresses]);

  const sameLocation = useMemo(
    () => (origin !== null && destination !== null ? isSamePlace(origin, destination) : false),
    [origin, destination],
  );

  const canCreate = origin !== null && destination !== null && !sameLocation && !creating;

  const choose = useCallback(
    (selection: LocationSelection) => {
      if (picker === 'origin') setOrigin(selection);
      if (picker === 'destination') setDestination(selection);
      setPicker(null);
      setCreateError(null);
    },
    [picker],
  );

  const swap = useCallback(() => {
    // Whole objects, not labels. Swapping the visible text and leaving the
    // coordinates behind produces a journey that reads correctly and goes the
    // wrong way, which nobody would catch until the route drew itself.
    setOrigin(destination);
    setDestination(origin);
    setCreateError(null);
  }, [origin, destination]);

  const plan = useCallback(() => {
    if (origin === null || destination === null) return;

    setCreating(true);
    setCreateError(null);

    void (async () => {
      try {
        const response = await createTrip({ token }, origin, destination, idempotencyKeyRef.current);
        idempotencyKeyRef.current = newIdempotencyKey();

        // Only the id is carried across. The route screen loads the trip from
        // the server rather than trusting anything this screen hands it: the
        // authoritative record is the row, and a screen that rendered what the
        // previous screen *said* would happily show a journey that was never
        // saved.
        navigate(`/trips/${response.data.id}`, { replace: true });
      } catch (caught) {
        if (isSessionOver(caught)) {
          signOut();
          return;
        }
        setCreateError(messageFor(caught));
      } finally {
        setCreating(false);
      }
    })();
  }, [origin, destination, token, navigate, signOut]);

  if (sessionState.status !== 'authenticated') return <AppLoading />;

  return (
    <div className="planner">
      <header className="planner__head">
        <h1 className="planner__title">Plan your journey</h1>
        <p className="planner__sub">
          Tell us where you are going and we&rsquo;ll find food worth stopping for along the way.
        </p>
      </header>

      <Card className="planner__card">
        <LocationField
          id="origin"
          label="Starting point"
          placeholder="Choose where you are setting off from"
          icon={<MapPin size={18} />}
          selection={origin}
          onOpen={() => setPicker('origin')}
          onClear={() => setOrigin(null)}
        />

        <div className="planner__swap-row">
          <Button
            variant="ghost"
            size="sm"
            onClick={swap}
            disabled={origin === null && destination === null}
            aria-label="Swap starting point and destination"
            icon={<ArrowUpDown size={16} />}
          >
            Swap
          </Button>
        </div>

        <LocationField
          id="destination"
          label="Destination"
          placeholder="Choose where you are going"
          icon={<Flag size={18} />}
          selection={destination}
          onOpen={() => setPicker('destination')}
          onClear={() => setDestination(null)}
        />

        {sameLocation ? (
          <p className="planner__error" role="alert">
            Your starting point and destination are the same. Choose a different destination.
          </p>
        ) : null}

        {createError !== null ? (
          <p className="planner__error" role="alert">
            {createError}
          </p>
        ) : null}

        <Button
          variant="primary"
          size="lg"
          className="planner__cta"
          onClick={plan}
          disabled={!canCreate}
          icon={creating ? <Loader2 size={18} className="picker__spin" /> : <ArrowRight size={18} />}
        >
          {creating ? 'Planning your journey…' : 'Plan journey'}
        </Button>

        {/* Said out loud rather than implied by an empty map. Module 06 owns the
            route, and a planner that showed a blank canvas here would read as a
            feature that failed rather than one that has not arrived. */}
        <p className="planner__note">
          We&rsquo;ll work out your route on the next screen.
        </p>
      </Card>

      {addressesState === 'loading' ? (
        <p className="planner__hint">Loading your saved places…</p>
      ) : null}

      {picker !== null ? (
        <LocationPicker
          end={picker}
          token={token}
          savedAddresses={addresses}
          savedAddressesFailed={addressesState === 'failed'}
          onChoose={choose}
          onClose={() => setPicker(null)}
          onSessionOver={signOut}
        />
      ) : null}
    </div>
  );
};
