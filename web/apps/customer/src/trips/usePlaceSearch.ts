import { useCallback, useEffect, useRef, useState } from 'react';
import { searchPlaces, type PlaceSuggestion } from './tripsApi.js';
import { isSessionOver, messageFor } from './tripErrors.js';

/**
 * Autocomplete, with the two things that decide what it costs.
 *
 * **Debounce.** 350 ms after the last keystroke, not on every one. Typing
 * "jaipur" is six keystrokes and one request; without this it is six requests,
 * five of which nobody ever sees the results of, and all six of which are billed.
 *
 * **One session per search.** The token is minted when a search begins and sent
 * with every query *and* with the details call that ends it, which is what lets
 * the provider bill an autocomplete session rather than each request. Minting a
 * new one per keystroke — the easy mistake — produces the maximum possible bill
 * while looking exactly like correct code.
 *
 * Stale responses are dropped by aborting the previous request, so a slow answer
 * for "jai" can never overwrite a fast one for "jaipur".
 */

export const DEBOUNCE_MS = 350;

/**
 * Below this, no request is sent at all.
 *
 * Two characters is also the server's own minimum (`'q' => ['min:2']`), so a
 * single character would be a guaranteed 422: a request that cannot succeed is
 * not worth making.
 */
export const MIN_QUERY_LENGTH = 2;

export type PlaceSearchState =
  | { readonly status: 'idle' }
  | { readonly status: 'searching' }
  | { readonly status: 'results'; readonly suggestions: readonly PlaceSuggestion[] }
  | { readonly status: 'empty' }
  | { readonly status: 'failed'; readonly message: string };

const newSessionToken = (): string =>
  typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `s-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export interface PlaceSearchCounters {
  /** Autocomplete requests actually sent. Read by the cost test, not by the UI. */
  readonly searches: number;
}

export const usePlaceSearch = (token: string, onSessionOver: () => void) => {
  const [query, setQuery] = useState('');
  const [state, setState] = useState<PlaceSearchState>({ status: 'idle' });

  // Survives re-renders; replaced only when a search session ends.
  const sessionTokenRef = useRef<string>(newSessionToken());
  const abortRef = useRef<AbortController | null>(null);
  const countRef = useRef(0);

  /*
   | The session-over callback, held in a ref rather than used as a dependency.
   |
   | It was a dependency, and that was an infinite render loop waiting for the
   | first caller who passed an inline arrow: the effect ran, set state, the
   | re-render produced a new function identity, the effect ran again. It never
   | fired in the app — both callers happen to pass a `useCallback`-stable
   | `signOut` — and it hung the whole test suite on the first `renderHook`. A
   | correctness property that depends on every caller remembering to memoise is
   | not a property; this removes the dependency instead.
   */
  const onSessionOverRef = useRef(onSessionOver);
  onSessionOverRef.current = onSessionOver;

  /** Ends the current provider session. Called when a place is chosen, or the
   *  picker closes — the two ways a search finishes. */
  const endSession = useCallback(() => {
    sessionTokenRef.current = newSessionToken();
  }, []);

  const reset = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
    setQuery('');
    setState({ status: 'idle' });
    endSession();
  }, [endSession]);

  useEffect(() => {
    const trimmed = query.trim();

    if (trimmed.length < MIN_QUERY_LENGTH) {
      abortRef.current?.abort();
      // Only when it is not already idle. Writing an equal-but-new object on
      // every pass is the other half of the loop above, and survives on its own
      // as a wasted render per keystroke below the minimum.
      setState((current) => (current.status === 'idle' ? current : { status: 'idle' }));
      return;
    }

    const timer = setTimeout(() => {
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;
      countRef.current += 1;
      setState({ status: 'searching' });

      void (async () => {
        try {
          const response = await searchPlaces(
            { token, signal: controller.signal },
            trimmed,
            sessionTokenRef.current,
          );
          const suggestions = response.data;
          setState(
            suggestions.length === 0
              ? { status: 'empty' }
              : { status: 'results', suggestions },
          );
        } catch (caught) {
          if (caught instanceof Error && caught.name === 'AbortError') return;
          if (isSessionOver(caught)) {
            onSessionOverRef.current();
            return;
          }
          setState({ status: 'failed', message: messageFor(caught) });
        }
      })();
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query, token]);

  // Cleanup on unmount: a request still in flight when the picker closes has
  // nobody to deliver to.
  useEffect(() => () => abortRef.current?.abort(), []);

  return {
    query,
    setQuery,
    state,
    reset,
    endSession,
    sessionToken: (): string => sessionTokenRef.current,
    /** Test and cost-measurement seam. Never rendered. */
    searchCount: (): number => countRef.current,
  };
};
