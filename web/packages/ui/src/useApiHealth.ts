import { useCallback, useEffect, useState } from 'react';
import { ApiError, apiRequest } from './apiClient.js';

export interface ReadinessCheck {
  healthy: boolean;
  latency_ms?: number;
  error?: string;
}

export interface Readiness {
  status: string;
  environment: string;
  checks: { database: ReadinessCheck; redis: ReadinessCheck };
}

export type HealthState =
  | { status: 'checking' }
  | { status: 'healthy'; readiness: Readiness; requestId: string }
  | { status: 'degraded'; message: string; requestId: string | null };

/**
 * Calls the real `/api/v1/health/ready` endpoint. This is the one live API call in
 * Module 01, and it exists so the shells prove end-to-end connectivity to Laravel,
 * MySQL and Redis rather than only claiming it. Nothing here is mocked.
 */
export const useApiHealth = (pollMs = 30_000): { state: HealthState; refresh: () => void } => {
  const [state, setState] = useState<HealthState>({ status: 'checking' });
  const [nonce, setNonce] = useState(0);

  const refresh = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    const controller = new AbortController();

    const check = async (): Promise<void> => {
      try {
        const response = await apiRequest<Readiness>('/api/v1/health/ready', { signal: controller.signal });
        setState({ status: 'healthy', readiness: response.data, requestId: response.meta.request_id });
      } catch (caught) {
        if ((caught as Error).name === 'AbortError') return;
        const error = caught instanceof ApiError ? caught : null;
        setState({
          status: 'degraded',
          message: error?.message ?? 'The API is unreachable.',
          requestId: error?.requestId ?? null,
        });
      }
    };

    void check();
    const timer = window.setInterval(() => void check(), pollMs);

    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [pollMs, nonce]);

  return { state, refresh };
};
