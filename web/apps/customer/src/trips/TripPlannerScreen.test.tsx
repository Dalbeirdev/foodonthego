import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { TripPlannerScreen } from './TripPlannerScreen.js';
import { SessionProvider } from '../session/SessionProvider.js';

/**
 * Planning a journey, end to end, without a browser.
 *
 * The API is stubbed at `fetch` rather than at the module boundary, so these
 * exercise the real client, the real envelope handling and the real request
 * bodies — which is where this module's security properties live. A test that
 * mocked `createTrip` would prove the screen calls a function, not that a saved
 * address is submitted as an identifier alone.
 */

const TOKEN = 'test-token-not-a-real-credential';

/** Real places at their real published positions, as the gazetteer holds them. */
const HOME = {
  id: 'addr-home',
  type: 'HOME' as const,
  label: 'Home',
  formatted_address: 'Green Park, New Delhi, Delhi 110016, IN',
  city: 'New Delhi',
  state: 'Delhi',
  postal_code: '110016',
  country_code: 'IN',
  latitude: '28.5590000',
  longitude: '77.2070000',
  place_id: 'dev:green-park',
  is_default: true,
};

const WORK = { ...HOME, id: 'addr-work', type: 'WORK' as const, label: 'Work', formatted_address: 'Hauz Khas Village, New Delhi, Delhi 110016, IN', latitude: '28.5494000', longitude: '77.2001000', place_id: 'dev:hauz-khas', is_default: false };

const UNLOCATED = { ...HOME, id: 'addr-other', type: 'OTHER' as const, label: 'The lock-up', latitude: null, longitude: null, place_id: null, is_default: false };

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

interface Recorded { url: string; init: RequestInit }

/** Routes a stubbed fetch by path, and records every call for assertions. */
const stubApi = (over: { addresses?: unknown[]; onCreate?: (body: unknown) => unknown } = {}) => {
  const calls: Recorded[] = [];
  const mock = vi.fn(async (url: string, init: RequestInit = {}) => {
    calls.push({ url, init });
    if (url.includes('/customer/addresses')) return ok(over.addresses ?? [HOME, WORK]);
    if (url.includes('/places/search')) {
      return ok([{ place_id: 'dev:taj-mahal', primary_text: 'Taj Mahal', secondary_text: 'Agra, Uttar Pradesh' }]);
    }
    if (url.includes('/places/')) {
      return ok({
        place_id: 'dev:taj-mahal',
        display_name: 'Taj Mahal',
        formatted_address: 'Tajganj, Agra, Uttar Pradesh 282001',
        latitude: '27.1751000',
        longitude: '78.0421000',
        city: 'Agra',
        region: 'Uttar Pradesh',
        country_code: 'IN',
        postal_code: '282001',
      });
    }
    if (url.includes('/customer/trips')) {
      const body: unknown = JSON.parse(String(init.body ?? '{}'));
      const answer = over.onCreate?.(body);
      return answer ?? ok({ id: 'trip-uuid-1', status: 'ROUTE_PENDING', route_status: 'NOT_CALCULATED' });
    }
    throw new Error(`unstubbed ${url}`);
  });
  vi.stubGlobal('fetch', mock);
  return { mock, calls };
};

const renderPlanner = () => {
  window.sessionStorage.setItem('fotg.customer.session', JSON.stringify({ token: TOKEN }));
  return render(
    <SessionProvider>
      <MemoryRouter initialEntries={['/trips/plan']}>
        <Routes>
          <Route path="/trips/plan" element={<TripPlannerScreen />} />
          <Route path="/trips/:tripId" element={<p>Journey screen for handoff</p>} />
          <Route path="/login" element={<p>Sign in</p>} />
        </Routes>
      </MemoryRouter>
    </SessionProvider>,
  );
};

const openOrigin = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(await screen.findByRole('button', { name: /Starting point/ }));
  return screen.findByRole('dialog', { name: /starting point/i });
};

const openDestination = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(await screen.findByRole('button', { name: /Destination/ }));
  return screen.findByRole('dialog', { name: /destination/i });
};

