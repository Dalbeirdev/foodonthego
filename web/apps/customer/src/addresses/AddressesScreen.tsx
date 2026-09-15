import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft, Home, Loader2, MapPin, Plus, Search, Trash2 } from 'lucide-react';
import { Button, Card } from '@fotg/ui';
import { useSession } from '../session/SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';
import { fetchPlaceDetails, toNumber, type SavedAddress } from '../trips/tripsApi.js';
import { usePlaceSearch, MIN_QUERY_LENGTH } from '../trips/usePlaceSearch.js';
import { isSessionOver, messageFor } from '../trips/tripErrors.js';
import { createAddress, deleteAddress, listAddresses, type NewAddress } from './addressesApi.js';
import './addresses.css';

/**
 * Saved places — the smallest version that makes Restart Module 05 work.
 *
 * An address is created *from a place the customer picked*, not from free text
 * that somebody later tries to geocode. That is a deliberate constraint: an
 * address created here always has real coordinates, so it is always usable for a
 * journey, and the "saved address with no map location" case the server guards
 * against can never be created by this screen.
 *
 * Flat, floor and landmark are still free text on top of it, because "Flat 4B"
 * is not a thing any gazetteer knows and the person who lives there does.
 */

const TYPES = [
  { value: 'HOME', label: 'Home' },
  { value: 'WORK', label: 'Work' },
  { value: 'OTHER', label: 'Other' },
] as const;

type AddressType = (typeof TYPES)[number]['value'];

