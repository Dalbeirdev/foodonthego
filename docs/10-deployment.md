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

---

## Module 10 — two migrations, no new service

```
2026_09_10_010000_create_menu_categories_table
2026_09_10_010100_create_menu_items_table
```

Additive: two new tables, no column changed on an existing one, no data
migration. Rolling forward is `php artisan migrate`; rolling back drops the two
tables and takes every menu with them, which is the correct behaviour for a
release that introduced them.

**Order matters in both directions.** `menu_items` carries a composite foreign
key into `menu_categories`, so categories are created first and dropped last.
The `down()` methods are written accordingly, and any script that clears menu
data must delete items before categories.

No new environment variable, no new external service, no new queue worker, and
no new scheduled job. The menu is served from this application's own database
and adds nothing to the deployment surface.

### What to watch after release

- **Query count per menu request.** Seventeen at the time of writing, of which
  two are the menu itself. A jump proportional to the number of items means an
  N+1 has been reintroduced; `MenuPerformanceTest` should have caught it, so a
  jump in production without a test failure means the test's fixture no longer
  resembles production.
- **Routing-provider call volume.** It must not move when menu traffic moves.
  The menu is the most-opened screen in the product after discovery, and it is
  the one that must stay free.
