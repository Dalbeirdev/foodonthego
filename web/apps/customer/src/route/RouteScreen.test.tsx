import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { RouteScreen } from './RouteScreen.js';
import { SessionProvider } from '../session/SessionProvider.js';

/**
 * The route screen, through the real API client.
 *
 * `fetch` is stubbed rather than the module boundary, so these exercise the real
 * request shapes — which is where this module's cost and security properties
 * live. A test that mocked `calculateRoute` would prove the screen calls a
 * function, not that opening it twice does not spend money twice.
 *
 * The multi-route cases matter most here. The development routing provider
 * returns a single route by design and will never produce an alternative, so
 * these are the only place the alternatives UI can be driven at all — and a
 * component test with fixture data is a test, not a screenshot presented as
 * evidence of a live feature.
 */

const TOKEN = 'test-token-not-a-real-credential';
const TRIP = 'trip-uuid-1';

/** Real coordinates: Green Park, New Delhi to Jaipur International Airport. */
const POLYLINE = 'ss{nDwtxtM~vbc@~nwqC';

const trip = (over: Record<string, unknown> = {}) => ({
  id: TRIP,
  status: 'ROUTE_PENDING',
  route_status: 'READY',
  origin: {
    source_type: 'SAVED_ADDRESS',
    display_name: 'Home',
    formatted_address: 'Green Park, New Delhi, Delhi 110016, IN',
    latitude: '28.5590000',
    longitude: '77.2070000',
    place_id: 'dev:green-park',
    city: 'New Delhi',
    region: 'Delhi',
    country_code: 'IN',
    postal_code: '110016',
  },
  destination: {
    source_type: 'PLACE_SEARCH',
    display_name: 'Jaipur International Airport',
    formatted_address: 'Sanganer, Jaipur, Rajasthan 302029',
    latitude: '26.8242000',
    longitude: '75.8122000',
    place_id: 'dev:jaipur-airport',
    city: 'Jaipur',
    region: 'Rajasthan',
    country_code: 'IN',
    postal_code: '302029',
  },
  created_at: '2026-09-15T10:00:00+00:00',
  cancelled_at: null,
  selected_route: null,
  ...over,
});

const route = (over: Record<string, unknown> = {}) => ({
  route_id: 'route-1',
  provider: 'google',
  provider_route_index: 0,
  summary: 'NH 48',
  distance_meters: 236_786,
  duration_seconds: 14_179,
  traffic_duration_seconds: null,
  traffic_delay_seconds: null,
  encoded_polyline: POLYLINE,
  bounds: { north: '28.5590000', south: '26.8242000', east: '77.2070000', west: '75.8122000' },
  is_recommended: true,
  is_selected: true,
  calculated_at: new Date().toISOString(),
  ...over,
});

const ok = (data: unknown) => ({
  ok: true,
  status: 200,
  headers: new Headers({ 'X-Request-Id': 'req-1' }),
  text: async () => JSON.stringify({ data, meta: { request_id: 'req-1' } }),
});

const fail = (status: number, code: string, message: string) => ({
  ok: false,
  status,
  headers: new Headers({ 'X-Request-Id': 'req-1' }),
  text: async () => JSON.stringify({ error: { code, message, request_id: 'req-1' } }),
});

interface Recorded {
  readonly url: string;
  readonly method: string;
}

const stubApi = (options: {
  get?: unknown;
  calculate?: unknown;
  select?: (routeId: string) => unknown;
}) => {
  const calls: Recorded[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init: RequestInit = {}) => {
      calls.push({ url, method: init.method ?? 'GET' });

      if (url.includes('/route/calculate')) {
        return options.calculate ?? ok({ trip: trip(), routes: [route()] });
      }
      if (url.includes('/select')) {
        const id = url.split('/routes/')[1]?.split('/')[0] ?? '';
        return options.select?.(id) ?? ok({ trip: trip(), routes: [route()] });
      }
      if (url.includes('/routes')) {
        return options.get ?? ok({ trip: trip(), routes: [route()] });
      }
      throw new Error(`unstubbed ${url}`);
    }),
  );
  return calls;
};

const renderScreen = () => {
  window.sessionStorage.setItem('fotg.customer.session', JSON.stringify({ token: TOKEN }));
  return render(
    <SessionProvider>
      <MemoryRouter initialEntries={[`/trips/${TRIP}`]}>
        <Routes>
          <Route path="/trips/:tripId" element={<RouteScreen />} />
          <Route path="/trips/:tripId/restaurants" element={<p>Restaurant listing</p>} />
          <Route path="/trips/plan" element={<p>Planner</p>} />
          <Route path="/login" element={<p>Sign in</p>} />
        </Routes>
      </MemoryRouter>
    </SessionProvider>,
  );
};

