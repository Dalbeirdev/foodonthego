import { apiRequest, type ApiEnvelope } from '@fotg/ui';
import type { Trip } from '../trips/tripsApi.js';

/**
 * The three route endpoints, and the one rule that shapes all of them.
 *
 * **Nothing here sends a distance, a duration, a traffic figure, a polyline or
 * a selection flag.** The only thing a customer's browser tells the server is
 * *which* of the routes it already calculated they want. Everything else comes
 * from the provider by way of the backend, which is what makes the numbers on
 * the screen worth anything.
 *
 * `GET /routes` deliberately never calculates. A GET that can spend money is a
 * GET that spends money on every screen rebuild, and that is this module's
 * largest cost risk.
 */

export interface RouteBounds {
  readonly north: number | string | null;
  readonly south: number | string | null;
  readonly east: number | string | null;
  readonly west: number | string | null;
}

export interface TripRoute {
  readonly route_id: string;
  readonly provider: string;
  readonly provider_route_index: number;
  readonly summary: string | null;
  readonly distance_meters: number | null;
  readonly duration_seconds: number | null;
  readonly traffic_duration_seconds: number | null;
  readonly traffic_delay_seconds: number | null;
  readonly encoded_polyline: string | null;
  readonly bounds: RouteBounds;
  readonly is_recommended: boolean;
  readonly is_selected: boolean;
  readonly calculated_at: string | null;
}

export interface RoutePayload {
  readonly trip: Trip;
  readonly routes: readonly TripRoute[];
}

interface Call {
  readonly token: string;
  readonly signal?: AbortSignal;
}

/** Reads what has already been calculated. Never calls a provider. */
export const fetchRoutes = (call: Call, tripId: string): Promise<ApiEnvelope<RoutePayload>> =>
  apiRequest<RoutePayload>(`/api/v1/customer/trips/${encodeURIComponent(tripId)}/routes`, {
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });

/**
 * Calculates, or returns what is already known and still fresh.
 *
 * POST because it writes and may call a billed third party. `refresh` skips the
 * freshness window and is wired only to an explicit "work it out again" button —
 * never to a screen open, a focus event or a retry loop.
 */
export const calculateRoute = (
  call: Call,
  tripId: string,
  options: { readonly refresh?: boolean } = {},
): Promise<ApiEnvelope<RoutePayload>> =>
  apiRequest<RoutePayload>(
    `/api/v1/customer/trips/${encodeURIComponent(tripId)}/route/calculate${options.refresh === true ? '?refresh=true' : ''}`,
    { method: 'POST', token: call.token, ...(call.signal ? { signal: call.signal } : {}) },
  );

/** Chooses one of the calculated routes. Sends nothing but which one. */
export const selectRoute = (
  call: Call,
  tripId: string,
  routeId: string,
): Promise<ApiEnvelope<RoutePayload>> =>
  apiRequest<RoutePayload>(
    `/api/v1/customer/trips/${encodeURIComponent(tripId)}/routes/${encodeURIComponent(routeId)}/select`,
    { method: 'POST', token: call.token, ...(call.signal ? { signal: call.signal } : {}) },
  );

/**
 * A provider whose output is not a real route.
 *
 * `development` is a straight-line stand-in the backend uses where no routing
 * credentials exist. It cannot be mistaken for a real provider in the database
 * or in a log, and it must not be mistaken for one on screen either — the route
 * screen renders a notice for any route this returns true for.
 */
export const isSyntheticProvider = (provider: string | null | undefined): boolean =>
  provider === 'development' || provider === 'unconfigured';
