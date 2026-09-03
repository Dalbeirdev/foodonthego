import { afterEach, describe, expect, it, vi } from 'vitest';
import { api, ApiRequestError, setAuthToken } from './client.js';

/**
 * Only the three things the client actually touches are stubbed. The field is
 * `text` rather than `body` because `Response['body']` is a `ReadableStream`, and
 * borrowing that name for a string is a type error rather than a convenience.
 */
interface StubbedResponse {
  ok?: boolean;
  status?: number;
  text?: string;
}

const mockFetch = (response: StubbedResponse) => {
  const fetchMock = vi.fn().mockResolvedValue({
    ok: response.ok ?? true,
    status: response.status ?? 200,
    text: async () => response.text ?? '',
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
};

afterEach(() => {
  vi.unstubAllGlobals();
  setAuthToken(null);
});

describe('api client', () => {
  it('sends no authorization header when signed out', async () => {
    const fetchMock = mockFetch({ text: '{"items":[],"total":0,"limit":20,"offset":0}' });
    await api.restaurants(new URLSearchParams());

    const headers = fetchMock.mock.calls[0]![1].headers as Record<string, string>;
    expect(headers.authorization).toBeUndefined();
  });

  it('sends the bearer token once one is set', async () => {
    const fetchMock = mockFetch({ text: '{}' });
    setAuthToken('a-token');
    await api.me();

    const headers = fetchMock.mock.calls[0]![1].headers as Record<string, string>;
    expect(headers.authorization).toBe('Bearer a-token');
  });

  it('surfaces the server’s error code and message', async () => {
    mockFetch({
      ok: false,
      status: 409,
      text: '{"error":{"code":"conflict","message":"Cart has another restaurant.","details":{"a":1}}}',
    });

    await expect(api.addToCart({ menuItemId: 'x', quantity: 1 })).rejects.toMatchObject({
      status: 409,
      code: 'conflict',
      message: 'Cart has another restaurant.',
      details: { a: 1 },
    });
  });

  it('reports a network failure as a network failure, not a server error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));

    const error = await api.me().catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(ApiRequestError);
    expect((error as ApiRequestError).code).toBe('network_error');
    expect((error as ApiRequestError).status).toBe(0);
  });

  it('handles a 204 with no body', async () => {
    mockFetch({ status: 204, text: '' });
    await expect(api.setItemAvailability('item-1', false)).resolves.toBeUndefined();
  });

  it('does not swallow an abort', async () => {
    const abortError = Object.assign(new Error('aborted'), { name: 'AbortError' });
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(abortError));

    await expect(api.restaurants(new URLSearchParams())).rejects.toMatchObject({ name: 'AbortError' });
  });
});
