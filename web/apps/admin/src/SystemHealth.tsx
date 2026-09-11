import { Activity, Database, RefreshCw, Server } from 'lucide-react';
import { Badge, Button, Card, Skeleton, StatTile, useApiHealth } from '@fotg/ui';

/**
 * The one screen in Module 01 that is not a placeholder.
 *
 * It calls the real Laravel endpoint `/api/v1/health/ready`, which itself runs a
 * `SELECT 1` against MySQL and a `PING` against Redis. If this renders green, the
 * whole chain — browser → Vite dev server → CORS → Laravel → MySQL/Redis — is
 * genuinely wired up. That is what makes it evidence rather than decoration.
 */
export const SystemHealth = () => {
  const { state, refresh } = useApiHealth(15_000);

  return (
    <div className="page">
      <header className="page__header">
        <div>
          <h1>System health</h1>
          <p className="page__lede">
            Live readiness of the FoodOnTheGo API and its dependencies. This page calls{' '}
            <code>GET /api/v1/health/ready</code> — it is not a mock.
          </p>
        </div>
        <Button variant="secondary" icon={<RefreshCw size={16} />} onClick={refresh}>
          Re-check
        </Button>
      </header>

      {state.status === 'checking' ? (
        <div className="grid-stats">
          <Skeleton height={104} />
          <Skeleton height={104} />
          <Skeleton height={104} />
        </div>
      ) : state.status === 'degraded' ? (
        <Card>
          <div className="health-error">
            <Badge tone="error">API unreachable</Badge>
            <p>{state.message}</p>
            <p className="page__lede">
              Start the API with <code>php artisan serve</code> from <code>backend/</code>, then re-check.
              {state.requestId ? (
                <>
                  {' '}
                  Request id <code>{state.requestId}</code>.
                </>
              ) : null}
            </p>
          </div>
        </Card>
      ) : (
        <>
          <div className="grid-stats">
            <StatTile
              label="API"
              value="Ready"
              hint={`environment: ${state.readiness.environment}`}
              icon={<Server size={18} />}
              tone="success"
            />
            <StatTile
              label="MySQL 8"
              value={state.readiness.checks.database.healthy ? 'Connected' : 'Down'}
              hint={
                state.readiness.checks.database.latency_ms !== undefined
                  ? `${state.readiness.checks.database.latency_ms} ms round trip`
                  : state.readiness.checks.database.error
              }
              icon={<Database size={18} />}
              tone={state.readiness.checks.database.healthy ? 'success' : 'error'}
            />
            <StatTile
              label="Redis 7"
              value={state.readiness.checks.redis.healthy ? 'Connected' : 'Down'}
              hint={
                state.readiness.checks.redis.latency_ms !== undefined
                  ? `${state.readiness.checks.redis.latency_ms} ms round trip`
                  : state.readiness.checks.redis.error
              }
              icon={<Activity size={18} />}
              tone={state.readiness.checks.redis.healthy ? 'success' : 'error'}
            />
          </div>

          <Card>
            <h2 className="section-heading">Correlation</h2>
            <p className="page__lede">
              Every API response carries an <code>X-Request-Id</code>, echoed in the body and written to
              the structured log for that request — so an error a user reports can be found in one search.
            </p>
            <p className="mono-block">{state.requestId}</p>
          </Card>
        </>
      )}
    </div>
  );
};
