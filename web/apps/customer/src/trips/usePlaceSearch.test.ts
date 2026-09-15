import { describe, expect, it, vi, afterEach } from 'vitest';
import { act, renderHook, waitFor } from '@testing-library/react';
import { usePlaceSearch, DEBOUNCE_MS, MIN_QUERY_LENGTH } from './usePlaceSearch.js';

/**
 * What autocomplete costs.
 *
 * These are cost-control tests, not rendering tests. Every one of them is about
 * a number on an invoice: how many requests six keystrokes produce, and whether
 * the provider is asked to bill one session or six.
 */

const TOKEN = 'test-token-not-a-real-credential';

const suggestions = [{ place_id: 'dev:jaipur-airport', primary_text: 'Jaipur International Airport', secondary_text: 'Jaipur, Rajasthan' }];

const stubFetch = () => {
  const mock = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    headers: new Headers({ 'X-Request-Id': 'req-1' }),
    text: async () => JSON.stringify({ data: suggestions, meta: { request_id: 'req-1' } }),
  });
  vi.stubGlobal('fetch', mock);
  return mock;
};

const urlsOf = (mock: ReturnType<typeof vi.fn>): string[] =>
  mock.mock.calls.map((call) => String(call[0]));

afterEach(() => vi.unstubAllGlobals());

/**
 * Real timers, not fake ones.
 *
 * The first version of this file used `vi.useFakeTimers`, and the whole suite
 * hung: the hook's debounce is a timer, but `waitFor` is *also* a timer, and a
 * fake clock that only advances when a test tells it to leaves the assertion
 * waiting for a tick that will never come. Real timers cost about half a second
 * per test and remove a class of failure that looks like a bug in the code
 * under test rather than in the harness.
 */
const settle = () => new Promise((resolve) => setTimeout(resolve, DEBOUNCE_MS + 120));

describe('usePlaceSearch', () => {
  it('sends one request for a whole word typed a letter at a time', async () => {
    const fetchMock = stubFetch();
    const { result } = renderHook(() => usePlaceSearch(TOKEN, () => {}));

    for (const query of ['j', 'ja', 'jai', 'jaip', 'jaipu', 'jaipur']) {
      act(() => result.current.setQuery(query));
      // Faster than the debounce, as a person typing is.
      await act(() => new Promise((resolve) => setTimeout(resolve, 40)));
    }

    await act(settle);
    await waitFor(() => expect(result.current.state.status).toBe('results'));

    // Six keystrokes, one request, and it is the *last* query — not the first.
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(urlsOf(fetchMock)[0]).toContain('q=jaipur');
  });

  it('sends nothing at all below the minimum length', async () => {
    const fetchMock = stubFetch();
    const { result } = renderHook(() => usePlaceSearch(TOKEN, () => {}));

    act(() => result.current.setQuery('j'));
    await act(settle);

    expect(MIN_QUERY_LENGTH).toBe(2);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.current.state.status).toBe('idle');
  });

  it('reuses one session token across the keystrokes of one search', async () => {
    const fetchMock = stubFetch();
    const { result } = renderHook(() => usePlaceSearch(TOKEN, () => {}));

    act(() => result.current.setQuery('jaipur'));
    await act(settle);
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

    act(() => result.current.setQuery('jaipur airport'));
    await act(settle);
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));

    const tokens = urlsOf(fetchMock).map((url) => new URL(url, 'http://x').searchParams.get('session_token'));
    expect(tokens[0]).toBeTruthy();
    expect(tokens[1]).toBe(tokens[0]);
  });

  it('starts a new session once a place has been chosen', async () => {
    const fetchMock = stubFetch();
    const { result } = renderHook(() => usePlaceSearch(TOKEN, () => {}));

    act(() => result.current.setQuery('jaipur'));
    await act(settle);
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    const first = result.current.sessionToken();

    // What the picker does when a suggestion is taken: that session is over.
    act(() => result.current.endSession());
    act(() => result.current.setQuery('agra'));
    await act(settle);
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));

    const second = new URL(urlsOf(fetchMock)[1] ?? '', 'http://x').searchParams.get('session_token');
    expect(second).toBeTruthy();
    expect(second).not.toBe(first);
  });

  it('reports no results separately from a failure', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        headers: new Headers(),
        text: async () => JSON.stringify({ data: [], meta: { request_id: 'r' } }),
      }),
    );

    const { result } = renderHook(() => usePlaceSearch(TOKEN, () => {}));
    act(() => result.current.setQuery('zzzzqqqq'));
    await act(settle);

    await waitFor(() => expect(result.current.state.status).toBe('empty'));
  });

  it('reports a provider failure as a failure', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 503,
        headers: new Headers(),
        text: async () =>
          JSON.stringify({
            error: { code: 'PLACE_LOOKUP_FAILED', message: 'We could not load places right now.', request_id: 'r' },
          }),
      }),
    );

    const { result } = renderHook(() => usePlaceSearch(TOKEN, () => {}));
    act(() => result.current.setQuery('jaipur'));
    await act(settle);

    await waitFor(() => expect(result.current.state.status).toBe('failed'));
    if (result.current.state.status === 'failed') {
      expect(result.current.state.message).toBe('We could not load places right now.');
    }
  });

  it('hands a 401 to the session rather than showing it as a search error', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 401,
        headers: new Headers(),
        text: async () =>
          JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Authentication is required.', request_id: 'r' } }),
      }),
    );

    const onSessionOver = vi.fn();
    const { result } = renderHook(() => usePlaceSearch(TOKEN, onSessionOver));
    act(() => result.current.setQuery('jaipur'));
    await act(settle);

    await waitFor(() => expect(onSessionOver).toHaveBeenCalledOnce());
    expect(result.current.state.status).not.toBe('failed');
  });
});
