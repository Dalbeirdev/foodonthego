import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, apiRequest } from './apiClient.js';

interface Stub {
  ok?: boolean;
  status?: number;
  text?: string;
  requestId?: string;
}

const stubFetch = (stub: Stub) => {
  const mock = vi.fn().mockResolvedValue({
    ok: stub.ok ?? true,
    status: stub.status ?? 200,
    headers: new Headers(stub.requestId ? { 'X-Request-Id': stub.requestId } : {}),
    text: async () => stub.text ?? '',
  });
  vi.stubGlobal('fetch', mock);
  return mock;
};

afterEach(() => vi.unstubAllGlobals());

describe('apiRequest', () => {
  it('unwraps the response envelope', async () => {
    stubFetch({ text: JSON.stringify({ data: { status: 'ready' }, meta: { request_id: 'abc' } }) });

    const response = await apiRequest<{ status: string }>('/api/v1/health/ready');
    expect(response.data.status).toBe('ready');
    expect(response.meta.request_id).toBe('abc');
  });

  it('surfaces the machine-readable error code and the request id', async () => {
    stubFetch({
      ok: false,
      status: 422,
      text: JSON.stringify({
        error: { code: 'VALIDATION_FAILED', message: 'The submitted data is not valid.', request_id: 'req-9' },
      }),
    });

    const error = (await apiRequest('/api/v1/anything').catch((e: unknown) => e)) as ApiError;
    expect(error).toBeInstanceOf(ApiError);
    expect(error.code).toBe('VALIDATION_FAILED');
    expect(error.requestId).toBe('req-9');
    expect(error.status).toBe(422);
  });

  it('distinguishes a transport failure from a server error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));

    const error = (await apiRequest('/api/v1/health/ready').catch((e: unknown) => e)) as ApiError;
    expect(error.code).toBe('NETWORK_ERROR');
    expect(error.status).toBe(0);
  });

  it('reports an unparseable body rather than throwing a SyntaxError at the caller', async () => {
    stubFetch({ text: '<html>502 Bad Gateway</html>' });

    const error = (await apiRequest('/api/v1/health/ready').catch((e: unknown) => e)) as ApiError;
    expect(error.code).toBe('MALFORMED_RESPONSE');
  });

  it('sends an Idempotency-Key when one is supplied', async () => {
    const mock = stubFetch({ text: JSON.stringify({ data: null, meta: { request_id: 'x' } }) });

    await apiRequest('/api/v1/orders', { method: 'POST', body: {}, idempotencyKey: 'key-1' });

    const headers = mock.mock.calls[0]![1].headers as Record<string, string>;
    expect(headers['Idempotency-Key']).toBe('key-1');
  });

  it('handles a 204 with no body', async () => {
    stubFetch({ status: 204, text: '', requestId: 'r-204' });

    const response = await apiRequest('/api/v1/thing', { method: 'DELETE' });
    expect(response.meta.request_id).toBe('r-204');
  });

  it('re-throws an abort so a cancelled request is not treated as a failure', async () => {
    const abort = Object.assign(new Error('aborted'), { name: 'AbortError' });
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(abort));

    await expect(apiRequest('/api/v1/health/ready')).rejects.toMatchObject({ name: 'AbortError' });
  });
});

/**
 * Where a request actually goes.
 *
 * Every assertion here failed on the deployed build. Both shells were compiled
 * with no VITE_API_BASE_URL, fell back to `http://localhost:8000`, and asked the
 * *viewer's own machine* for the API — which is why a freshly deployed dashboard
 * showed "API unreachable" while the API was up and answering on the same host
 * the page had just been served from.
 *
 * Nothing caught it because these tests stub `fetch` and, until this group, only
 * ever looked at what came back. The URL that was passed in was never read.
 */
describe('the API base URL', () => {
  const urlOf = (mock: ReturnType<typeof stubFetch>): string => String(mock.mock.calls[0][0]);

  it('is same-origin by default, not a host and port', async () => {
    const mock = stubFetch({ text: JSON.stringify({ data: {}, meta: { request_id: 'x' } }) });

    await apiRequest('/api/v1/health/ready');

    // Relative. Anything absolute here names a machine that is not necessarily
    // the one serving the page.
    expect(urlOf(mock)).toBe('/api/v1/health/ready');
  });

  it('never points at localhost, which in a browser is the viewer', async () => {
    const mock = stubFetch({ text: JSON.stringify({ data: {}, meta: { request_id: 'x' } }) });

    await apiRequest('/api/v1/health/ready');

    expect(urlOf(mock)).not.toContain('localhost');
    expect(urlOf(mock)).not.toContain('127.0.0.1');
  });

  it('does not carry a scheme or an authority', async () => {
    const mock = stubFetch({ text: JSON.stringify({ data: {}, meta: { request_id: 'x' } }) });

    await apiRequest('/api/v1/health/ready');

    // Asserted rather than assumed: a relative URL is what lets one build work
    // on :8080 today and on 443 through the tunnel later, with no rebuild.
    const resolved = new URL(urlOf(mock), 'http://example.test:9999');
    expect(resolved.origin).toBe('http://example.test:9999');
    expect(resolved.pathname).toBe('/api/v1/health/ready');
  });

  it('does not double the /api prefix the way the Flutter build once did', async () => {
    const mock = stubFetch({ text: JSON.stringify({ data: {}, meta: { request_id: 'x' } }) });

    await apiRequest('/api/v1/health/ready');

    expect(urlOf(mock)).not.toContain('/api/v1/api/v1');
  });
});
