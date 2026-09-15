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

---

# Status after Restart Module 05

## What a customer can now do in a browser, end to end

Sign in with a phone number and a one-time code → land on Home → tap **Plan a
journey** → choose a starting point from a saved place, a place search or their
current location → choose a destination from a saved place or a search → have the
same place at both ends refused → create a real journey → be taken to it by id →
reload and still find it → see it in the Trips tab and on Home. They can also
create, list and delete saved places.

Everything after the journey is still Android and iOS only: restaurants along
the route, the menu, the cart, pickup time, checkout, payment and tracking. Each
is closed by its own restart module.

## Test results — commands actually run on this commit

| Command | Result |
| --- | --- |
| `backend: vendor/bin/phpunit` | **1,344 passed** |
| `backend: vendor/bin/pint --test` | **passed** |
| `web: npm run typecheck` | **passed** (all workspaces) |
| `web: npm test` | **107 passed** — customer 74, ui 22, admin 7, restaurant 4 |
| `mobile: flutter analyze --fatal-infos` | **passed** |
| `mobile: flutter test` | **1,063 passed** |
| `mobile: dart format --set-exit-if-changed` | **passed** (268 files, 0 changed) |
| `scripts/preflight.sh` | **all runnable checks passed** |
| Android on a device | **NOT PERFORMED** — no SDK or emulator here |
| iOS on a device or simulator | **PENDING — environment unavailable** |

PHPStan is not in preflight (it needs MySQL for database reflection); CI runs it.

## The blockers that are still the client's to clear

| | What is needed | What it unblocks |
| --- | --- | --- |
| **Twilio** | API Key SID + Secret, a Messaging Service, DLT registration for India | A real SMS. Codes currently go to a log file |
| **Google Places** | A Places API key | Real place search. Today a fixed gazetteer of twelve real places |
| **Google Maps** | A Maps SDK key for Android and iOS | Any map tile, on any platform |
| **Routing provider** | Credentials | Real traffic-aware distance and travel time |
| **Razorpay** | Live keys | Any real payment |
| **Apple Developer** | Account, certificate, provisioning profile | An installable iOS build |
| **TLS on the review host** | A Cloudflare Tunnel or equivalent | HTTPS — and with it browser geolocation, which browsers refuse over http |
| **A decision on staff sign-in** | Email + password, or phone + OTP | Every operator screen. No staff login exists at all |

---

# Status after Restart Module 06

## What a customer can now do in a browser, end to end

Everything Restart Module 05 delivered, and then: the journey's route is worked
out, the route's real shape is drawn with both ends marked, the distance and
travel time are shown with the time they were calculated, the route can be
worked out again on demand, an alternative can be chosen where the provider
returns one — and **Find food on this route** carries the journey and the chosen
route to the next screen, which says honestly that Restart Module 07 owns the
listing.

Opening that screen again costs nothing: **0 billed provider calls across five
refreshes, five navigations and a fresh session**, measured on the production
build.

## What the screen tells the customer it cannot do

Two notices, both permanent until a credential arrives, and both deliberate:

- **No map tiles.** MF-08. The route shape is real; the imagery under it needs a
  Google Maps key.
- **These figures are not a real route.** MF-12. No routing provider is
  configured, so distance and time come from a straight-line stand-in.

## The finding worth acting on

A Maps key had **no path into Android or iOS**. Supplying one would have turned
the map on in the app and left both native SDKs unauthenticated — a blank grey
Android map and an iOS throw, arriving on the day the credential did. That is
now wired on both platforms and guarded by a test, so the key is one build flag
away from working.

## Test results — commands actually run on this commit

| Command | Result |
| --- | --- |
| `backend: vendor/bin/phpunit` | see the completion report |
| `backend: vendor/bin/pint --test` | **passed** |
| `web: npm run typecheck` | **passed** |
| `web: npm test` | **159 passed** — customer 126, ui 22, admin 7, restaurant 4 |
| `mobile: flutter analyze --fatal-infos` | **passed** |
| `mobile: flutter test` | see the completion report |
| `scripts/preflight.sh` | **all runnable checks passed** |
| Android on a device | **NOT PERFORMED** — no SDK or emulator here |
| iOS on a device or simulator | **PENDING — environment unavailable** |