beforeEach(() => window.sessionStorage.clear());
afterEach(() => vi.unstubAllGlobals());

describe('TripPlannerScreen', () => {
  it('will not plan a journey until both ends are chosen', async () => {
    stubApi();
    const user = userEvent.setup();
    renderPlanner();

    expect(await screen.findByRole('button', { name: /Plan journey/ })).toBeDisabled();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));

    // One end is not a journey.
    await waitFor(() => expect(screen.getByRole('button', { name: /Plan journey/ })).toBeDisabled());

    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Work/ }));

    await waitFor(() => expect(screen.getByRole('button', { name: /Plan journey/ })).toBeEnabled());
  });

  it('offers Home, Work and Other from the saved addresses', async () => {
    stubApi({ addresses: [HOME, WORK, { ...UNLOCATED, latitude: '26.9239000', longitude: '75.8267000' }] });
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    expect(within(origin).getByRole('button', { name: /^Home/ })).toBeInTheDocument();
    expect(within(origin).getByRole('button', { name: /^Work/ })).toBeInTheDocument();
    expect(within(origin).getByRole('button', { name: /lock-up/ })).toBeInTheDocument();
  });

  it('marks a saved address with no map location as unusable instead of letting it fail later', async () => {
    stubApi({ addresses: [HOME, UNLOCATED] });
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    expect(within(origin).getByText(/Needs a map location/)).toBeInTheDocument();
    // Not a button: it cannot be chosen, so it cannot produce a refusal two
    // screens later that the customer has no way to understand.
    expect(within(origin).queryByRole('button', { name: /lock-up/ })).not.toBeInTheDocument();
  });

  it('refuses the same place at both ends, and says which rule it broke', async () => {
    stubApi();
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Home/ }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/starting point and destination are the same/i);
    expect(screen.getByRole('button', { name: /Plan journey/ })).toBeDisabled();
  });

  it('submits a saved address as an identifier and nothing else', async () => {
    const { calls } = stubApi();
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Work/ }));
    await user.click(await screen.findByRole('button', { name: /Plan journey/ }));

    await screen.findByText('Journey screen for handoff');

    const create = calls.find((call) => call.init.method === 'POST');
    const body = JSON.parse(String(create?.init.body)) as Record<string, Record<string, unknown>>;

    expect(body.origin).toEqual({ source_type: 'SAVED_ADDRESS', saved_address_id: 'addr-home' });
    expect(body.destination).toEqual({ source_type: 'SAVED_ADDRESS', saved_address_id: 'addr-work' });
    // No customer id anywhere in the request: who this is comes from the token.
    expect(JSON.stringify(body)).not.toContain('customer_id');
  });

  it('resolves a searched place to real coordinates before submitting it', async () => {
    const { calls } = stubApi();
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));

    const destination = await openDestination(user);
    await user.type(within(destination).getByLabelText('Search for a place'), 'taj');
    await user.click(await within(destination).findByRole('option', { name: /Taj Mahal/ }));

    await user.click(await screen.findByRole('button', { name: /Plan journey/ }));
    await screen.findByText('Journey screen for handoff');

    const create = calls.find((call) => call.init.method === 'POST');
    const body = JSON.parse(String(create?.init.body)) as Record<string, Record<string, unknown>>;

    expect(body.destination).toMatchObject({
      source_type: 'PLACE_SEARCH',
      place_id: 'dev:taj-mahal',
      // From the details call, not from the suggestion, which carries no
      // position at all.
      latitude: 27.1751,
      longitude: 78.0421,
    });
    expect(calls.some((call) => call.url.includes('/places/dev%3Ataj-mahal'))).toBe(true);
  });

  it('sends one idempotency key and reuses it when a create fails', async () => {
    let attempts = 0;
    const { calls } = stubApi({
      onCreate: () => {
        attempts += 1;
        // The lost-response shape: the first attempt does not come back.
        return attempts === 1 ? fail(500, 'SERVER_ERROR', 'Something went wrong.') : undefined;
      },
    });
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Work/ }));

    const cta = await screen.findByRole('button', { name: /Plan journey/ });
    await user.click(cta);
    await screen.findByRole('alert');

    await user.click(screen.getByRole('button', { name: /Plan journey/ }));
    await screen.findByText('Journey screen for handoff');

    const keys = calls
      .filter((call) => call.init.method === 'POST')
      .map((call) => (call.init.headers as Record<string, string>)['Idempotency-Key']);

    expect(keys).toHaveLength(2);
    expect(keys[0]).toBeTruthy();
    // The same key, so the server answers the retry from the first attempt
    // instead of writing a second journey. A key minted per attempt would make
    // every retry a new trip, which is the bug this exists to prevent.
    expect(keys[1]).toBe(keys[0]);
  });

  it('hands only the trip id to the route screen', async () => {
    stubApi();
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Work/ }));
    await user.click(await screen.findByRole('button', { name: /Plan journey/ }));

    expect(await screen.findByText('Journey screen for handoff')).toBeInTheDocument();
  });

  it('still lets a customer search when their saved addresses fail to load', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url.includes('/customer/addresses')) return fail(500, 'SERVER_ERROR', 'Nope.');
        if (url.includes('/places/search')) {
          return ok([{ place_id: 'dev:taj-mahal', primary_text: 'Taj Mahal', secondary_text: 'Agra' }]);
        }
        throw new Error(`unstubbed ${url}`);
      }),
    );

    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    expect(within(origin).getByRole('alert')).toHaveTextContent(/could not load your saved places/i);
    // The planner is not dead: the other two ways to choose a place still work.
    expect(within(origin).getByLabelText('Search for a place')).toBeInTheDocument();
    expect(within(origin).getByRole('button', { name: /current location/i })).toBeInTheDocument();
  });

  it('never offers current location for the destination', async () => {
    stubApi();
    const user = userEvent.setup();
    renderPlanner();

    const destination = await openDestination(user);
    expect(within(destination).queryByRole('button', { name: /current location/i })).not.toBeInTheDocument();
  });

  it('swaps whole selections, not just the labels', async () => {
    const { calls } = stubApi();
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Work/ }));

    await user.click(screen.getByRole('button', { name: /Swap/ }));
    await user.click(await screen.findByRole('button', { name: /Plan journey/ }));
    await screen.findByText('Journey screen for handoff');

    const create = calls.find((call) => call.init.method === 'POST');
    const body = JSON.parse(String(create?.init.body)) as Record<string, Record<string, unknown>>;

    expect(body.origin).toEqual({ source_type: 'SAVED_ADDRESS', saved_address_id: 'addr-work' });
    expect(body.destination).toEqual({ source_type: 'SAVED_ADDRESS', saved_address_id: 'addr-home' });
  });

  it("shows the server's message for a code it recognises", async () => {
    stubApi({ onCreate: () => fail(422, 'SAME_LOCATION', 'Your starting point and destination are the same. Choose a different destination.') });
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.type(within(destination).getByLabelText('Search for a place'), 'taj');
    await user.click(await within(destination).findByRole('option', { name: /Taj Mahal/ }));
    await user.click(await screen.findByRole('button', { name: /Plan journey/ }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/starting point and destination are the same/i);
  });

  it('will not render a message for a code it has never read', async () => {
    // The other half of the allow-list. An unreviewed string from the server is
    // how internal detail — a stack frame, a provider's quota message, a table
    // name — ends up on a customer's screen.
    stubApi({
      onCreate: () =>
        fail(500, 'SOME_INTERNAL_CODE', 'SQLSTATE[23000]: Integrity constraint violation on trips.customer_id'),
    });
    const user = userEvent.setup();
    renderPlanner();

    const origin = await openOrigin(user);
    await user.click(within(origin).getByRole('button', { name: /^Home/ }));
    const destination = await openDestination(user);
    await user.click(within(destination).getByRole('button', { name: /^Work/ }));
    await user.click(await screen.findByRole('button', { name: /Plan journey/ }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Something went wrong. Please try again.');
    expect(alert).not.toHaveTextContent(/SQLSTATE/);
    expect(alert).not.toHaveTextContent(/customer_id/);
  });
});
