/**
 * The single HTTP client for both shells. It understands the API's response
 * envelope and error contract (docs/05-api-standards.md) so no screen has to.
 */

export interface ApiEnvelope<T> {
  data: T;
  meta: { request_id: string } & Record<string, unknown>;
}

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    request_id: string;
    details?: unknown;
  };
}

/**
 * Carries the server's machine-readable code and the request id.
 *
 * The request id is surfaced in the UI on failure on purpose: it is the string a
 * user quotes to support, and it is the same id in our logs for that request.
 */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly requestId: string | null,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/**
 * Where the API lives, as a prefix to join to a path.
 *
 * The fallback is the empty string, meaning **same origin** — not a host and
 * port. It used to be `http://localhost:8000`, which is correct for `vite dev`
 * (still set that way in .env.development) and wrong everywhere else: nothing
 * passes VITE_API_BASE_URL to the production build, so both deployed shells
 * asked the *viewer's own machine* for the API and reported "API unreachable".
 * Nobody saw it until the shells were first opened in a browser, because until
 * then their assets 404ed and no page rendered at all.
 *
 * Same origin is the accurate answer rather than a convenient one: deploy/nginx
 * serves `location ^~ /api` from the same server as these bundles, so the origin
 * the page was loaded from is where its API is. It is also what lets one build
 * work on :8080 today and on 443 later without being rebuilt between them.
 */
const baseUrl = (): string =>
  (import.meta.env.VITE_API_BASE_URL as string | undefined)?.replace(/\/$/, '') ?? '';

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: unknown;
  signal?: AbortSignal;
  /** Sent as Idempotency-Key; only meaningful on unsafe methods. */
  idempotencyKey?: string;
  /**
   * A customer bearer token.
   *
   * Authorization header only, never a query parameter: a token in a URL ends
   * up in access logs, proxy logs and the Referer sent to the next site. Passed
   * in per request rather than held in a module variable so that signing out
   * cannot leave a token behind in this module for the next caller to send.
   */
  token?: string;
}

export const apiRequest = async <T>(path: string, options: RequestOptions = {}): Promise<ApiEnvelope<T>> => {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  if (options.idempotencyKey) headers['Idempotency-Key'] = options.idempotencyKey;
  if (options.token) headers.Authorization = `Bearer ${options.token}`;

  let response: Response;
  try {
    response = await fetch(`${baseUrl()}${path}`, {
      method: options.method ?? 'GET',
      headers,
      credentials: 'include',
      ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
      ...(options.signal ? { signal: options.signal } : {}),
    });
  } catch (caught) {
    if ((caught as Error).name === 'AbortError') throw caught;
    // A transport failure is not a server error and must not be reported as one:
    // "the API is down" and "your connection dropped" need different user action.
    throw new ApiError(0, 'NETWORK_ERROR', 'Could not reach the FoodOnTheGo API.', null);
  }

  const requestId = response.headers.get('X-Request-Id');

  if (response.status === 204) {
    return { data: undefined as T, meta: { request_id: requestId ?? '' } };
  }

  const text = await response.text();
  let payload: unknown;
  try {
    payload = text ? JSON.parse(text) : undefined;
  } catch {
    throw new ApiError(response.status, 'MALFORMED_RESPONSE', 'The API returned a response that could not be read.', requestId);
  }

  if (!response.ok) {
    const body = payload as ApiErrorBody | undefined;
    throw new ApiError(
      response.status,
      body?.error?.code ?? 'UNKNOWN_ERROR',
      body?.error?.message ?? `Request failed with status ${response.status}.`,
      body?.error?.request_id ?? requestId,
      body?.error?.details,
    );
  }

  return payload as ApiEnvelope<T>;
};
