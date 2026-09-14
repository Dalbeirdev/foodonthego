import { useCallback, useEffect, useState } from 'react';
import { ApiError, apiRequest } from '@fotg/ui';

/**
 * Only what Home renders. Deliberately narrower than what the endpoint returns:
 * a type that mirrors the whole payload invites screens to reach for fields
 * they should be asking their own endpoint for.
 */
export interface HomeCustomer {
  readonly first_name?: string | null;
  readonly full_name?: string | null;
}

export interface HomeTrip {
  readonly uuid: string;
  readonly status?: string | null;
  readonly origin?: { readonly display_name?: string | null } | null;
  readonly destination?: { readonly display_name?: string | null } | null;
}

export interface HomeOrder {
  readonly uuid: string;
  readonly order_number?: string | null;
  readonly status?: string | null;
  readonly restaurant?: { readonly name?: string | null } | null;
  readonly pickup_start_at?: string | null;
}

export interface HomePayload {
  readonly customer: HomeCustomer | null;
  readonly active_trip: HomeTrip | null;
  readonly active_order: HomeOrder | null;
  readonly notification_summary: { readonly supported: boolean; readonly unread: number | null };
}

export type HomeState =
  | { readonly status: 'loading' }
  | { readonly status: 'ready'; readonly data: HomePayload }
  | { readonly status: 'failed'; readonly error: ApiError };

export const useHome = (token: string, onUnauthorized?: () => void) => {
  const [state, setState] = useState<HomeState>({ status: 'loading' });
  const [reloads, setReloads] = useState(0);

  const reload = useCallback(() => setReloads((n) => n + 1), []);

  useEffect(() => {
    const controller = new AbortController();
    // Reset on every reload so a retry shows the skeleton rather than leaving
    // the old error on screen while the new request is in flight.
    setState({ status: 'loading' });

    void (async () => {
      try {
        const response = await apiRequest<HomePayload>('/api/v1/customer/home', {
          signal: controller.signal,
          token,
        });
        setState({ status: 'ready', data: response.data });
      } catch (caught) {
        // An aborted request is this effect being cleaned up, not a failure.
        // Setting state here would replace a fresh render with a stale error.
        if (caught instanceof Error && caught.name === 'AbortError') return;

        // A 401 is not a screen-level error. The token is gone or revoked, so
        // the session is over and the customer belongs at sign-in — handled in
        // one place rather than re-implemented by every screen that fetches.
        if (caught instanceof ApiError && caught.status === 401) {
          onUnauthorized?.();
          return;
        }

        setState({
          status: 'failed',
          error:
            caught instanceof ApiError
              ? caught
              : new ApiError(0, 'UNKNOWN', 'Something went wrong loading your home screen.', null),
        });
      }
    })();

    return () => controller.abort();
  }, [token, reloads, onUnauthorized]);

  return { state, reload };
};
