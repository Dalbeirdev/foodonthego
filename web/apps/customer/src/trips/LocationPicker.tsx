import { useCallback, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Crosshair, Loader2, MapPin, Search, Star, X } from 'lucide-react';
import { Button } from '@fotg/ui';
import { fetchPlaceDetails, toNumber, type SavedAddress } from './tripsApi.js';
import type { LocationSelection } from './location.js';
import { usePlaceSearch, MIN_QUERY_LENGTH } from './usePlaceSearch.js';
import { useCurrentLocation, FAILURE_COPY } from './useCurrentLocation.js';
import { isSessionOver, messageFor } from './tripErrors.js';

/**
 * Choosing one end of a journey.
 *
 * A dialog rather than a dropdown, at every width. A popover that has to become
 * a sheet below 900px is two layouts, two sets of focus rules and two ways for
 * a long Indian address to overflow; one dialog that fills a phone screen and
 * floats on a desktop is one. The keyboard contract is the same either way.
 */

export type PickerEnd = 'origin' | 'destination';

const labelFor = (address: SavedAddress): string => {
  if (address.type === 'HOME') return 'Home';
  if (address.type === 'WORK') return 'Work';
  return address.label?.trim() || 'Saved place';
};

/**
 * A saved address the server will accept for a journey.
 *
 * Module 04 allows an address with no coordinates — somebody can type where
 * they live without ever putting it on a map. A trip cannot use one, and the
 * server says so with SAVED_ADDRESS_NOT_LOCATED. Showing it as unusable *here*,
 * with the reason, is better than letting the customer pick it and be refused
 * two screens later.
 */
const isUsable = (address: SavedAddress): boolean =>
  toNumber(address.latitude) !== null && toNumber(address.longitude) !== null;

const fromSavedAddress = (address: SavedAddress): LocationSelection => ({
  sourceType: 'SAVED_ADDRESS',
  displayName: labelFor(address),
  formattedAddress: address.formatted_address,
  // Carried for display only. `toRequestBody` sends the id and nothing else,
  // and the server reads the position from the row it owns.
  placeId: address.place_id,
  latitude: toNumber(address.latitude) ?? 0,
  longitude: toNumber(address.longitude) ?? 0,
  savedAddressId: address.id,
  city: address.city,
  region: address.state,
  countryCode: address.country_code,
  postalCode: address.postal_code,
});

interface Props {
  readonly end: PickerEnd;
  readonly token: string;
  readonly savedAddresses: readonly SavedAddress[];
  readonly savedAddressesFailed: boolean;
  readonly onChoose: (selection: LocationSelection) => void;
  readonly onClose: () => void;
  readonly onSessionOver: () => void;
}

