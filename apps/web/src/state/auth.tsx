import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { AuthResponse, LoginInput, PublicUser, RegisterInput } from '@fotg/contracts';
import { api, setAuthToken } from '../api/client.js';

const STORAGE_KEY = 'fotg.session';

interface StoredSession {
  token: string;
  expiresAt: string;
}

interface AuthState {
  user: PublicUser | null;
  status: 'loading' | 'ready';
  login: (input: LoginInput) => Promise<void>;
  register: (input: RegisterInput) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

const readStored = (): StoredSession | null => {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredSession;
    // An expired token is worse than none: it makes every call fail with a 401 that
    // looks like a bug. Drop it on the way in.
    if (!parsed.token || new Date(parsed.expiresAt).getTime() <= Date.now()) return null;
    return parsed;
  } catch {
    return null;
  }
};

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<PublicUser | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready'>('loading');

  useEffect(() => {
    const stored = readStored();
    if (!stored) {
      setStatus('ready');
      return;
    }

    setAuthToken(stored.token);
    // The token being well-formed is not proof the account still exists, so the
    // session is confirmed against the server before the UI trusts it.
    api
      .me()
      .then(setUser)
      .catch(() => {
        window.localStorage.removeItem(STORAGE_KEY);
        setAuthToken(null);
      })
      .finally(() => setStatus('ready'));
  }, []);

  const accept = useCallback((response: AuthResponse) => {
    setAuthToken(response.token);
    window.localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ token: response.token, expiresAt: response.expiresAt }),
    );
    setUser(response.user);
  }, []);

  const login = useCallback(async (input: LoginInput) => accept(await api.login(input)), [accept]);
  const register = useCallback(async (input: RegisterInput) => accept(await api.register(input)), [accept]);

  const logout = useCallback(() => {
    setAuthToken(null);
    window.localStorage.removeItem(STORAGE_KEY);
    setUser(null);
  }, []);

  const value = useMemo<AuthState>(
    () => ({ user, status, login, register, logout }),
    [user, status, login, register, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = (): AuthState => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside an AuthProvider.');
  return context;
};
