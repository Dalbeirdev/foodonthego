import { apiRequest, type ApiEnvelope } from '@fotg/ui';
import type { LocationSelection } from './location.js';
import { toRequestBody } from './location.js';

/**
 * Every call the trip planner makes, in one file.
 *
 * Place search goes through **this server**, not through a provider SDK in the
 * browser. That is the whole of the key-security answer for Customer Web: the
 * bundle contains no provider key of any kind, restricted or otherwise, because
 * it never talks to a provider. `GET /customer/places/*` is authenticated, so
 * the metered key behind it is not a free geocoder for anyone who finds the URL.
 */

export interface SavedAddress {
  readonly id: string;
  readonly type: 'HOME' | 'WORK' | 'OTHER';
  readonly label: string | null;
  readonly formatted_address: string | null;
  readonly city: string | null;
  readonly state: string | null;
  readonly postal_code: string | null;
  readonly country_code: string | null;
  readonly latitude: number | string | null;
  readonly longitude: number | string | null;
  readonly place_id: string | null;
  readonly is_default: boolean;
}

export interface PlaceSuggestion {
  readonly place_id: string;
  readonly primary_text: string;
  readonly secondary_text: string;
}

export interface PlaceDetails {
  readonly place_id: string;
  readonly display_name: string;
  readonly formatted_address: string | null;
  readonly latitude: number | string;
  readonly longitude: number | string;
  readonly city: string | null;
  readonly region: string | null;
  readonly country_code: string | null;
  readonly postal_code: string | null;
}

export interface TripEndpoint {
  readonly source_type: string;
  readonly display_name: string | null;
  readonly formatted_address: string | null;
  readonly latitude: number | string | null;
  readonly longitude: number | string | null;
  readonly place_id: string | null;
  readonly city: string | null;
  readonly region: string | null;
  readonly country_code: string | null;
  readonly postal_code: string | null;
}

export interface Trip {
  readonly id: string;
  readonly status: string;
  readonly route_status: string;
  readonly origin: TripEndpoint;
  readonly destination: TripEndpoint;
  readonly created_at: string | null;
  readonly cancelled_at: string | null;
  readonly selected_route: unknown;
}

/**
 * The server sends decimals as strings — MySQL DECIMAL round-trips exactly that
 * way through PHP's JSON encoder, and a client that assumed `number` would get
 * `NaN` from arithmetic on a perfectly valid payload.
 */
export const toNumber = (value: number | string | null | undefined): number | null => {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

interface Call {
  readonly token: string;
  readonly signal?: AbortSignal;
}

export const fetchSavedAddresses = (call: Call): Promise<ApiEnvelope<SavedAddress[]>> =>
  apiRequest<SavedAddress[]>('/api/v1/customer/addresses', {
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });

export const searchPlaces = (
  call: Call,
  query: string,
  sessionToken: string,
): Promise<ApiEnvelope<PlaceSuggestion[]>> =>
  apiRequest<PlaceSuggestion[]>(
    `/api/v1/customer/places/search?q=${encodeURIComponent(query)}&session_token=${encodeURIComponent(sessionToken)}`,
    { token: call.token, ...(call.signal ? { signal: call.signal } : {}) },
  );

export const fetchPlaceDetails = (
  call: Call,
  placeId: string,
  sessionToken: string,
): Promise<ApiEnvelope<PlaceDetails>> =>
  apiRequest<PlaceDetails>(
    // The id goes in the path and is percent-encoded: a provider id is an opaque
    // string and has contained slashes before now.
    `/api/v1/customer/places/${encodeURIComponent(placeId)}?session_token=${encodeURIComponent(sessionToken)}`,
    { token: call.token, ...(call.signal ? { signal: call.signal } : {}) },
  );

/**
 * Names a coordinate the device produced.
 *
 * Its failure is not the flow's failure: the coordinates are authoritative
 * whether or not anybody can put a street name to them, so the caller keeps them
 * and falls back to the label "Current location".
 */
export const reverseGeocode = (
  call: Call,
  latitude: number,
  longitude: number,
): Promise<ApiEnvelope<PlaceDetails | null>> =>
  apiRequest<PlaceDetails | null>('/api/v1/customer/places/reverse-geocode', {
    method: 'POST',
    body: { latitude, longitude },
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });

/**
 * Creates the journey.
 *
 * `idempotencyKey` is minted once per *planned journey* — when the planner
 * screen mounts, and again after a successful create — rather than per attempt.
 * That is what makes a lost response safe: the retry carries the same key and
 * the server replays the first answer instead of writing a second trip. Minting
 * it per attempt would be a fresh key on every tap, which is the same as having
 * none at all.
 */
export const createTrip = (
  call: Call,
  origin: LocationSelection,
  destination: LocationSelection,
  idempotencyKey: string,
): Promise<ApiEnvelope<Trip>> =>
  apiRequest<Trip>('/api/v1/customer/trips', {
    method: 'POST',
    body: { origin: toRequestBody(origin), destination: toRequestBody(destination) },
    idempotencyKey,
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });

export const fetchTrips = (call: Call): Promise<ApiEnvelope<Trip[]>> =>
  apiRequest<Trip[]>('/api/v1/customer/trips', {
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });

export const fetchTrip = (call: Call, tripId: string): Promise<ApiEnvelope<Trip>> =>
  apiRequest<Trip>(`/api/v1/customer/trips/${encodeURIComponent(tripId)}`, {
    token: call.token,
    ...(call.signal ? { signal: call.signal } : {}),
  });
