import { useCallback, useEffect, useRef, useState } from 'react';
import { isSessionOver, messageFor } from '../trips/tripErrors.js';
import {
  calculateRoute,
  fetchRoutes,
  selectRoute as selectRouteApi,
  type RoutePayload,
} from './routeApi.js';

/**
 * The route screen's whole state, as one machine rather than six booleans.
 *
 * The distinction that matters most is between **loading** and **calculating**.
 * Reading a route that already exists is instant and free; working one out may
 * take seconds and costs money. A screen that showed the same spinner for both
 * would make a billed call look like a page load, which is how a cost problem
 * stays invisible.
 */

export type RouteState =
  | { readonly status: 'loading' }
  | { readonly status: 'calculating'; readonly data: RoutePayload | null }
  | { readonly status: 'ready'; readonly data: RoutePayload }
  | { readonly status: 'noRoute'; readonly data: RoutePayload }
  | { readonly status: 'failed'; readonly message: string; readonly data: RoutePayload | null };

/** Route statuses that mean there is something to draw. */
const USABLE = new Set(['READY', 'STALE']);

export const useRoute = (token: string, tripId: string, onSessionOver: () => void) => {
  const [state, setState] = useState<RouteState>({ status: 'loading' });
  const [selecting, setSelecting] = useState<string | null>(null);

  const onSessionOverRef = useRef(onSessionOver);
  onSessionOverRef.current = onSessionOver;

  /**
   * Whether this screen has already asked the server to calculate.
   *
   * A ref, not state, and never reset by a re-render. Without it the effect
   * below could fire a second calculation while the first was still running —
   * the exact "every screen rebuild is a billed request" failure the GET/POST
   * split exists to prevent.
   */
  const attempted = useRef(false);

  const apply = useCallback((payload: RoutePayload) => {
    const status = payload.trip.route_status;

    if (status === 'NO_ROUTE') {
      setState({ status: 'noRoute', data: payload });
      return;
    }

    if (USABLE.has(status) && payload.routes.length > 0) {
      setState({ status: 'ready', data: payload });
      return;
    }

    if (status === 'FAILED') {
      setState({
        status: 'failed',
        message: 'We could not work out a route for this journey.',
        data: payload,
      });
      return;
    }

    // NOT_CALCULATED or CALCULATING with nothing to show yet.
    setState({ status: 'calculating', data: payload });
  }, []);

  /**
   * Loads what exists, and calculates only if there is nothing usable.
   *
   * Two requests at most on a first open, and exactly one — the free GET — on
   * every open after that while the route stays fresh. The server's freshness
   * window then decides whether the POST reaches the provider at all.
   */
  const load = useCallback(
    async (signal: AbortSignal) => {
      try {
        const existing = await fetchRoutes({ token, signal }, tripId);
        const payload = existing.data;

        const usable = USABLE.has(payload.trip.route_status) && payload.routes.length > 0;
        const terminal = payload.trip.route_status === 'NO_ROUTE';

        if (usable || terminal || attempted.current) {
          apply(payload);
          return;
        }

        attempted.current = true;
        setState({ status: 'calculating', data: payload });

        const calculated = await calculateRoute({ token, signal }, tripId);
        apply(calculated.data);
      } catch (caught) {
        if (caught instanceof Error && caught.name === 'AbortError') return;
        if (isSessionOver(caught)) {
          onSessionOverRef.current();
          return;
        }
        setState((current) => ({
          status: 'failed',
          message: messageFor(caught),
          data: 'data' in current ? current.data : null,
        }));
      }
    },
    [token, tripId, apply],
  );

  useEffect(() => {
    if (token === '' || tripId === '') return;
    const controller = new AbortController();
    attempted.current = false;
    setState({ status: 'loading' });
    void load(controller.signal);
    return () => controller.abort();
  }, [token, tripId, load]);

  /**
   * An explicit "work it out again".
   *
   * The only path in this app that sets `refresh`, and it is wired to a button
   * a person presses. Nothing automatic reaches it — not a focus event, not a
   * retry, not a poll.
   */
  const refresh = useCallback(() => {
    const controller = new AbortController();
    setState((current) => ({ status: 'calculating', data: 'data' in current ? current.data : null }));

    void (async () => {
      try {
        const result = await calculateRoute({ token, signal: controller.signal }, tripId, {
          refresh: true,
        });
        apply(result.data);
      } catch (caught) {
        if (caught instanceof Error && caught.name === 'AbortError') return;
        if (isSessionOver(caught)) {
          onSessionOverRef.current();
          return;
        }
        setState((current) => ({
          status: 'failed',
          message: messageFor(caught),
          data: 'data' in current ? current.data : null,
        }));
      }
    })();
  }, [token, tripId, apply]);

  /**
   * Chooses a route.
   *
   * The server's answer replaces the whole payload rather than this client
   * flipping a flag locally. That is what makes "exactly one selected" true on
   * screen as well as in the database: if the server refused, or selected
   * something else, the screen shows what the server did.
   */
  const select = useCallback(
    (routeId: string) => {
      setSelecting(routeId);

      void (async () => {
        try {
          const result = await selectRouteApi({ token }, tripId, routeId);
          apply(result.data);
        } catch (caught) {
          if (isSessionOver(caught)) {
            onSessionOverRef.current();
            return;
          }
          setState((current) => ({
            status: 'failed',
            message: messageFor(caught),
            data: 'data' in current ? current.data : null,
          }));
        } finally {
          setSelecting(null);
        }
      })();
    },
    [token, tripId, apply],
  );

  return { state, refresh, select, selecting };
};
