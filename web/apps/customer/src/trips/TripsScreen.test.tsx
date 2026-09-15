import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { TripsScreen } from './TripsScreen.js';
import { SessionProvider } from '../session/SessionProvider.js';

/** The trips tab, and the journey screen Restart Module 06 will take over. */

const TOKEN = 'test-token-not-a-real-credential';

const trip = (over: Record<string, unknown> = {}) => ({
  id: 'trip-uuid-1',
  status: 'ROUTE_PENDING',
  route_status: 'NOT_CALCULATED',
  origin: { source_type: 'SAVED_ADDRESS', display_name: 'Home', formatted_address: 'Green Park, New Delhi', latitude: '28.5590000', longitude: '77.2070000', place_id: 'dev:green-park', city: 'New Delhi', region: 'Delhi', country_code: 'IN', postal_code: '110016' },
  destination: { source_type: 'PLACE_SEARCH', display_name: 'Jaipur International Airport', formatted_address: 'Sanganer, Jaipur, Rajasthan 302029', latitude: '26.8242000', longitude: '75.8122000', place_id: 'dev:jaipur-airport', city: 'Jaipur', region: 'Rajasthan', country_code: 'IN', postal_code: '302029' },
  created_at: '2026-09-15T08:00:00+00:00',
  cancelled_at: null,
  selected_route: null,
  ...over,
});

const stub = (data: unknown, ok = true, status = 200) =>
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok,
      status,
      headers: new Headers({ 'X-Request-Id': 'req-1' }),
      text: async () =>
        ok
          ? JSON.stringify({ data, meta: { request_id: 'req-1' } })
          : JSON.stringify({ error: { code: 'TRIP_NOT_FOUND', message: 'That journey does not exist.', request_id: 'req-1' } }),
    }),
  );

const renderAt = (path: string) => {
  window.sessionStorage.setItem('fotg.customer.session', JSON.stringify({ token: TOKEN }));
  return render(
    <SessionProvider>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/trips" element={<TripsScreen />} />
        </Routes>
      </MemoryRouter>
    </SessionProvider>,
  );
};

beforeEach(() => window.sessionStorage.clear());
afterEach(() => vi.unstubAllGlobals());

describe('TripsScreen', () => {
  it('lists a journey by both its ends', async () => {
    stub([trip()]);
    renderAt('/trips');

    expect(await screen.findByText(/Home/)).toBeInTheDocument();
    expect(screen.getByText(/Jaipur International Airport/)).toBeInTheDocument();
  });

  it('says the route is not calculated rather than showing a zero distance', async () => {
    stub([trip()]);
    renderAt('/trips');

    expect(await screen.findByText('Route not calculated yet')).toBeInTheDocument();
    // No distance, no time, no ETA: none of them exist yet, and a zero would
    // read as a route that came back empty.
    expect(screen.queryByText(/km/)).not.toBeInTheDocument();
    expect(screen.queryByText(/\bmin\b/)).not.toBeInTheDocument();
  });

  it('offers a way forward when there are no journeys', async () => {
    stub([]);
    renderAt('/trips');

    expect(await screen.findByText('No journeys yet')).toBeInTheDocument();

    // Two of them — the header and the empty state — and both must go to the
    // planner. A header link that quietly pointed somewhere else would be the
    // kind of thing nobody notices until a customer taps it.
    const links = screen.getAllByRole('link', { name: /Plan a journey/ });
    expect(links).toHaveLength(2);
    for (const link of links) expect(link).toHaveAttribute('href', '/trips/plan');
  });
});
