import { ApiError } from '@fotg/ui';

/**
 * Turns a failure into a sentence a customer can act on.
 *
 * An allow-list, exactly as `authApi.ts` does it, and for the same reason: the
 * server's message is written for a person, but only for the codes we have read.
 * A code this file has never heard of gets the generic line rather than having
 * an unreviewed string rendered into the page — that is how internal detail
 * ends up on a customer's screen.
 */
const SAFE_CODES = new Set([
  'VALIDATION_FAILED',
  'SAME_LOCATION',
  'INVALID_COORDINATES',
  'SAVED_ADDRESS_NOT_LOCATED',
  'ADDRESS_NOT_FOUND',
  'ADDRESS_LIMIT_REACHED',
  'TRIP_LIMIT_REACHED',
  'TRIP_NOT_FOUND',
  'TRIP_NOT_EDITABLE',
  'PLACE_LOOKUP_FAILED',
  'PLACE_NOT_FOUND',
  'RATE_LIMITED',

  /*
   | Restart Module 06's route codes.
   |
   | Added because the allow-list was doing its job too well: a real 503 from
   | the calculate endpoint carried "We could not work out a route right now."
   | — written for a customer, and cleared by the backend's own test that a
   | provider failure says nothing about our quota or our key — and this file
   | replaced it with the generic line because it had never heard of the code.
   | Found by driving the provider-error state in a browser.
   |
   | Each of these has been read. None of them names a provider, a project, a
   | key or a quota; `RouteProviderRateLimited` answers "Route planning is busy
   | right now", which is the customer's version of that fact.
   */
  'ROUTE_NOT_FOUND',
  'ROUTE_STALE',
  'ROUTE_INPUT_INVALID',
  'ROUTE_SELECTION_INVALID',
  'ROUTE_PROVIDER_UNAVAILABLE',
  'ROUTE_PROVIDER_RATE_LIMITED',
]);

export const GENERIC_FAILURE = 'Something went wrong. Please try again.';

export const messageFor = (error: unknown): string => {
  if (!(error instanceof ApiError)) return GENERIC_FAILURE;

  // A dropped connection is not a server fault and must not be reported as one:
  // "we couldn't reach the server" tells somebody to check their signal, which
  // is the action that actually helps when they are driving out of coverage.
  if (error.code === 'NETWORK_ERROR') {
    return 'We could not reach FoodOnTheGo. Check your connection and try again.';
  }

  if (error.status === 401) return 'Your session has ended. Sign in again to continue.';

  return SAFE_CODES.has(error.code) && error.message !== '' ? error.message : GENERIC_FAILURE;
};

/**
 * Whether this failure means the session is over.
 *
 * Every screen asks the one question rather than each deciding what a 401 is,
 * so signing out on an expired token happens in one place per screen and cannot
 * drift into "some screens log you out and some show an error".
 */
export const isSessionOver = (error: unknown): boolean =>
  error instanceof ApiError && error.status === 401;
