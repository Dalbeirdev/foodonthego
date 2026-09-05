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

---

## Module 11 release notes

Additive again, and larger: six new tables (`menu_item_variants`,
`menu_modifier_groups`, `menu_modifier_options`, `menu_item_modifier_group`,
`carts`, `cart_items`, `cart_item_modifiers` — seven, counting the pivot) plus
one altered table.

**The altered table is `menu_items`, and it is the one to read before
deploying.** The migration adds `UNIQUE (id, restaurant_id)` to it. That index
is redundant on its own — `id` is already unique — and exists solely so that
`menu_item_variants` can hold a composite foreign key into it and make a variant
belonging to one restaurant's item and another restaurant's row unwritable.
Adding a unique index to a populated table takes a lock proportional to its
size; on a menu table of any realistic size that is milliseconds, but it is a
DDL lock and it belongs in a maintenance window rather than mid-service.

**Order matters, in both directions.** The dependency chain is:

```
menu_items ──► menu_item_variants ──┐
menu_modifier_groups ──► menu_modifier_options ──┐
                                    ├──► cart_items ──► cart_item_modifiers
carts ──────────────────────────────┘
```

Migrations are numbered to run in that order and the `down()` methods reverse
it. Rolling back drops every cart, which is correct for a release that
introduced them — but it also drops the composite index on `menu_items`, so a
rollback that is later rolled forward re-takes the same DDL lock.

**One generated column.** `carts.active_flag` is
`CASE WHEN status = 'ACTIVE' THEN 1 ELSE NULL END STORED`, and it exists to make
`UNIQUE (customer_id, trip_id, active_flag)` a *partial* unique index: two
abandoned carts for the same trip both store `NULL` and do not collide, one
active cart does. MySQL will not accept a cascading foreign key on a column that
appears in a generated column's expression, which is why the flag derives from
`status` alone and `trip_id` is a plain member of the index.

No new environment variable, no new external service, no new queue worker, no
new scheduled job, and — this is the one that matters for cost — **no new
routing-provider call**. Opening a dish and adding it to a cart reuses the
ordering context Module 07 already cached.

### What to watch after release

- **Query count on the add path.** Reads are flat at the time of writing; the
  inserts grow with the number of chosen options, which is legitimate. A jump in
  *reads* proportional to options means an N+1 was reintroduced.
- **`PRICE_UPDATED` rate.** A trickle is the feature working — a restaurant
  changed a price while somebody had the dish open. A spike means either a
  restaurant is editing prices in bulk during service, or a client is caching a
  dish longer than it should.
- **Unique-index violations on `cart_items.configuration_hash`.** These are
  caught and merged, so they never surface as errors; they surface as a counter.
  A rising counter means duplicate taps are reaching the server, which is the
  race the index exists to lose safely.
- **Routing-provider call volume.** Still must not move. Ordering is now the
  deepest funnel in the product and it is still free.
