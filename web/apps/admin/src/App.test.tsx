import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { adminNavigation } from './navigation.js';
import { SystemHealth } from './SystemHealth.js';

const stubHealth = (healthy = true) => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: healthy,
    status: healthy ? 200 : 503,
    headers: new Headers({ 'X-Request-Id': 'req-test' }),
    text: async () =>
      healthy
        ? JSON.stringify({
            data: {
              status: 'ready',
              environment: 'testing',
              checks: { database: { healthy: true, latency_ms: 2.1 }, redis: { healthy: true, latency_ms: 0.4 } },
            },
            meta: { request_id: 'req-test' },
          })
        : JSON.stringify({
            error: { code: 'DEPENDENCY_UNAVAILABLE', message: 'One or more dependencies are unavailable.', request_id: 'req-test' },
          }),
  }));
};

beforeEach(() => vi.unstubAllGlobals());

describe('admin navigation architecture', () => {
  it('covers every area the module specification requires', () => {
    const labels = adminNavigation.flatMap((s) => s.items).map((i) => i.label);

    for (const required of [
      'Overview', 'Customers', 'Restaurants', 'Routes', 'Orders', 'Payments',
      'Reviews', 'Promotions', 'Support', 'Analytics', 'Administration',
      'Settings', 'Audit Logs',
    ]) {
      expect(labels).toContain(required);
    }
  });

  it('gives every route a unique path', () => {
    const paths = adminNavigation.flatMap((s) => s.items).map((i) => i.path);
    expect(new Set(paths).size).toBe(paths.length);
  });

  it('names the delivering module for every scaffolded route', () => {
    for (const item of adminNavigation.flatMap((s) => s.items)) {
      expect(item.module, `${item.label} has no module`).toMatch(/Module \d+|—/);
      expect(item.description.length).toBeGreaterThan(20);
    }
  });

  it('marks only System Health as implemented, because only it has a backend', () => {
    const implemented = adminNavigation.flatMap((s) => s.items).filter((i) => i.implemented);
    expect(implemented.map((i) => i.label)).toEqual(['System Health']);
  });
});

describe('SystemHealth', () => {
  const renderPage = () =>
    render(
      <MemoryRouter initialEntries={['/system-health']}>
        <Routes>
          <Route path="/system-health" element={<SystemHealth />} />
        </Routes>
      </MemoryRouter>,
    );

  it('reports MySQL and Redis when the API is ready', async () => {
    stubHealth(true);
    renderPage();

    expect(await screen.findByText('MySQL 8')).toBeInTheDocument();
    expect(await screen.findByText('Redis 7')).toBeInTheDocument();
    expect(screen.getAllByText('Connected')).toHaveLength(2);
    expect(screen.getByText('2.1 ms round trip')).toBeInTheDocument();
  });

  it('shows an actionable message when the API is unreachable', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    renderPage();

    expect(await screen.findByText('API unreachable')).toBeInTheDocument();
    // It must tell the developer what to actually do, not just that it failed.
    expect(screen.getByText(/php artisan serve/)).toBeInTheDocument();
  });

  it('surfaces the request id so a failure can be traced to a log line', async () => {
    stubHealth(true);
    renderPage();

    expect(await screen.findByText('req-test')).toBeInTheDocument();
  });
});
