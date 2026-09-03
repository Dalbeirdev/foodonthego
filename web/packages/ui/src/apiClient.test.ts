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
