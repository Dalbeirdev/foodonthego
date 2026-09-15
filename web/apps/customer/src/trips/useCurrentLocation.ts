import { useCallback, useEffect, useRef, useState } from 'react';
import { reverseGeocode } from './tripsApi.js';
import type { LocationSelection } from './location.js';

/**
 * The browser's location, asked for only when the customer asks for it.
 *
 * Nothing here runs on mount. `navigator.geolocation.getCurrentPosition` is what
 * triggers Chrome's permission prompt, and calling it as the screen loads is how
 * an app asks a stranger where they are before showing them anything — so it is
 * called from the button handler and nowhere else.
 *
 * `enableHighAccuracy` is false. The planner needs the town, not the lane: a
 * high-accuracy fix costs battery and seconds for precision that changes no
 * decision this module makes.
 *
 * There is no `watchPosition` anywhere in this app. Continuous location is live
 * tracking, which this module does not own and must not quietly acquire the
 * habit of.
 */

export type CurrentLocationState =
  | { readonly status: 'idle' }
  | { readonly status: 'requesting' }
  | {
      readonly status: 'resolved';
      readonly selection: LocationSelection;
      /** What the device claims, in metres. Shown, never used to reject a fix. */
      readonly accuracyMetres: number | null;
    }
  | { readonly status: 'failed'; readonly reason: CurrentLocationFailure };

/**
 * Why it did not work, in the customer's terms.
 *
 * Distinct cases because the action differs: a denied permission needs browser
 * settings, an insecure page needs https, and a timeout needs another tap. One
 * "location unavailable" for all three tells somebody nothing they can use.
 */
export type CurrentLocationFailure =
  | 'denied'
  | 'unsupported'
  | 'insecure-context'
  | 'position-unavailable'
  | 'timeout'
  /**
   * The browser was asked and said nothing at all.
   *
   * Not a theoretical case. Restart Module 05's live run found that when
   * geolocation is blocked for the origin, this Chromium calls *neither*
   * callback — and does not honour its own `timeout` option either, so the
   * request never ends. Without the watchdog below, "Use my current location"
   * span forever and the customer's only way out was to reload the page.
   */
  | 'no-response';

export const FAILURE_COPY: Record<CurrentLocationFailure, string> = {
  denied:
    'Location is blocked for this site. Allow it in your browser settings, or choose a saved address or search for a place instead.',
  unsupported:
    'This browser cannot share your location. Choose a saved address or search for a place instead.',
  'insecure-context':
    'Browsers only share your location over a secure (https) connection. Choose a saved address or search for a place instead.',
  'position-unavailable':
    'We could not get a location fix. Check that location services are on, or choose a saved address or search for a place instead.',
  timeout: 'Getting your location took too long. Try again, or choose a place another way.',
  'no-response':
    'Your browser did not answer our request for your location. It may be blocked for this site. Choose a saved address or search for a place instead.',
};

const TIMEOUT_MS = 12_000;

/**
 * How long a *label* may delay a usable fix.
 *
 * Shorter than the geolocation timeout on purpose: the coordinates are the
 * feature and the street name is a courtesy, so the courtesy is the part that
 * gets cut when the network is slow.
 */
const LABEL_TIMEOUT_MS = 3_000;

/** Never reused: a fix from ten minutes ago is not where the customer is now. */
const MAX_AGE_MS = 0;

/**
 * Our own deadline on the whole request.
 *
 * Longer than `TIMEOUT_MS` so a browser that *does* honour its timeout reports
 * the accurate 'timeout'; this only catches the case where neither callback
 * ever arrives. A screen must not depend on a third party calling it back to
 * leave a loading state — that is a spinner with no exit, and this app had one
 * until a live run sat on it for twenty seconds.
 */
const WATCHDOG_MS = 15_000;

