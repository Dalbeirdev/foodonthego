import { Route, Routes } from 'react-router-dom';
import { Info } from 'lucide-react';
import { AppShell, Card, ModulePlaceholder, type NavItem } from '@fotg/ui';
import { adminNavigation } from './navigation.js';
import { SystemHealth } from './SystemHealth.js';
import './pages.css';

/**
 * Development persona. Module 01 has no authentication (that is Module 02), so the
 * shell is rendered with a clearly-labelled test identity rather than a fake login.
 */
const DEV_USER = {
  name: 'FoodOnTheGo Platform Admin',
  email: 'admin@foodonthego.test',
  roleLabel: 'Super administrator',
};

const Overview = () => (
  <div className="page">
    <div className="welcome">
      <h1>Platform overview</h1>
      <p className="page__lede">
        FoodOnTheGo admin shell. Module 01 delivers the navigation architecture, the design system
        and the API foundation; operational screens arrive with their own modules.
      </p>
    </div>

    <div className="module-note">
      <Info size={20} aria-hidden="true" style={{ flex: 'none' }} />
      <span>
        <strong>Nothing on this screen is live data.</strong>
        No customers, restaurants, routes or orders exist yet — there are no such tables in the
        database. <em>System Health</em> is the only page here backed by a real API call.
      </span>
    </div>

    <Card>
      <h2 className="section-heading">Foundation in place</h2>
      <p className="page__lede">
        Laravel 12 on MySQL 8 and Redis 7, a versioned <code>/api/v1</code> contract with one error
        shape, correlation IDs threaded from request to log line, secrets redacted before they are
        written, per-actor rate limiting, idempotent retries for unsafe requests, and the seven
        platform roles declared and tested.
      </p>
    </Card>
  </div>
);

const placeholderFor = (item: NavItem) => (
  <ModulePlaceholder
    title={item.label}
    module={item.module}
    description={item.description}
    icon={<item.icon size={26} strokeWidth={1.8} />}
  />
);

export const App = () => (
  <AppShell productName="FoodOnTheGo" surfaceLabel="Admin" sections={adminNavigation} user={DEV_USER}>
    <Routes>
      <Route path="/" element={<Overview />} />
      <Route path="/system-health" element={<SystemHealth />} />
      {adminNavigation
        .flatMap((section) => section.items)
        .filter((item) => !item.implemented && item.path !== '/')
        .map((item) => (
          <Route key={item.path} path={item.path} element={<div className="page">{placeholderFor(item)}</div>} />
        ))}
      <Route
        path="*"
        element={
          <div className="page">
            <ModulePlaceholder
              title="Page not found"
              module="—"
              description="There is nothing at this address. Use the sidebar to get back to the overview."
            />
          </div>
        }
      />
    </Routes>
  </AppShell>
);