export const LocationPicker = ({
  end,
  token,
  savedAddresses,
  savedAddressesFailed,
  onChoose,
  onClose,
  onSessionOver,
}: Props) => {
  const search = usePlaceSearch(token, onSessionOver);
  const location = useCurrentLocation(token);
  const [highlighted, setHighlighted] = useState(-1);
  const [resolving, setResolving] = useState(false);
  const [resolveError, setResolveError] = useState<string | null>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const title = end === 'origin' ? 'Choose your starting point' : 'Choose your destination';

  // Focus lands on the search box, which is the control most people want, and
  // the one that makes the dialog reachable by keyboard at all.
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Escape closes, from anywhere inside. Registered on the dialog rather than
  // the document so an unmounted picker cannot keep swallowing the key.
  const onKeyDownCapture = useCallback(
    (event: React.KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onClose();
      }
    },
    [onClose],
  );

  // A resolved current-location fix is a choice: the customer asked for it, and
  // making them confirm afterwards adds a tap that answers no question.
  useEffect(() => {
    if (location.state.status === 'resolved') {
      onChoose(location.state.selection);
    }
  }, [location.state, onChoose]);

  const suggestions =
    search.state.status === 'results' ? search.state.suggestions : [];

  useEffect(() => setHighlighted(-1), [search.state.status, search.query]);

  const choosePlace = useCallback(
    (placeId: string) => {
      setResolving(true);
      setResolveError(null);

      void (async () => {
        try {
          // The details call, with the same session token the suggestions used.
          // A suggestion has no coordinates — it answers "which place did you
          // mean", not "where is it" — so routing on its text would put the
          // journey at the centroid of a search term.
          const response = await fetchPlaceDetails({ token }, placeId, search.sessionToken());
          const details = response.data;
          const latitude = toNumber(details.latitude);
          const longitude = toNumber(details.longitude);

          if (latitude === null || longitude === null) {
            setResolveError('That place does not have a location we can use. Try another.');
            return;
          }

          // The session ends when a place is chosen — that is what the provider
          // bills as one session, and reusing the token afterwards would be
          // billing a second search against a finished one.
          search.endSession();

          onChoose({
            sourceType: 'PLACE_SEARCH',
            displayName: details.display_name,
            formattedAddress: details.formatted_address,
            placeId: details.place_id,
            latitude,
            longitude,
            savedAddressId: null,
            city: details.city,
            region: details.region,
            countryCode: details.country_code,
            postalCode: details.postal_code,
          });
        } catch (caught) {
          if (isSessionOver(caught)) {
            onSessionOver();
            return;
          }
          setResolveError(messageFor(caught));
        } finally {
          setResolving(false);
        }
      })();
    },
    [token, search, onChoose, onSessionOver],
  );

  /**
   * Arrow keys move through the list, Enter takes the highlighted one.
   *
   * Handled on the input rather than on the options, because focus never leaves
   * the input — that is what `aria-activedescendant` is for, and it is what lets
   * somebody keep typing to narrow the list without tabbing back.
   */
  const onSearchKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (suggestions.length === 0) return;

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setHighlighted((index) => (index + 1) % suggestions.length);
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      setHighlighted((index) => (index <= 0 ? suggestions.length - 1 : index - 1));
      return;
    }
    if (event.key === 'Enter' && highlighted >= 0) {
      event.preventDefault();
      const chosen = suggestions[highlighted];
      if (chosen !== undefined) choosePlace(chosen.place_id);
    }
  };

  const usableSaved = savedAddresses.filter(isUsable);
  const unusableSaved = savedAddresses.filter((address) => !isUsable(address));

  return (
    <div className="picker__scrim" role="presentation" onClick={onClose}>
      <div
        className="picker"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        ref={dialogRef}
        onClick={(event) => event.stopPropagation()}
        onKeyDownCapture={onKeyDownCapture}
      >
        <header className="picker__head">
          <h2 className="picker__title">{title}</h2>
          <Button
            variant="ghost"
            size="sm"
            aria-label="Close"
            onClick={onClose}
            icon={<X size={18} />}
          />
        </header>

        <div className="picker__body">
          {/* Origin only. A destination defaulting to where somebody already is
              is not a journey, and offering it invites the mistake. */}
          {end === 'origin' ? (
            <section className="picker__section">
              <Button
                variant="secondary"
                className="picker__current"
                onClick={location.request}
                disabled={location.state.status === 'requesting'}
                icon={
                  location.state.status === 'requesting' ? (
                    <Loader2 size={18} className="picker__spin" />
                  ) : (
                    <Crosshair size={18} />
                  )
                }
              >
                {location.state.status === 'requesting'
                  ? 'Getting your location…'
                  : 'Use my current location'}
              </Button>

              {location.state.status === 'failed' ? (
                <p className="picker__error" role="alert">
                  {FAILURE_COPY[location.state.reason]}
                </p>
              ) : null}
            </section>
          ) : null}

          <section className="picker__section">
            <h3 className="picker__section-title">
              <Star size={15} aria-hidden="true" /> Saved places
            </h3>

            {savedAddressesFailed ? (
              <p className="picker__error" role="alert">
                We could not load your saved places. You can still search for one.
              </p>
            ) : savedAddresses.length === 0 ? (
              <div className="picker__empty">
                <p>No saved addresses yet.</p>
                <Link className="picker__link" to="/profile/addresses">
                  Add a saved address
                </Link>
              </div>
            ) : (
              <ul className="picker__list">
                {usableSaved.map((address) => (
                  <li key={address.id}>
                    <button
                      type="button"
                      className="picker__option"
                      onClick={() => onChoose(fromSavedAddress(address))}
                    >
                      <MapPin size={16} aria-hidden="true" />
                      <span className="picker__option-text">
                        <span className="picker__option-primary">{labelFor(address)}</span>
                        <span className="picker__option-secondary">
                          {address.formatted_address ?? ''}
                        </span>
                      </span>
                    </button>
                  </li>
                ))}

                {unusableSaved.map((address) => (
                  <li key={address.id}>
                    <div className="picker__option picker__option--unusable">
                      <MapPin size={16} aria-hidden="true" />
                      <span className="picker__option-text">
                        <span className="picker__option-primary">{labelFor(address)}</span>
                        <span className="picker__option-secondary">
                          Needs a map location before it can be used for a journey.
                        </span>
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="picker__section">
            <h3 className="picker__section-title">
              <Search size={15} aria-hidden="true" /> Search for a place
            </h3>

            <input
              ref={inputRef}
              className="picker__input"
              type="search"
              role="combobox"
              aria-expanded={suggestions.length > 0}
              aria-controls="place-suggestions"
              aria-autocomplete="list"
              aria-label="Search for a place"
              {...(highlighted >= 0 ? { 'aria-activedescendant': `place-option-${highlighted}` } : {})}
              placeholder="Town, landmark or address"
              value={search.query}
              onChange={(event) => search.setQuery(event.target.value)}
              onKeyDown={onSearchKeyDown}
              autoComplete="off"
            />

            <div className="picker__results" aria-live="polite">
              {search.state.status === 'searching' ? (
                <p className="picker__hint">
                  <Loader2 size={15} className="picker__spin" aria-hidden="true" /> Searching…
                </p>
              ) : null}

              {search.state.status === 'idle' && search.query.trim().length > 0 ? (
                <p className="picker__hint">
                  Keep typing — at least {MIN_QUERY_LENGTH} characters.
                </p>
              ) : null}

              {search.state.status === 'empty' ? (
                <p className="picker__hint">No places match that search.</p>
              ) : null}

              {search.state.status === 'failed' ? (
                <p className="picker__error" role="alert">
                  {search.state.message}
                </p>
              ) : null}

              {suggestions.length > 0 ? (
                <ul className="picker__list" id="place-suggestions" role="listbox">
                  {suggestions.map((suggestion, index) => (
                    <li key={suggestion.place_id} role="presentation">
                      <button
                        type="button"
                        id={`place-option-${index}`}
                        role="option"
                        aria-selected={index === highlighted}
                        className={`picker__option ${index === highlighted ? 'picker__option--active' : ''}`}
                        onMouseEnter={() => setHighlighted(index)}
                        onClick={() => choosePlace(suggestion.place_id)}
                        disabled={resolving}
                      >
                        <MapPin size={16} aria-hidden="true" />
                        <span className="picker__option-text">
                          <span className="picker__option-primary">{suggestion.primary_text}</span>
                          <span className="picker__option-secondary">{suggestion.secondary_text}</span>
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              ) : null}

              {resolving ? (
                <p className="picker__hint">
                  <Loader2 size={15} className="picker__spin" aria-hidden="true" /> Getting that
                  place…
                </p>
              ) : null}

              {resolveError !== null ? (
                <p className="picker__error" role="alert">
                  {resolveError}
                </p>
              ) : null}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
};
