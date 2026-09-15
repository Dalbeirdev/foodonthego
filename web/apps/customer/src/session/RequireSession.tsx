import { Navigate, useLocation } from 'react-router-dom';
import type { ReactNode } from 'react';
import { useSession } from './SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';

/**
 * The guard every private route sits behind.
 *
 * Route-level, not navigation-level: hiding a link from the menu is not
 * protection, because a URL can be typed. Every one of Home, Trips, Orders,
 * Notifications and Profile is wrapped in this.
 *
 * While the session is restoring it renders a loading screen rather than
 * redirecting. Redirecting during 'restoring' is the auth flash: a returning
 * customer sees the sign-in screen for a frame and is then bounced to Home.
 */
export const RequireSession = ({ children }: { children: ReactNode }) => {
  const { state } = useSession();
  const location = useLocation();

  if (state.status === 'restoring') return <AppLoading />;

  if (state.status === 'anonymous') {
    // Where they were going is carried across, so signing in returns them
    // there rather than dumping everyone on Home. Only the path is kept — an
    // absolute URL here would be an open-redirect.
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />;
  }

  return <>{children}</>;
};
