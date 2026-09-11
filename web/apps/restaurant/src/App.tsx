import { Route, Routes } from 'react-router-dom';
import { Info } from 'lucide-react';
import { AppShell, Card, ModulePlaceholder, type NavItem } from '@fotg/ui';
import { restaurantNavigation } from './navigation.js';
import './pages.css';

/**
 * Development persona. Module 01 has no authentication (that is Module 02), so the
 * shell is rendered with a clearly-labelled test identity rather than a fake login.
 */
const DEV_USER = {
  name: 'Priya Verma',
  email: 'priya.verma@highwayspice.test',
  roleLabel: 'Restaurant owner · Highway Spice Kitchen',
};

const Overview = () => (
  <div className="page">
    <div className="welcome">
      <h1>Good evening, Priya</h1>
      <p className="page__lede">
        This is the Highway Spice Kitchen dashboard shell. Module 01 delivers the navigation
        architecture, design system and API foundation — the operational screens arrive with their
        own modules.
      </p>
    </div>

    <div className="module-note">
      <Info size={20} aria-hidden="true" style={{ flex: 'none' }} />
      <span>
        <strong>Nothing on this screen is live data.</strong>
        No orders, menu items or earnings exist yet — there are no such tables in the database. Every
        link in the sidebar marked with a dot is navigation scaffolding.
      </span>
    </div>

    <Card>
      <h2 className="section-heading">What Module 01 established</h2>
      <p className="page__lede">
        A Laravel 12 API on MySQL 8 and Redis 7 with a versioned <code>/api/v1</code> contract,
        correlation IDs on every request, structured logs with secrets redacted, rate limiting,
        idempotent retries, and seven roles ready to authorise against. The Admin panel&rsquo;s{' '}
        <em>System Health</em> page proves the connection end to end.
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
  <AppShell
    productName="FoodOnTheGo"
    surfaceLabel="Restaurant"
    sections={restaurantNavigation}
    user={DEV_USER}
  >
    <Routes>
      <Route path="/" element={<Overview />} />
      {restaurantNavigation
        .flatMap((section) => section.items)
        .filter((item) => item.path !== '/')
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
              description="There is nothing at this address. Use the sidebar to get back to the dashboard."
            />
          </div>
        }
      />
    </Routes>
  </AppShell>
);