beforeEach(() => window.sessionStorage.clear());
afterEach(() => vi.unstubAllGlobals());

describe('RouteScreen', () => {
  it('shows the distance and travel time the server sent', async () => {
    stubApi({});
    renderScreen();

    expect(await screen.findByText('237 km')).toBeInTheDocument();
    expect(screen.getByText('3 hr 56 min')).toBeInTheDocument();
  });

  it('draws the route and its two ends', async () => {
    stubApi({});
    renderScreen();

    await screen.findByText('237 km');
    // One line for the route, one marker at each end. Drawn from the decoded
    // polyline, so an empty or undecodable geometry renders nothing at all
    // rather than a straight line between the bounds corners.
    expect(document.querySelectorAll('.route-shape__line')).toHaveLength(1);
    expect(document.querySelectorAll('.route-shape__marker')).toHaveLength(2);
  });

  it('says plainly that there are no map tiles', async () => {
    stubApi({});
    renderScreen();

    // By its text, not by role: the screen has more than one note on it and
    // `getByRole('note')` matched all of them. A harness error, not a defect.
    expect(
      await screen.findByText(/Map tiles are not available in this build/),
    ).toBeInTheDocument();
    expect(screen.getByText(/real shape of your journey/)).toBeInTheDocument();
  });

  it('does not calculate when a usable route already exists', async () => {
    const calls = stubApi({});
    renderScreen();

    await screen.findByText('237 km');

    // The whole cost control in one assertion: opening the screen reads, and
    // reading is free. A POST here is a billed provider call on every visit.
    expect(calls.filter((call) => call.method === 'POST')).toHaveLength(0);
    expect(calls.filter((call) => call.url.includes('/route/calculate'))).toHaveLength(0);
  });

  it('calculates once when nothing has been worked out yet', async () => {
    const calls = stubApi({
      get: ok({ trip: trip({ route_status: 'NOT_CALCULATED' }), routes: [] }),
    });
    renderScreen();

    await screen.findByText('237 km');

    const posts = calls.filter((call) => call.url.includes('/route/calculate'));
    expect(posts).toHaveLength(1);
    // Never with refresh: that flag is for a button a person presses.
    expect(posts[0]?.url).not.toContain('refresh=true');
  });

  it('asks again only when the customer asks', async () => {
    const calls = stubApi({});
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText('237 km');
    await user.click(screen.getByRole('button', { name: /Work it out again/ }));

    await waitFor(() =>
      expect(calls.some((call) => call.url.includes('refresh=true'))).toBe(true),
    );
  });

  it('never claims traffic the provider did not return', async () => {
    stubApi({});
    renderScreen();

    expect(
      await screen.findByText('Traffic information is not available for this route.'),
    ).toBeInTheDocument();
    expect(screen.queryByText(/with current traffic/)).not.toBeInTheDocument();
  });

  it('shows traffic when there is a real figure', async () => {
    stubApi({
      get: ok({
        trip: trip(),
        routes: [route({ traffic_duration_seconds: 16_000 })],
      }),
    });
    renderScreen();

    expect(await screen.findByText(/with current traffic/)).toBeInTheDocument();
    expect(screen.getByText(/slower than usual/)).toBeInTheDocument();
  });

  it('warns when the figures come from a synthetic provider', async () => {
    stubApi({
      get: ok({ trip: trip(), routes: [route({ provider: 'development' })] }),
    });
    renderScreen();

    expect(await screen.findByText(/These figures are not a real route/)).toBeInTheDocument();
  });

  it('does not warn when the provider is a real one', async () => {
    stubApi({});
    renderScreen();

    await screen.findByText('237 km');
    expect(screen.queryByText(/not a real route/)).not.toBeInTheDocument();
  });

  it('reports a single route as an answer, not as a missing feature', async () => {
    stubApi({});
    renderScreen();

    expect(
      await screen.findByText('Your provider returned one route for this journey.'),
    ).toBeInTheDocument();
    expect(screen.queryByText('Choose your route')).not.toBeInTheDocument();
  });

  it('offers every route the provider returned', async () => {
    stubApi({
      get: ok({
        trip: trip(),
        routes: [
          route({ route_id: 'r1', duration_seconds: 14_179, is_selected: true }),
          route({ route_id: 'r2', duration_seconds: 15_900, is_selected: false, provider_route_index: 1 }),
        ],
      }),
    });
    renderScreen();

    expect(await screen.findByText('Choose your route')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^Fastest\./ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^Route 2\./ })).toBeInTheDocument();
  });

  it('takes the selection from the server, not from a local flag', async () => {
    const calls = stubApi({
      get: ok({
        trip: trip(),
        routes: [
          route({ route_id: 'r1', is_selected: true }),
          route({ route_id: 'r2', is_selected: false, duration_seconds: 15_900, provider_route_index: 1 }),
        ],
      }),
      select: (id) =>
        ok({
          trip: trip(),
          routes: [
            route({ route_id: 'r1', is_selected: id === 'r1' }),
            route({
              route_id: 'r2',
              is_selected: id === 'r2',
              duration_seconds: 15_900,
              provider_route_index: 1,
            }),
          ],
        }),
    });
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText('Choose your route');
    await user.click(screen.getByRole('button', { name: /^Route 2\./ }));

    await waitFor(() =>
      expect(screen.getByRole('button', { name: /Route 2.*Currently selected/ })).toBeInTheDocument(),
    );

    const posts = calls.filter((call) => call.url.includes('/select'));
    expect(posts).toHaveLength(1);
    expect(posts[0]?.url).toContain('/routes/r2/select');
  });

  it('carries the trip and the selected route to the restaurant listing', async () => {
    stubApi({});
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText('237 km');
    const cta = screen.getByRole('link', { name: /Find food on this route/ });
    expect(cta).toHaveAttribute('href', `/trips/${TRIP}/restaurants?route=route-1`);

    await user.click(cta);
    expect(await screen.findByText('Restaurant listing')).toBeInTheDocument();
  });

  it('will not send anybody to find food without a route', async () => {
    stubApi({
      get: ok({ trip: trip({ route_status: 'NO_ROUTE' }), routes: [] }),
    });
    renderScreen();

    expect(await screen.findByText('No driving route found')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /Find food/ })).not.toBeInTheDocument();
  });

  it('offers a way out when the provider fails, and says what happened', async () => {
    stubApi({
      get: ok({ trip: trip({ route_status: 'NOT_CALCULATED' }), routes: [] }),
      calculate: fail(503, 'ROUTE_PROVIDER_UNAVAILABLE', 'We could not work out a route right now.'),
    });
    renderScreen();

    // The server's own words, not the generic line. The allow-list in
    // tripErrors.ts had never heard of the route codes, so a perfectly
    // customer-safe message was being replaced with "Something went wrong" —
    // found by driving this state in a browser, not by a test.
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'We could not work out a route right now.',
    );
    expect(screen.getByRole('button', { name: /Try again/ })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Change journey/ })).toBeInTheDocument();
  });

  it('never shows a provider quota or key to a customer', async () => {
    stubApi({
      get: ok({ trip: trip({ route_status: 'NOT_CALCULATED' }), routes: [] }),
      calculate: fail(
        500,
        'SOME_INTERNAL_CODE',
        'quota exceeded for project fotg-123, API key AIza…',
      ),
    });
    renderScreen();

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Something went wrong. Please try again.');
    expect(alert).not.toHaveTextContent(/AIza/);
    expect(alert).not.toHaveTextContent(/quota/);
  });

  it('ends the session rather than showing a 401', async () => {
    stubApi({ get: fail(401, 'UNAUTHENTICATED', 'Authentication is required.') });
    renderScreen();

    /*
     | The screen's own contract is to *end the session*, not to navigate.
     | Redirecting is `RequireSession`'s job and it wraps the whole shell, which
     | is why one place decides what a 401 means rather than every screen.
     |
     | The first version of this test asserted the sign-in screen appeared and
     | failed, because this harness renders the route screen without that guard.
     | The harness was wrong, not the code — but the assertion is better this
     | way round regardless: it tests what this file is responsible for.
     */
    await waitFor(() =>
      expect(window.sessionStorage.getItem('fotg.customer.session')).toBeNull(),
    );

    // And it does not render the failure as a screen-level error.
    expect(screen.queryByText(/could not work out your route/i)).not.toBeInTheDocument();
  });

  it('shows the route in text as well as in the drawing', async () => {
    stubApi({});
    renderScreen();

    // The map is never the only representation: everything it shows is also
    // readable, because a drawing is unusable to a screen reader and
    // unavailable to anybody whose tiles will not load.
    await screen.findByText('237 km');
    expect(screen.getByText('Distance')).toBeInTheDocument();
    expect(screen.getByText('Estimated travel time')).toBeInTheDocument();
    expect(screen.getByText('From')).toBeInTheDocument();
    expect(screen.getByText('To')).toBeInTheDocument();
  });
});
