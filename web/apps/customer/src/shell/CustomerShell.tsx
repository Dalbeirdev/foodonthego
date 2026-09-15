import { NavLink, Outlet } from 'react-router-dom';
import { customerDestinations } from './navigation.js';
import './shell.css';

/**
 * The frame every signed-in screen renders inside.
 *
 * One component, two navigations, chosen by CSS rather than by JavaScript
 * measuring the window: both are in the DOM and the media query decides which
 * is displayed. That means no layout flash on first paint, no resize listener,
 * and the same markup in a server render if one is ever added.
 *
 * Below 900px the rail is hidden and the bottom bar shown; above it, the
 * reverse. 900 rather than 768 because the rail needs room to sit beside a
 * content column without squeezing it — a tablet in portrait is still a phone
 * layout as far as this shell is concerned.
 */
export const CustomerShell = () => (
  <div className="shell">
    <a className="shell__skip" href="#main">
      Skip to content
    </a>

    <nav className="shell__rail" aria-label="Primary">
      <div className="shell__brand">
        <span className="shell__mark" aria-hidden="true">
          F
        </span>
        <span className="shell__wordmark">FoodOnTheGo</span>
      </div>

      <ul className="shell__rail-list">
        {customerDestinations.map(({ label, path, icon: Icon }) => (
          <li key={path}>
            <NavLink
              to={path}
              end={path === '/'}
              className={({ isActive }) => `shell__rail-link${isActive ? ' is-active' : ''}`}
            >
              {/* aria-current is what a screen reader announces as "current
                  page". The orange text and the bar to its left are for
                  everyone else — three signals, never colour alone. */}
              <Icon size={20} strokeWidth={1.9} aria-hidden="true" />
              <span>{label}</span>
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>

    <main className="shell__main" id="main">
      <Outlet />
    </main>

    <nav className="shell__bottom" aria-label="Primary">
      <ul className="shell__bottom-list">
        {customerDestinations.map(({ label, path, icon: Icon }) => (
          <li key={path}>
            <NavLink
              to={path}
              end={path === '/'}
              className={({ isActive }) => `shell__bottom-link${isActive ? ' is-active' : ''}`}
            >
              <Icon size={22} strokeWidth={1.9} aria-hidden="true" />
              <span>{label}</span>
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  </div>
);
