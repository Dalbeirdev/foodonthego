# 10 — Deployment

> Module 01 establishes the *requirements* for a deployment. No production infrastructure is
> provisioned, and no deployment has been performed.

## Build artefacts

| Component | Command | Output |
| --- | --- | --- |
| Backend | `composer install --no-dev -o` | The `backend/` tree |
| Restaurant | `npm run build -w @fotg/restaurant` | `web/apps/restaurant/dist/` |
| Admin | `npm run build -w @fotg/admin` | `web/apps/admin/dist/` |
| Android | `flutter build appbundle --release` | `.aab` |
| iOS | `flutter build ipa --release` | `.ipa` |

## Backend runtime requirements

- PHP 8.4 with `pdo_mysql`, `redis`, `mbstring`, `intl`, `zip`
- `php artisan config:cache route:cache view:cache` on deploy
- A queue worker (`php artisan queue:work`) as its own process
- A scheduler entry (`php artisan schedule:run` every minute)
- MySQL 8 and Redis 7 reachable

## Release checklist

1. `APP_ENV=production`, `APP_DEBUG=false`, real `APP_KEY`
2. `FRONTEND_URLS` lists exact HTTPS origins, no wildcard
3. Migrations applied (`php artisan migrate --force`)
4. Config cached
5. `/api/v1/health/ready` returns 200 **before** the instance joins the load balancer
6. Queue worker and scheduler running

Steps 1–2 are enforced: `ProductionConfigGuard` refuses to boot otherwise.

## Health probes

| Probe | Endpoint | On failure |
| --- | --- | --- |
| Liveness | `/api/v1/health/live` | Restart the container |
| Readiness | `/api/v1/health/ready` | Remove from the load balancer; do **not** restart |

Pointing both at the same endpoint turns a slow database into a restart loop.

## Zero-downtime notes

Migrations must be backwards compatible with the currently-running version — add a column, deploy,
backfill, then drop in a later release. A migration that renames or drops a column in the same
deploy as the code that stops using it will break every instance still serving the old version.

## Not yet built

Container images, an orchestration manifest, a CDN or object-storage strategy, log shipping, a
Sentry project, and a rollback procedure. Each belongs to the module or the infrastructure work that
needs it.
