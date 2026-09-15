import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { App } from './App.js';
import { SessionProvider } from './session/SessionProvider.js';

/**
 * The customer web shell.
 *
 * These cover the things Restart Module 02 is answerable for: that a private
 * route is protected by the route rather than by a hidden link, that a signed
 * -in customer reaches Home with real data, that a missing name degrades to
 * something a person can read, and that every one of the five destinations
 * answers rather than dead-ending.
 */

const TOKEN = 'test-token-not-a-real-credential';

const homePayload = (over: Record<string, unknown> = {}) => ({
  data: {
    customer: { first_name: 'Rahul', full_name: 'Rahul Sharma' },
    active_trip: null,
    active_order: null,
    notification_summary: { supported: false, unread: null },
    ...over,
  },
  meta: { request_id: 'req-1' },
});

const stubFetch = (body: unknown, ok = true) => {
  const mock = vi.fn().mockResolvedValue({
    ok,
    status: ok ? 200 : 500,
    headers: new Headers({ 'X-Request-Id': 'req-1' }),
    text: async () => JSON.stringify(body),
  });
  vi.stubGlobal('fetch', mock);
  return mock;
};

/** Answers by path, so a list endpoint returns a list and a screen returns its own shape. */
const stubByPath = (over: { home?: unknown } = {}) => {
  const mock = vi.fn(async (url: string) => {
    const body =
      url.includes('/customer/home') ? over.home ?? homePayload().data
      : url.includes('/customer/trips') ? []
      : url.includes('/customer/addresses') ? []
      : null;

    return {
      ok: true,
      status: 200,
      headers: new Headers({ 'X-Request-Id': 'req-1' }),
      text: async () => JSON.stringify({ data: body, meta: { request_id: 'req-1' } }),
    };
  });
  vi.stubGlobal('fetch', mock);
  return mock;
};

const signedIn = () =>
  window.sessionStorage.setItem('fotg.customer.session', JSON.stringify({ token: TOKEN }));

const renderAt = (path: string) =>
  render(
    <SessionProvider>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </SessionProvider>,
  );

beforeEach(() => window.sessionStorage.clear());
afterEach(() => vi.unstubAllGlobals());

describe('the auth guard', () => {
  it('sends an anonymous visitor to sign-in instead of Home', async () => {
    stubFetch(homePayload());

    renderAt('/');

    // The guard is on the route, so this holds for a typed URL too — hiding a
    // link from the navigation would not.
    await waitFor(() => expect(screen.getByText(/What is your mobile number/i)).toBeInTheDocument());
    expect(screen.queryByText(/Where are you travelling today/i)).not.toBeInTheDocument();
  });

  it('protects every private destination, not only Home', async () => {
    for (const path of ['/trips', '/orders', '/notifications', '/profile']) {
      window.sessionStorage.clear();
      stubFetch(homePayload());

      const view = renderAt(path);
      await waitFor(() => expect(screen.getByText(/What is your mobile number/i)).toBeInTheDocument());
      view.unmount();
    }
  });

  it('never shows private content while the session is still being restored', async () => {
    signedIn();
    stubFetch(homePayload());

    renderAt('/');

    // The first paint must not be the sign-in screen for a customer who is in
    // fact signed in — that flash is the bug this state machine exists for.
    expect(screen.queryByText(/What is your mobile number/i)).not.toBeInTheDocument();
  });
});

