import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  clearStoredSession,
  readStoredSession,
  writeStoredSession,
  type CustomerSession,
  type SessionState,
} from './session.js';

interface SessionContextValue {
  readonly state: SessionState;
  readonly signIn: (session: CustomerSession) => void;
  readonly signOut: () => void;
}

const SessionContext = createContext<SessionContextValue | null>(null);

export const SessionProvider = ({ children }: { children: ReactNode }) => {
  // Starts as 'restoring' and never skips it, even though reading
  // sessionStorage is synchronous. The one-tick delay is deliberate: it keeps
  // the state machine identical to the one a slower store (an http-only cookie
  // check, a refresh-token exchange) would need, so adding that later does not
  // reintroduce the flash this was written to prevent.
  const [state, setState] = useState<SessionState>({ status: 'restoring' });

  useEffect(() => {
    const stored = readStoredSession();
    setState(stored === null ? { status: 'anonymous' } : { status: 'authenticated', session: stored });
  }, []);

  const signIn = useCallback((session: CustomerSession) => {
    writeStoredSession(session);
    setState({ status: 'authenticated', session });
  }, []);

  const signOut = useCallback(() => {
    clearStoredSession();
    setState({ status: 'anonymous' });
  }, []);

  const value = useMemo<SessionContextValue>(() => ({ state, signIn, signOut }), [state, signIn, signOut]);

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
};

export const useSession = (): SessionContextValue => {
  const value = useContext(SessionContext);
  if (value === null) throw new Error('useSession was called outside a SessionProvider.');
  return value;
};
