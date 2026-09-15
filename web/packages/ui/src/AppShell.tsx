import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { NavLink, Link, useLocation } from 'react-router-dom';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import {
  Bell,
  ChevronDown,
  Menu as MenuIcon,
  PanelLeftClose,
  PanelLeftOpen,
  Search,
  X,
} from 'lucide-react';
import type { NavSection } from './navigation.js';
import { useApiHealth } from './useApiHealth.js';
import './AppShell.css';

const STORAGE_KEY = 'fotg.sidebar.collapsed';

export interface ShellUser {
  name: string;
  email: string;
  roleLabel: string;
}

export interface AppShellProps {
  productName: string;
  surfaceLabel: string;
  sections: NavSection[];
  user: ShellUser;
  children: ReactNode;
}

/** Breadcrumbs derived from the route, matched against the nav so labels are real. */
const useBreadcrumbs = (sections: NavSection[]): Array<{ label: string; path: string }> => {
  const { pathname } = useLocation();

  return useMemo(() => {
    const all = sections.flatMap((section) => section.items);
    const match = all.find((item) => item.path === pathname);
    const home = all[0];

    if (!home) return [];
    if (!match || match.path === home.path) return [{ label: home.label, path: home.path }];

    return [
      { label: home.label, path: home.path },
      { label: match.label, path: match.path },
    ];
  }, [pathname, sections]);
};

const ApiHealthPill = () => {
  const { state } = useApiHealth();

  const tone = state.status === 'healthy' ? 'success' : state.status === 'checking' ? 'neutral' : 'error';
  const label =
    state.status === 'healthy'
      ? `API ${state.readiness.environment}`
      : state.status === 'checking'
        ? 'Checking API…'
        : 'API unreachable';

  const title =
    state.status === 'healthy'
      ? `MySQL ${state.readiness.checks.database.latency_ms ?? '?'}ms · Redis ${state.readiness.checks.redis.latency_ms ?? '?'}ms · request ${state.requestId}`
      : state.status === 'degraded'
        ? `${state.message}${state.requestId ? ` (request ${state.requestId})` : ''}`
        : 'Contacting /api/v1/health/ready';

  return (
    <span className={`fotg-health fotg-health--${tone}`} title={title} role="status">
      <span className="fotg-health__dot" aria-hidden="true" />
      {/* Wrapped in an element, not left as a bare text node: the narrow-viewport
          rule that collapses this pill to a dot is a child selector, and CSS cannot
          target a text node. Left unwrapped the rule silently does nothing. */}
      <span className="fotg-health__label">{label}</span>
    </span>
  );
};

