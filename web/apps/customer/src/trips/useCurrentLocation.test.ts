import { describe, expect, it, vi, afterEach } from 'vitest';
import { act, renderHook, waitFor } from '@testing-library/react';
import { useCurrentLocation, FAILURE_COPY } from './useCurrentLocation.js';

/**
 * The browser's location, and the six ways it does not arrive.
 *
 * Every case here produces a distinct message, because the action differs:
 * blocked permission means browser settings, an insecure page means https, and
 * nothing at all means use one of the other two ways to pick a place. One
 * "location unavailable" for all of them would be easier to write and useless
 * to the person reading it.
 */

const TOKEN = 'test-token-not-a-real-credential';

/** India Gate, New Delhi — a controlled test location, not anybody's home. */
const TEST_FIX = { latitude: 28.6129, longitude: 77.2295, accuracy: 40 };

const stubGeolocation = (impl: (ok: PositionCallback, fail: PositionErrorCallback) => void) => {
  vi.stubGlobal('navigator', {
    geolocation: {
      getCurrentPosition: (ok: PositionCallback, fail: PositionErrorCallback) => impl(ok, fail),
    },
  });
};

const position = (coords: typeof TEST_FIX) =>
  ({ coords: { ...coords, altitude: null, altitudeAccuracy: null, heading: null, speed: null }, timestamp: Date.now() }) as GeolocationPosition;

const geolocationError = (code: number) =>
  ({ code, message: '', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }) as GeolocationPositionError;

const noPlaceName = () =>
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers(),
      text: async () => JSON.stringify({ data: null, meta: { request_id: 'r' } }),
    }),
  );

afterEach(() => vi.unstubAllGlobals());

describe('useCurrentLocation', () => {
  it('asks for nothing until the customer asks', () => {
    const getCurrentPosition = vi.fn();
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition } });

    renderHook(() => useCurrentLocation(TOKEN));

    // The whole permission-prompt-on-launch problem, in one assertion: mounting
    // the hook must not trigger the browser's prompt.
    expect(getCurrentPosition).not.toHaveBeenCalled();
  });

  it('refuses before touching the API on an insecure page', () => {
    const getCurrentPosition = vi.fn();
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition } });

    // One property of the real window, not a replacement object. Replacing
    // `window` wholesale took `document` with it, and testing-library then
    // failed with "Expected container to be an Element" — a harness error that
    // reads exactly like a bug in the code under test.
    const original = Object.getOwnPropertyDescriptor(window, 'isSecureContext');
    Object.defineProperty(window, 'isSecureContext', { value: false, configurable: true });

    try {
      const { result } = renderHook(() => useCurrentLocation(TOKEN));
      act(() => result.current.request());

      // Synchronous: the refusal happens before any async work starts.
      expect(result.current.state.status).toBe('failed');
      if (result.current.state.status === 'failed') {
        expect(result.current.state.reason).toBe('insecure-context');
        expect(FAILURE_COPY[result.current.state.reason]).toContain('https');
      }

      // Not asked. On an insecure origin the browser fails every call with a
      // permission error, which would be shown as "you denied us" — blaming the
      // customer for the deployment having no TLS.
      expect(getCurrentPosition).not.toHaveBeenCalled();
    } finally {
      if (original === undefined) {
        Reflect.deleteProperty(window, 'isSecureContext');
      } else {
        Object.defineProperty(window, 'isSecureContext', original);
      }
    }
  });

  it('keeps the device coordinates when nothing can name them', async () => {
    stubGeolocation((ok) => ok(position(TEST_FIX)));
    noPlaceName();

    const { result } = renderHook(() => useCurrentLocation(TOKEN));
    act(() => result.current.request());

    await waitFor(() => expect(result.current.state.status).toBe('resolved'));
    if (result.current.state.status !== 'resolved') return;

    expect(result.current.state.selection.latitude).toBe(TEST_FIX.latitude);
    expect(result.current.state.selection.longitude).toBe(TEST_FIX.longitude);
    // The one thing that must never happen: a street address nobody supplied.
    expect(result.current.state.selection.displayName).toBe('Current location');
    expect(result.current.state.selection.formattedAddress).toBeNull();
    expect(result.current.state.accuracyMetres).toBe(40);
  });

  it('takes the label from the server but never the position', async () => {
    stubGeolocation((ok) => ok(position(TEST_FIX)));
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        headers: new Headers(),
        text: async () =>
          JSON.stringify({
            data: {
              place_id: 'dev:connaught-place',
              display_name: 'New Delhi',
              formatted_address: 'New Delhi, Delhi',
              // A provider that answered with a position two kilometres away.
              latitude: 28.6315,
              longitude: 77.2167,
              city: 'New Delhi',
              region: 'Delhi',
              country_code: 'IN',
              postal_code: null,
            },
            meta: { request_id: 'r' },
          }),
      }),
    );

    const { result } = renderHook(() => useCurrentLocation(TOKEN));
    act(() => result.current.request());

    await waitFor(() => {
      expect(result.current.state.status === 'resolved' && result.current.state.selection.displayName).toBe('New Delhi');
    });
    if (result.current.state.status !== 'resolved') return;

    // The label improved; the coordinates are still the device's.
    expect(result.current.state.selection.latitude).toBe(TEST_FIX.latitude);
    expect(result.current.state.selection.longitude).toBe(TEST_FIX.longitude);
  });

  it('separates a denied permission from a timeout', async () => {
    stubGeolocation((_ok, fail) => fail(geolocationError(1)));
    const denied = renderHook(() => useCurrentLocation(TOKEN));
    act(() => denied.result.current.request());
    await waitFor(() => {
      expect(denied.result.current.state.status === 'failed' && denied.result.current.state.reason).toBe('denied');
    });

    stubGeolocation((_ok, fail) => fail(geolocationError(3)));
    const timedOut = renderHook(() => useCurrentLocation(TOKEN));
    act(() => timedOut.result.current.request());
    await waitFor(() => {
      expect(timedOut.result.current.state.status === 'failed' && timedOut.result.current.state.reason).toBe('timeout');
    });

    expect(FAILURE_COPY.denied).not.toBe(FAILURE_COPY.timeout);
  });

  it('gives up when the browser never answers at all', async () => {
    // Exactly what a blocked origin did in the live run: neither callback, and
    // the browser's own `timeout` option not honoured either. Without the
    // watchdog the button spins for ever and the only way out is a reload.
    stubGeolocation(() => {});

    vi.useFakeTimers();
    try {
      const { result } = renderHook(() => useCurrentLocation(TOKEN));
      act(() => result.current.request());
      expect(result.current.state.status).toBe('requesting');

      act(() => void vi.advanceTimersByTime(15_100));

      expect(result.current.state.status).toBe('failed');
      if (result.current.state.status === 'failed') {
        expect(result.current.state.reason).toBe('no-response');
      }
    } finally {
      vi.useRealTimers();
    }
  });

  it('says so when the browser has no geolocation API', async () => {
    vi.stubGlobal('navigator', {});
    const { result } = renderHook(() => useCurrentLocation(TOKEN));
    act(() => result.current.request());

    await waitFor(() => {
      expect(result.current.state.status === 'failed' && result.current.state.reason).toBe('unsupported');
    });
  });
});
