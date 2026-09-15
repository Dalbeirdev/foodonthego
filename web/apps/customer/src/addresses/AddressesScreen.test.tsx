import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { AddressesScreen } from './AddressesScreen.js';
import { SessionProvider } from '../session/SessionProvider.js';

/**
 * Saved places.
 *
 * The property worth testing is that an address created here always has real
 * coordinates, because the planner's mandatory saved-address integration is
 * worthless if half the addresses cannot be used for a journey.
 */

const TOKEN = 'test-token-not-a-real-credential';

const ok = (data: unknown) => ({
  ok: true,
  status: 200,
  headers: new Headers({ 'X-Request-Id': 'req-1' }),
  text: async () => JSON.stringify({ data, meta: { request_id: 'req-1' } }),
});

interface Recorded { url: string; init: RequestInit }

const stubApi = (existing: unknown[] = []) => {
  const calls: Recorded[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init: RequestInit = {}) => {
      calls.push({ url, init });
      if (url.includes('/places/search')) {
        return ok([{ place_id: 'dev:green-park', primary_text: 'Green Park', secondary_text: 'New Delhi, Delhi' }]);
      }
      if (url.includes('/places/')) {
        return ok({
          place_id: 'dev:green-park',
          display_name: 'Green Park',
          formatted_address: 'Green Park, New Delhi, Delhi 110016',
          latitude: '28.5590000',
          longitude: '77.2070000',
          city: 'New Delhi',
          region: 'Delhi',
          country_code: 'IN',
          postal_code: '110016',
        });
      }
      if (url.includes('/customer/addresses')) {
        return init.method === 'POST' ? ok({ id: 'addr-new' }) : ok(existing);
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
      <MemoryRouter>
        <AddressesScreen />
      </MemoryRouter>
    </SessionProvider>,
  );
};

beforeEach(() => window.sessionStorage.clear());
afterEach(() => vi.unstubAllGlobals());

describe('AddressesScreen', () => {
  it('saves an address with the coordinates of the place that was chosen', async () => {
    const calls = stubApi();
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole('button', { name: 'Add a saved place' }));
    await user.type(screen.getByLabelText('Find the place'), 'green');
    await user.click(await screen.findByRole('button', { name: /Green Park/ }));
    await user.click(await screen.findByRole('button', { name: 'Save place' }));

    await waitFor(() => expect(calls.some((call) => call.init.method === 'POST')).toBe(true));
    const create = calls.find((call) => call.init.method === 'POST');
    const body = JSON.parse(String(create?.init.body)) as Record<string, unknown>;

    expect(body).toMatchObject({
      type: 'HOME',
      // The place's name, not the whole formatted address: the server composes
      // `formatted_address` from these parts, and sending the composed string
      // back as line 1 repeated every part of it.
      address_line_1: 'Green Park',
      city: 'New Delhi',
      state: 'Delhi',
      country_code: 'IN',
      latitude: 28.559,
      longitude: 77.207,
      place_id: 'dev:green-park',
    });
  });

  it('will not save until a real place has been picked', async () => {
    stubApi();
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole('button', { name: 'Add a saved place' }));

    // No coordinates yet, so nothing to save. This is what stops an address
    // being created that the trip planner would then have to refuse.
    expect(screen.getByRole('button', { name: 'Save place' })).toBeDisabled();
  });

  it('asks for a name when the place is neither home nor work', async () => {
    stubApi();
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole('button', { name: 'Add a saved place' }));
    await user.click(screen.getByRole('radio', { name: 'Other' }));
    await user.type(screen.getByLabelText('Find the place'), 'green');
    await user.click(await screen.findByRole('button', { name: /Green Park/ }));

    expect(screen.getByRole('button', { name: 'Save place' })).toBeDisabled();

    await user.type(screen.getByLabelText(/Name this place/), 'The gym');
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save place' })).toBeEnabled());
  });

  it('says so when nothing is saved yet', async () => {
    stubApi([]);
    renderScreen();

    expect(await screen.findByText('No saved places yet')).toBeInTheDocument();
  });
});
