import { Navigate } from 'react-router-dom';
import type { ReactNode } from 'react';
import { useSession } from './SessionProvider.js';
import { AppLoading } from '../shell/AppLoading.js';

/**
 * The mirror of RequireSession, and it needs the same three states.
 *
 * Redirecting during 'restoring' would bounce a signed-out visitor off the
 * sign-in screen for a frame — the auth flash again, in the other direction.
 */
export const RedirectIfSignedIn = ({ children }: { children: ReactNode }) => {
  const { state } = useSession();

  if (state.status === 'restoring') return <AppLoading />;
  if (state.status === 'authenticated') return <Navigate to="/" replace />;

  return <>{children}</>;
};