export const AppShell = ({ productName, surfaceLabel, sections, user, children }: AppShellProps) => {
  const location = useLocation();
  const reduceMotion = useReducedMotion();
  const breadcrumbs = useBreadcrumbs(sections);

  // Persisted so the choice survives a reload; wrapped because storage throws in
  // private-mode browsers rather than returning null.
  const [collapsed, setCollapsed] = useState<boolean>(() => {
    try {
      return window.localStorage.getItem(STORAGE_KEY) === 'true';
    } catch {
      return false;
    }
  });
  const [mobileOpen, setMobileOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, String(collapsed));
    } catch {
      /* storage unavailable — the toggle still works for this session */
    }
  }, [collapsed]);

  // Navigating on mobile must close the drawer, or the destination is hidden
  // behind the menu the user just used.
  useEffect(() => {
    setMobileOpen(false);
    setMenuOpen(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!menuOpen) return;

    const onPointerDown = (event: MouseEvent): void => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) setMenuOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') setMenuOpen(false);
    };

    document.addEventListener('mousedown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('mousedown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [menuOpen]);

  const initials = user.name
    .split(' ')
    .map((part) => part[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase();

  return (
    <div className={`fotg-shell ${collapsed ? 'fotg-shell--collapsed' : ''}`}>
      <a className="fotg-skip-link" href="#fotg-main">
        Skip to content
      </a>

      {/* Scrim closes the drawer; it is inert to screen readers because the same
          action is available from the labelled close button inside the drawer. */}
      <AnimatePresence>
        {mobileOpen ? (
          <motion.div
            className="fotg-scrim"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: reduceMotion ? 0 : 0.16 }}
            onClick={() => setMobileOpen(false)}
            aria-hidden="true"
          />
        ) : null}
      </AnimatePresence>

      {/* The label belongs on the <nav> below, not here: <aside> has an implicit
          role of `complementary`, so labelling it does not name the navigation
          landmark a screen-reader user actually jumps to. */}
      <aside className={`fotg-sidebar ${mobileOpen ? 'fotg-sidebar--open' : ''}`}>
        <div className="fotg-sidebar__brand">
          <Link to={sections[0]?.items[0]?.path ?? '/'} className="fotg-brand">
            <span className="fotg-brand__mark" aria-hidden="true">
              F
            </span>
            <span className="fotg-brand__text">
              <span className="fotg-brand__name">{productName}</span>
              <span className="fotg-brand__surface">{surfaceLabel}</span>
            </span>
          </Link>
          <button
            type="button"
            className="fotg-icon-button fotg-sidebar__close"
            onClick={() => setMobileOpen(false)}
            aria-label="Close navigation"
          >
            <X size={20} aria-hidden="true" />
          </button>
        </div>

        <nav className="fotg-nav" aria-label={`${surfaceLabel} navigation`}>
          {sections.map((section, index) => (
            <div className="fotg-nav__section" key={section.title ?? `section-${index}`}>
              {section.title ? <p className="fotg-nav__title">{section.title}</p> : null}
              <ul className="fotg-nav__list">
                {section.items.map((item) => (
                  <li key={item.path}>
                    <NavLink
                      to={item.path}
                      end={item.path === sections[0]?.items[0]?.path}
                      className={({ isActive }) => `fotg-nav__link ${isActive ? 'is-active' : ''}`}
                      title={collapsed ? item.label : undefined}
                    >
                      <span className="fotg-nav__icon" aria-hidden="true">
                        <item.icon size={19} strokeWidth={1.9} />
                      </span>
                      <span className="fotg-nav__label">{item.label}</span>
                      {!item.implemented ? (
                        <span className="fotg-nav__pending" aria-label="Not built yet" title="Not built yet" />
                      ) : null}
                    </NavLink>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </nav>

        <div className="fotg-sidebar__footer">
          <button
            type="button"
            className="fotg-icon-button fotg-sidebar__collapse"
            onClick={() => setCollapsed((value) => !value)}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            aria-pressed={collapsed}
          >
            {collapsed ? <PanelLeftOpen size={20} aria-hidden="true" /> : <PanelLeftClose size={20} aria-hidden="true" />}
            <span className="fotg-nav__label">Collapse</span>
          </button>
        </div>
      </aside>

      <div className="fotg-main-column">
        <header className="fotg-topbar">
          <button
            type="button"
            className="fotg-icon-button fotg-topbar__menu"
            onClick={() => setMobileOpen(true)}
            aria-label="Open navigation"
            aria-expanded={mobileOpen}
          >
            <MenuIcon size={22} aria-hidden="true" />
          </button>

          <nav className="fotg-breadcrumbs" aria-label="Breadcrumb">
            <ol>
              {breadcrumbs.map((crumb, index) => (
                <li key={crumb.path}>
                  {index < breadcrumbs.length - 1 ? (
                    <Link to={crumb.path}>{crumb.label}</Link>
                  ) : (
                    <span aria-current="page">{crumb.label}</span>
                  )}
                </li>
              ))}
            </ol>
          </nav>

          <div className="fotg-topbar__search">
            <Search size={17} aria-hidden="true" />
            <input
              type="search"
              placeholder="Search…"
              aria-label="Search (available from Module 21)"
              disabled
              title="Search arrives with its own module"
            />
          </div>

          <div className="fotg-topbar__actions">
            <ApiHealthPill />

            <button type="button" className="fotg-icon-button" aria-label="Notifications (none yet)" disabled>
              <Bell size={20} aria-hidden="true" />
            </button>

            <div className="fotg-account" ref={menuRef}>
              <button
                type="button"
                className="fotg-account__trigger"
                onClick={() => setMenuOpen((open) => !open)}
                aria-expanded={menuOpen}
                aria-haspopup="menu"
              >
                <span className="fotg-avatar" aria-hidden="true">
                  {initials}
                </span>
                <span className="fotg-account__text">
                  <span className="fotg-account__name">{user.name}</span>
                  <span className="fotg-account__role">{user.roleLabel}</span>
                </span>
                <ChevronDown size={16} aria-hidden="true" />
              </button>

              <AnimatePresence>
                {menuOpen ? (
                  <motion.div
                    className="fotg-account__menu"
                    role="menu"
                    initial={{ opacity: 0, y: -4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -4 }}
                    transition={{ duration: reduceMotion ? 0 : 0.14 }}
                  >
                    <p className="fotg-account__menu-header">
                      <strong>{user.name}</strong>
                      <span>{user.email}</span>
                    </p>
                    <button type="button" role="menuitem" disabled>
                      Profile — Module 02
                    </button>
                    <button type="button" role="menuitem" disabled>
                      Sign out — Module 02
                    </button>
                  </motion.div>
                ) : null}
              </AnimatePresence>
            </div>
          </div>
        </header>

        <main id="fotg-main" className="fotg-content" tabIndex={-1}>
          <motion.div
            key={location.pathname}
            initial={{ opacity: 0, y: reduceMotion ? 0 : 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: reduceMotion ? 0 : 0.18, ease: [0.2, 0, 0, 1] }}
          >
            {children}
          </motion.div>
        </main>
      </div>
    </div>
  );
};
