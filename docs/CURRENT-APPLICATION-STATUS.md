# CURRENT APPLICATION STATUS

Restart Module 01 — live audit. Commit `b49dcb4`, captured 2026-09-14.

Everything here was established by running the software, not by reading a
previous completion report. Where something could not be run, it says so.

## Superseded in part by Restart Module 02

The client chose React for Customer Web. `web/apps/customer` now exists and is
what `deploy/web.Dockerfile` copies to `/var/www/customer`; the Dockerfile has no
Flutter stage. Flutter builds Android and iOS only. The finding below is kept as
the record of what was true before that decision.

## The single most important finding (as at Restart Module 01)

**A Customer Web application already exists.** It is not a React app and it is
not listed under `web/apps/`. It is the Flutter customer app compiled with
`flutter build web --release`, copied to `/var/www/customer` by
`deploy/web.Dockerfile:93`, and served at the site root by
`deploy/nginx/app.conf:84`. It is what answered when the phone number was typed
into `techpio.tech:8080` and an OTP screen came back.

So the brief's condition — *"If Customer Web does NOT currently exist: create its
proper foundation now"* — **is not met**. A second customer frontend in React
would not be filling a gap; it would be a decision to build and then maintain the
entire customer journey twice. That decision is the client's and is put to them
rather than taken here. See PLATFORM-PARITY.md for the trade-off.

## Actual paths

| Thing | Actual path | Notes |
| --- | --- | --- |
| Backend (Laravel 12, PHP 8.4) | `backend/` | 58 routes in `backend/routes/api.php` |
| Customer Web | `web/apps/customer/` | **React 19 + TS + Vite, added by Restart Module 02.** Served at the origin root |
| Customer Android | `mobile/android/` | `com.foodonthego.foodonthego` |
| Customer iOS | `mobile/ios/` | Runner target, no signing configured |
| Restaurant Web | `web/apps/restaurant/` | React 19 + TS + Vite, base `/restaurant/` |
| Admin Web | `web/apps/admin/` | React 19 + TS + Vite, base `/admin/` |
| Shared web design system | `web/packages/ui/` | Tokens, AppShell, primitives, apiClient |
| Migrations | `backend/database/migrations/` | 38 migrations, all Ran |
| Seeders | `backend/database/seeders/` | 3 seeders |
| Deployment | `deploy/` | Dockerfiles, compose, nginx |
| CI | `.github/workflows/ci.yml`, `deploy.yml` | 7 jobs |
| Docs | `docs/` | 36 numbered documents + evidence |

There is **no `web/apps/customer`**. That is a fact, not a gap — see above.

## What was actually run

A local replica of the production routing was used so that what a browser sees
here is what a browser sees on the deployed site: `/api` proxied to Laravel, the
two shells on their sub-paths with SPA fallback, the customer app at the root,
one origin throughout.

| Application | URL used | Running | Auth | Live verified |
| --- | --- | --- | --- | --- |
| Backend API | `http://127.0.0.1:8000` | YES | n/a | `health/ready` 200 |
| Customer Web | `http://127.0.0.1:8100/` | YES | phone+OTP | YES — renders, see caveat |
| Restaurant Web | `http://127.0.0.1:8100/restaurant/` | YES | **NONE** | YES |
| Admin Web | `http://127.0.0.1:8100/admin/` | YES | **NONE** | YES |
| MySQL 8 | 127.0.0.1:3306 | YES | — | 1.29 ms round trip |
| Redis 7 | 127.0.0.1:6379 | YES | — | 0.3 ms round trip |
| Customer Android | — | **NOT RUN LOCALLY** | — | CI emulator green |
| Customer iOS | — | **NOT RUN LOCALLY** | — | CI simulator green |

Deployed equivalent: `http://techpio.tech:8080` — plain HTTP, no TLS, because
port 443 on that host belongs to a different product.

### Android and iOS, stated honestly

- **Android live inspection = NOT PERFORMED IN THIS ENVIRONMENT.** No Android
  SDK and no emulator here (KI-001). CI runs the release APK on a Pixel 6 /
  API 34 emulator and 29 integration tests on every pull request, and those were
  green on this commit. That is evidence the app starts and the tests pass; it is
  not a screenshot taken by a person.
- **iOS live inspection = PENDING — ENVIRONMENT UNAVAILABLE.** No Apple hardware
  is reachable. CI builds on `macos-latest` and runs the integration tests on an
  iPhone simulator; both were green on this commit. An installable `.ipa` remains
  impossible without an Apple Developer account, certificate and profile.

## Test results — commands actually run

| Command | Result |
| --- | --- |
| `backend: php vendor/bin/phpunit` | **1332 passed**, 5904 assertions |
| `backend: php vendor/bin/phpstan analyse` | **No errors** |
| `backend: php vendor/bin/pint --test` | **passed** |
| `web: npm run typecheck` | **passed** (all 3 workspaces) |
| `web: npm test` | **33 passed** (ui 22, admin 7, restaurant 4) |
| `mobile: flutter test` | see LIVE-VIEW-EVIDENCE.md |
| `mobile: flutter analyze` | **passed** |
| Android on-device integration | **CI only** — green on `b49dcb4` |
| iOS on-device integration | **CI only** — green on `b49dcb4` |