export const useCurrentLocation = (token: string) => {
  const [state, setState] = useState<CurrentLocationState>({ status: 'idle' });
  const abortRef = useRef<AbortController | null>(null);
  const watchdogRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearWatchdog = useCallback(() => {
    if (watchdogRef.current !== null) {
      clearTimeout(watchdogRef.current);
      watchdogRef.current = null;
    }
  }, []);

  const reset = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
    clearWatchdog();
    setState({ status: 'idle' });
  }, [clearWatchdog]);

  // A request outliving the screen that made it has nobody to answer to.
  useEffect(() => () => {
    abortRef.current?.abort();
    if (watchdogRef.current !== null) clearTimeout(watchdogRef.current);
  }, []);

  const request = useCallback(() => {
    // Checked before `navigator.geolocation` is touched, because on an insecure
    // origin Chrome leaves the object in place and fails every call with a
    // permission error — which would be reported as "you denied us", blaming the
    // customer for the deployment not having TLS.
    if (typeof window !== 'undefined' && window.isSecureContext === false) {
      setState({ status: 'failed', reason: 'insecure-context' });
      return;
    }

    if (typeof navigator === 'undefined' || navigator.geolocation === undefined) {
      setState({ status: 'failed', reason: 'unsupported' });
      return;
    }

    setState({ status: 'requesting' });

    let settled = false;

    /** Whichever answer arrives first wins; the rest are ignored. */
    const claim = (): boolean => {
      if (settled) return false;
      settled = true;
      clearWatchdog();
      return true;
    };

    watchdogRef.current = setTimeout(() => {
      if (claim()) setState({ status: 'failed', reason: 'no-response' });
    }, WATCHDOG_MS);

    navigator.geolocation.getCurrentPosition(
      (position) => {
        const { latitude, longitude, accuracy } = position.coords;
        const accuracyMetres = Number.isFinite(accuracy) ? Math.round(accuracy) : null;

        // The coordinates are kept whatever the accuracy says. A 900 m fix from
        // a wifi lookup still names the right town, and refusing it would turn a
        // usable starting point into a dead end for exactly the customers whose
        // GPS is worst. The figure is carried instead, so a caller can show it.
        const base: LocationSelection = {
          sourceType: 'CURRENT_LOCATION',
          displayName: 'Current location',
          formattedAddress: null,
          placeId: null,
          latitude,
          longitude,
          savedAddressId: null,
          city: null,
          region: null,
          countryCode: null,
          postalCode: null,
        };

        // Claimed the moment the fix arrives, so the watchdog cannot fire while
        // the optional label lookup is still running.
        if (!claim()) return;

        const controller = new AbortController();
        abortRef.current = controller;

        void (async () => {
          /*
           | Awaited, not fired and forgotten.
           |
           | The first version resolved on the device fix immediately and
           | improved the label when the lookup came back. That read well and did
           | not work: a resolved fix *is* the choice, so the picker closed, this
           | hook unmounted, and the answer arrived for a component that no
           | longer existed. The call was paid for and the label was thrown away
           | — visible in the live run as a reverse-geocode request followed by a
           | field still reading "Current location" two kilometres from a place
           | the gazetteer knows.
           |
           | Bounded, because a naming call must never be what stops somebody
           | setting off: past the deadline the fix resolves unnamed, which is
           | exactly what happens when the provider has no name for it.
           */
          const label = await Promise.race([
            reverseGeocode({ token, signal: controller.signal }, latitude, longitude)
              .then((response) => response.data)
              .catch(() => null),
            new Promise<null>((resolve) => setTimeout(() => resolve(null), LABEL_TIMEOUT_MS)),
          ]);

          if (label === null || label === undefined) {
            setState({ status: 'resolved', selection: base, accuracyMetres });
            return;
          }

          setState({
            status: 'resolved',
            accuracyMetres,
            selection: {
              ...base,
              // Only the *label* is taken from the lookup. The position stays
              // the device's, because that is the authoritative fact here and a
              // geocoder's idea of where a road is could move the origin by a
              // kilometre.
              displayName: label.display_name || 'Current location',
              formattedAddress: label.formatted_address,
              placeId: label.place_id ?? null,
              city: label.city,
              region: label.region,
              countryCode: label.country_code,
              postalCode: label.postal_code,
            },
          });
        })();
      },
      (error) => {
        const reason: CurrentLocationFailure =
          error.code === error.PERMISSION_DENIED
            ? 'denied'
            : error.code === error.TIMEOUT
              ? 'timeout'
              : 'position-unavailable';
        if (claim()) setState({ status: 'failed', reason });
      },
      { enableHighAccuracy: false, timeout: TIMEOUT_MS, maximumAge: MAX_AGE_MS },
    );
  }, [token, clearWatchdog]);

  return { state, request, reset };
};
