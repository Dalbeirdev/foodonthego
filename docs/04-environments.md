# 04 — Environments

| Environment | `APP_ENV` | Database | Debug | Purpose |
| --- | --- | --- | --- | --- |
| Local | `local` | `foodonthego_local` | on | A developer's machine |
| Testing | `testing` | `foodonthego_testing` | on | Automated tests; wiped by `RefreshDatabase` |
| Development | `development` | shared dev instance | on | Integration, shared |
| Staging | `staging` | staging instance | **off** | Production-like; guards enforced |
| Production | `production` | production instance | **off** | Live |

## Configuration is read once

`backend/config/foodonthego.php` is the only place `env()` is called for product settings.
Application code reads `config(...)`. This is what makes `php artisan config:cache` safe — with a
cached config, `env()` returns `null` everywhere else.

> One known exception, documented at the top of `config/cors.php`: it parses `FRONTEND_URLS` itself
> rather than calling `config('foodonthego.frontend_urls')`. Laravel loads all config files in one
> pass, so calling `config()` from inside a config file silently yields the default. That defect
> shipped an empty CORS allow-list and blocked every browser request until it was caught in
> live-view verification.

## Production and staging refuse to start when misconfigured

`App\Support\ProductionConfigGuard` runs at boot and throws when any of these hold:

- `APP_DEBUG` is true
- `APP_KEY` is empty
- `FRONTEND_URLS` is empty, contains `*`, or contains a non-HTTPS origin
- `DB_CONNECTION` is not `mysql`
- `DB_PASSWORD` is empty

The message names every failure at once. A container that will not start gets noticed; one that
starts insecure does not.

## Never point automated tests at a shared or production database

`phpunit.xml` pins `DB_DATABASE=foodonthego_testing`, and the suite uses `RefreshDatabase`, which
truncates. Pointing it elsewhere destroys that data.

## Test data is not production data

The personas in this repository — Rahul Sharma, Priya Verma, Highway Spice Kitchen, the
Delhi → Jaipur journey — are development fixtures. They appear only in shells and tests, are clearly
labelled as test personas in the UI, and must never be seeded into a production database.
