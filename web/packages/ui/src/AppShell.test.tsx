import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { LayoutDashboard, Settings } from 'lucide-react';
import { AppShell } from './AppShell.js';
import type { NavSection } from './navigation.js';

// The shell polls the real health endpoint; the network is stubbed so these tests
// assert layout behaviour rather than connectivity (that is covered live).
beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    headers: new Headers({ 'X-Request-Id': 'test-request-id' }),
    text: async () =>
      JSON.stringify({
        data: {
          status: 'ready',
          environment: 'testing',
          checks: { database: { healthy: true, latency_ms: 1 }, redis: { healthy: true, latency_ms: 1 } },
        },
        meta: { request_id: 'test-request-id' },
      }),
  }));
  window.localStorage.clear();
});

const sections: NavSection[] = [
  { items: [{ label: 'Overview', path: '/', icon: LayoutDashboard, module: 'M01', description: 'x' }] },
  {
    title: 'Account',
    items: [{ label: 'Settings', path: '/settings', icon: Settings, module: 'M03', description: 'y' }],
  },
];

const user = { name: 'Priya Verma', email: 'priya@example.test', roleLabel: 'Restaurant owner' };

const renderShell = (initialPath = '/') =>
  render(
    <MemoryRouter initialEntries={[initialPath]}>
      <AppShell productName="FoodOnTheGo" surfaceLabel="Restaurant" sections={sections} user={user}>
        <p>Page body</p>
      </AppShell>
    </MemoryRouter>,
  );

describe('AppShell', () => {
  it('renders the navigation and the page body', () => {
    renderShell();

    expect(screen.getByRole('link', { name: /Overview/ })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Settings/ })).toBeInTheDocument();
    expect(screen.getByText('Page body')).toBeInTheDocument();
  });

  it('groups navigation under its section heading', () => {
    renderShell();
    expect(screen.getByText('Account')).toBeInTheDocument();
  });

  it('marks the current route active, and only that one', () => {
    const { container } = renderShell('/settings');

    const active = container.querySelectorAll('.fotg-nav__link.is-active');
    expect(active).toHaveLength(1);
    expect(active[0]).toHaveTextContent('Settings');
  });

  it('shows a breadcrumb trail ending in the current page', () => {
    renderShell('/settings');

    const crumbs = screen.getByRole('navigation', { name: 'Breadcrumb' });
    expect(within(crumbs).getByText('Overview')).toBeInTheDocument();
    expect(within(crumbs).getByText('Settings')).toHaveAttribute('aria-current', 'page');
  });

  it('collapses and expands the sidebar, and remembers the choice', async () => {
    const actor = userEvent.setup();
    const { container } = renderShell();

    await actor.click(screen.getByRole('button', { name: 'Collapse sidebar' }));
    expect(container.querySelector('.fotg-shell--collapsed')).not.toBeNull();
    expect(window.localStorage.getItem('fotg.sidebar.collapsed')).toBe('true');

    await actor.click(screen.getByRole('button', { name: 'Expand sidebar' }));
    expect(container.querySelector('.fotg-shell--collapsed')).toBeNull();
  });

  it('opens the account menu and closes it on Escape', async () => {
    const actor = userEvent.setup();
    renderShell();

    const trigger = screen.getByRole('button', { name: /Priya Verma/ });
    expect(trigger).toHaveAttribute('aria-expanded', 'false');

    await actor.click(trigger);
    expect(screen.getByRole('menu')).toBeInTheDocument();
    expect(trigger).toHaveAttribute('aria-expanded', 'true');

    await actor.keyboard('{Escape}');
    // The menu fades out, so it lingers in the DOM for the duration of the exit
    // animation; assert it is eventually gone rather than gone synchronously.
    await waitFor(() => expect(screen.queryByRole('menu')).not.toBeInTheDocument());
  });

  it('offers a skip link so a keyboard user can bypass the sidebar', () => {
    renderShell();
    expect(screen.getByRole('link', { name: 'Skip to content' })).toHaveAttribute('href', '#fotg-main');
  });

  it('labels the sidebar so a screen reader can identify it', () => {
    renderShell();
    expect(screen.getByRole('navigation', { name: 'Restaurant navigation' })).toBeInTheDocument();
  });

  it('marks unimplemented routes rather than implying they work', () => {
    renderShell();
    // Both fixture routes are scaffolding, so both carry the marker.
    expect(screen.getAllByLabelText('Not built yet')).toHaveLength(2);
  });

  it('reports live API health once the check resolves', async () => {
    renderShell();
    expect(await screen.findByText('API testing')).toBeInTheDocument();
  });

  it('survives localStorage being unavailable', () => {
    const getItem = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError: storage disabled');
    });

    // A private-mode browser throws rather than returning null; the shell must
    // still render instead of taking the whole app down.
    expect(() => renderShell()).not.toThrow();
    getItem.mockRestore();
  });
});