const newIdempotencyKey = (): string =>
  typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `a-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;

interface LocatedPlace {
  readonly placeId: string;
  readonly displayName: string;
  readonly formattedAddress: string;
  readonly city: string;
  readonly state: string;
  readonly postalCode: string;
  readonly countryCode: string;
  readonly latitude: number;
  readonly longitude: number;
}

const typeLabel = (address: SavedAddress): string =>
  address.type === 'HOME' ? 'Home' : address.type === 'WORK' ? 'Work' : address.label?.trim() || 'Other';

export const AddressesScreen = () => {
  const { state: sessionState, signOut } = useSession();
  const token = sessionState.status === 'authenticated' ? sessionState.session.token : '';

  const [addresses, setAddresses] = useState<readonly SavedAddress[] | null>(null);
  const [listError, setListError] = useState<string | null>(null);
  const [reloads, setReloads] = useState(0);

  const [adding, setAdding] = useState(false);
  const [type, setType] = useState<AddressType>('HOME');
  const [label, setLabel] = useState('');
  const [line2, setLine2] = useState('');
  const [landmark, setLandmark] = useState('');
  const [located, setLocated] = useState<LocatedPlace | null>(null);
  const [locating, setLocating] = useState(false);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const search = usePlaceSearch(token, signOut);
  const reload = useCallback(() => setReloads((n) => n + 1), []);

  useEffect(() => {
    if (token === '') return;
    const controller = new AbortController();
    setAddresses(null);
    setListError(null);

    void (async () => {
      try {
        const response = await listAddresses({ token, signal: controller.signal });
        // Same reason as TripsScreen: a list that is not a list must not take
        // the page down with it.
        setAddresses(Array.isArray(response.data) ? response.data : []);
      } catch (caught) {
        if (caught instanceof Error && caught.name === 'AbortError') return;
        if (isSessionOver(caught)) {
          signOut();
          return;
        }
        setListError(messageFor(caught));
      }
    })();

    return () => controller.abort();
  }, [token, reloads, signOut]);

  const resetForm = useCallback(() => {
    setAdding(false);
    setType('HOME');
    setLabel('');
    setLine2('');
    setLandmark('');
    setLocated(null);
    setFormError(null);
    search.reset();
  }, [search]);

  const locate = useCallback(
    (placeId: string) => {
      setLocating(true);
      setFormError(null);

      void (async () => {
        try {
          const response = await fetchPlaceDetails({ token }, placeId, search.sessionToken());
          const details = response.data;
          const latitude = toNumber(details.latitude);
          const longitude = toNumber(details.longitude);

          if (latitude === null || longitude === null) {
            setFormError('That place does not have a location we can use. Try another.');
            return;
          }

          search.endSession();

          setLocated({
            placeId: details.place_id,
            displayName: details.display_name,
            formattedAddress: details.formatted_address ?? details.display_name,
            // Left empty rather than filled with a plausible guess when the
            // provider does not say. The customer completes it; nothing here
            // invents a city.
            city: details.city ?? '',
            state: details.region ?? '',
            postalCode: details.postal_code ?? '',
            countryCode: details.country_code ?? '',
            latitude,
            longitude,
          });
          search.setQuery('');
        } catch (caught) {
          if (isSessionOver(caught)) {
            signOut();
            return;
          }
          setFormError(messageFor(caught));
        } finally {
          setLocating(false);
        }
      })();
    },
    [token, search, signOut],
  );

  const save = useCallback(() => {
    if (located === null) return;

    const payload: NewAddress = {
      type,
      label: type === 'OTHER' ? label.trim() : null,
      /*
       | The place's *name*, not its whole formatted address.
       |
       | The server composes `formatted_address` itself from line 1, city, state,
       | postcode and country (AddressFormatter). Sending the full formatted
       | string as line 1 therefore produced "Green Park, New Delhi, Delhi
       | 110016, New Delhi, Delhi 110016, IN" — every part twice. Caught by
       | reading the row back after the first address this screen created.
       |
       | Falls back to the formatted address when a name is too short for the
       | server's `min:3`, which a one-word place can be.
       */
      address_line_1: (
        located.displayName.trim().length >= 3 ? located.displayName : located.formattedAddress
      ).slice(0, 180),
      address_line_2: line2.trim() === '' ? null : line2.trim(),
      landmark: landmark.trim() === '' ? null : landmark.trim(),
      city: located.city.trim(),
      state: located.state.trim(),
      postal_code: located.postalCode.trim() === '' ? null : located.postalCode.trim(),
      country_code: located.countryCode.trim().toUpperCase(),
      latitude: located.latitude,
      longitude: located.longitude,
      place_id: located.placeId,
    };

    setSaving(true);
    setFormError(null);

    void (async () => {
      try {
        await createAddress({ token }, payload, newIdempotencyKey());
        resetForm();
        reload();
      } catch (caught) {
        if (isSessionOver(caught)) {
          signOut();
          return;
        }
        setFormError(messageFor(caught));
      } finally {
        setSaving(false);
      }
    })();
  }, [located, type, label, line2, landmark, token, resetForm, reload, signOut]);

  const remove = useCallback(
    (addressId: string) => {
      void (async () => {
        try {
          await deleteAddress({ token }, addressId);
          reload();
        } catch (caught) {
          if (isSessionOver(caught)) {
            signOut();
            return;
          }
          setListError(messageFor(caught));
        }
      })();
    },
    [token, reload, signOut],
  );

  if (sessionState.status !== 'authenticated') return <AppLoading />;

  const suggestions = search.state.status === 'results' ? search.state.suggestions : [];
  const canSave =
    located !== null &&
    located.city.trim() !== '' &&
    located.state.trim() !== '' &&
    located.countryCode.trim().length === 2 &&
    (type !== 'OTHER' || label.trim() !== '') &&
    !saving;

  return (
    <div className="addresses">
      <header className="addresses__head">
        <Link className="addresses__back" to="/profile">
          <ArrowLeft size={16} aria-hidden="true" /> Profile
        </Link>
        <h1 className="addresses__title">Saved places</h1>
      </header>

      {listError !== null ? (
        <Card>
          <p className="addresses__error" role="alert">
            {listError}
          </p>
          <Button onClick={reload}>Try again</Button>
        </Card>
      ) : null}

      {addresses === null && listError === null ? (
        <AppLoading />
      ) : (
        <ul className="addresses__list">
          {(addresses ?? []).map((address) => (
            <li key={address.id}>
              <Card className="addresses__row">
                <div className="addresses__row-main">
                  <Home size={18} aria-hidden="true" />
                  <span className="addresses__row-text">
                    <span className="addresses__row-label">{typeLabel(address)}</span>
                    <span className="addresses__row-address">{address.formatted_address ?? ''}</span>
                  </span>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  aria-label={`Remove ${typeLabel(address)}`}
                  onClick={() => remove(address.id)}
                  icon={<Trash2 size={16} />}
                />
              </Card>
            </li>
          ))}
        </ul>
      )}

      {addresses !== null && addresses.length === 0 && !adding ? (
        <Card>
          <h2 className="addresses__empty-title">No saved places yet</h2>
          <p className="addresses__empty-line">
            Save the places you travel from and to, and they&rsquo;ll be one tap away when you plan
            a journey.
          </p>
        </Card>
      ) : null}

      {!adding ? (
        <Button variant="primary" onClick={() => setAdding(true)} icon={<Plus size={18} />}>
          Add a saved place
        </Button>
      ) : (
        <Card className="addresses__form">
          <h2 className="addresses__form-title">Add a saved place</h2>

          <fieldset className="addresses__types">
            <legend className="addresses__legend">What is this place?</legend>
            {TYPES.map((option) => (
              <label key={option.value} className="addresses__type">
                <input
                  type="radio"
                  name="address-type"
                  value={option.value}
                  checked={type === option.value}
                  onChange={() => setType(option.value)}
                />
                {option.label}
              </label>
            ))}
          </fieldset>

          {type === 'OTHER' ? (
            <label className="addresses__label">
              Name this place
              <input
                className="addresses__input"
                value={label}
                onChange={(event) => setLabel(event.target.value)}
                maxLength={60}
                placeholder="Gym, parents&rsquo; house…"
              />
            </label>
          ) : null}

          {located === null ? (
            <>
              <label className="addresses__label" htmlFor="address-place-search">
                Find the place
              </label>
              <div className="addresses__search">
                <Search size={16} aria-hidden="true" />
                <input
                  id="address-place-search"
                  className="addresses__input"
                  type="search"
                  autoComplete="off"
                  placeholder="Town, landmark or address"
                  value={search.query}
                  onChange={(event) => search.setQuery(event.target.value)}
                />
              </div>

              <div aria-live="polite">
                {search.state.status === 'searching' ? (
                  <p className="addresses__hint">
                    <Loader2 size={15} className="picker__spin" aria-hidden="true" /> Searching…
                  </p>
                ) : null}
                {search.state.status === 'idle' && search.query.trim().length > 0 ? (
                  <p className="addresses__hint">
                    Keep typing — at least {MIN_QUERY_LENGTH} characters.
                  </p>
                ) : null}
                {search.state.status === 'empty' ? (
                  <p className="addresses__hint">No places match that search.</p>
                ) : null}
                {search.state.status === 'failed' ? (
                  <p className="addresses__error" role="alert">
                    {search.state.message}
                  </p>
                ) : null}

                {suggestions.length > 0 ? (
                  <ul className="addresses__suggestions">
                    {suggestions.map((suggestion) => (
                      <li key={suggestion.place_id}>
                        <button
                          type="button"
                          className="addresses__suggestion"
                          onClick={() => locate(suggestion.place_id)}
                          disabled={locating}
                        >
                          <MapPin size={16} aria-hidden="true" />
                          <span>
                            <span className="addresses__suggestion-primary">
                              {suggestion.primary_text}
                            </span>
                            <span className="addresses__suggestion-secondary">
                              {suggestion.secondary_text}
                            </span>
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                ) : null}
              </div>
            </>
          ) : (
            <>
              <div className="addresses__located">
                <MapPin size={16} aria-hidden="true" />
                <span>
                  <strong>{located.displayName}</strong>
                  <br />
                  {located.formattedAddress}
                </span>
                <Button variant="ghost" size="sm" onClick={() => setLocated(null)}>
                  Change
                </Button>
              </div>

              <label className="addresses__label">
                Flat, floor or building <span className="addresses__optional">(optional)</span>
                <input
                  className="addresses__input"
                  value={line2}
                  onChange={(event) => setLine2(event.target.value)}
                  maxLength={180}
                />
              </label>

              <label className="addresses__label">
                Landmark <span className="addresses__optional">(optional)</span>
                <input
                  className="addresses__input"
                  value={landmark}
                  onChange={(event) => setLandmark(event.target.value)}
                  maxLength={120}
                />
              </label>

              {/* Shown and editable rather than hidden. The provider fills these
                  in most of the time and gets them wrong some of the time, and
                  the person standing in the building is the better authority. */}
              <div className="addresses__grid">
                <label className="addresses__label">
                  City
                  <input
                    className="addresses__input"
                    value={located.city}
                    onChange={(event) => setLocated({ ...located, city: event.target.value })}
                    maxLength={90}
                  />
                </label>
                <label className="addresses__label">
                  State
                  <input
                    className="addresses__input"
                    value={located.state}
                    onChange={(event) => setLocated({ ...located, state: event.target.value })}
                    maxLength={90}
                  />
                </label>
                <label className="addresses__label">
                  Postcode <span className="addresses__optional">(optional)</span>
                  <input
                    className="addresses__input"
                    value={located.postalCode}
                    onChange={(event) => setLocated({ ...located, postalCode: event.target.value })}
                    maxLength={16}
                  />
                </label>
                <label className="addresses__label">
                  Country
                  <input
                    className="addresses__input"
                    value={located.countryCode}
                    onChange={(event) =>
                      setLocated({ ...located, countryCode: event.target.value.toUpperCase() })
                    }
                    maxLength={2}
                    placeholder="IN"
                  />
                </label>
              </div>
            </>
          )}

          {formError !== null ? (
            <p className="addresses__error" role="alert">
              {formError}
            </p>
          ) : null}

          <div className="addresses__actions">
            <Button variant="primary" onClick={save} disabled={!canSave}>
              {saving ? 'Saving…' : 'Save place'}
            </Button>
            <Button variant="ghost" onClick={resetForm}>
              Cancel
            </Button>
          </div>
        </Card>
      )}
    </div>
  );
};