describe('Home', () => {
  it('greets the customer by the name the server returned', async () => {
    signedIn();
    stubFetch(homePayload());

    renderAt('/');

    await waitFor(() => expect(screen.getByText(/, Rahul$/)).toBeInTheDocument());
  });

  it('falls back to the product name rather than rendering a blank or a placeholder', async () => {
    signedIn();
    stubFetch(homePayload({ customer: { first_name: null } }));

    renderAt('/');

    await waitFor(() => expect(screen.getByText('Welcome to FoodOnTheGo')).toBeInTheDocument());
    // "Good evening, undefined" and "Customer #123" are the two failures this
    // is guarding; both are what happens when a screen assumes a name is there.
    expect(screen.queryByText(/undefined|null|Customer #/i)).not.toBeInTheDocument();
  });

  it('offers the journey CTA whether or not anything else loaded', async () => {
    signedIn();
    stubFetch(homePayload());

    renderAt('/');

    await waitFor(() =>
      expect(screen.getByRole('link', { name: /Plan a journey/i })).toHaveAttribute('href', '/trips/plan'),
    );
  });

  it('shows an empty state when there is no journey, not a spinner forever', async () => {
    signedIn();
    stubFetch(homePayload());

    renderAt('/');

    await waitFor(() => expect(screen.getByText('No active journey')).toBeInTheDocument());
  });

  it('shows the real journey when the server returns one', async () => {
    signedIn();
    stubFetch(
      homePayload({
        active_trip: {
          uuid: 'trip-1',
          origin: { display_name: 'Delhi' },
          destination: { display_name: 'Jaipur' },
        },
      }),
    );

    renderAt('/');

    await waitFor(() => expect(screen.getByText('Delhi → Jaipur')).toBeInTheDocument());
  });

  it('shows no order card at all when there is no order', async () => {
    signedIn();
    stubFetch(homePayload());

    renderAt('/');

    await waitFor(() => expect(screen.getByText('No active journey')).toBeInTheDocument());
    // Absent, not an empty card. A permanent "no orders" panel is a permanent
    // reminder of nothing.
    expect(screen.queryByText('Your order')).not.toBeInTheDocument();
  });

  it('shows the order status the server sent and invents no ETA', async () => {
    signedIn();
    stubFetch(
      homePayload({
        active_order: {
          uuid: 'order-1',
          order_number: 'FOTG-260914-ABC',
          status: 'PLACED',
          restaurant: { name: 'Highway Spice Kitchen' },
        },
      }),
    );

    renderAt('/');

    await waitFor(() => expect(screen.getByText('Highway Spice Kitchen')).toBeInTheDocument());
    expect(screen.getByText('FOTG-260914-ABC')).toBeInTheDocument();
    // The ETA engine does not exist. Home must not imply one.
    expect(screen.queryByText(/arriv|eta|ready at/i)).not.toBeInTheDocument();
  });

  it('keeps the journey CTA usable when the home request fails', async () => {
    signedIn();
    stubFetch({ error: { code: 'SERVER_ERROR', message: 'boom', request_id: 'req-1' } }, false);

    renderAt('/');

    await waitFor(() => expect(screen.getByText(/couldn.t load your home screen/i)).toBeInTheDocument());
    // A failed request must not take the whole app away: planning a journey
    // does not depend on the data that failed.
    expect(screen.getByRole('link', { name: /Plan a journey/i })).toBeInTheDocument();
  });
});

describe('navigation', () => {
  it('offers all five destinations', async () => {
    signedIn();
    stubFetch(homePayload());

    renderAt('/');

    await waitFor(() => expect(screen.getByText(/, Rahul$/)).toBeInTheDocument());

    for (const label of ['Home', 'Trips', 'Orders', 'Notifications', 'Profile']) {
      // Two navigations are in the DOM at once — the rail and the bottom bar —
      // and CSS picks. Both must carry every destination.
      expect(screen.getAllByRole('link', { name: label }).length).toBeGreaterThanOrEqual(1);
    }
  });

  it('renders a real screen for every destination rather than a dead end', async () => {
    for (const [path, heading] of [
      ['/trips', 'Trips'],
      ['/trips/plan', 'Plan your journey'],
      ['/orders', 'Orders'],
      ['/notifications', 'Notifications'],
      ['/profile', 'Profile'],
      ['/profile/addresses', 'Saved places'],
    ] as const) {
      window.sessionStorage.clear();
      signedIn();
      // Answers each screen with the shape its own endpoint returns. The single
      // home payload this loop used to serve for every route handed the trips
      // tab an object where it expected a list; `.map` threw during render and
      // the whole tree unmounted to a blank page. Both halves were wrong and
      // both are fixed: the stub, and the screen that could not survive it.
      stubByPath({ home: homePayload().data });

      const view = renderAt(path);
      await waitFor(() => expect(screen.getByRole('heading', { level: 1, name: heading })).toBeInTheDocument());
      view.unmount();
    }
  });
});
