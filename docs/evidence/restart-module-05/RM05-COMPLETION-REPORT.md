# FOODONTHEGO RESTART MODULE 05 — TRIP PLANNER REPORT

## A. Final status

**RESTART MODULE 05 = NOT COMPLETE.**

Customer Web is done and was driven end to end in a browser. Android and iOS are
not — no Android SDK, emulator or Apple hardware is reachable from this
environment, so no screen on either platform was looked at by a person. The
brief's definition of done names all three, and iOS is explicitly "PENDING —
RUNTIME ENVIRONMENT UNAVAILABLE. Do not mark PASS."

## B. Before-state findings

- **Web:** `/trips/plan`, `/trips` and `/trips/:tripId` rendered "coming later"
  placeholders. `/profile` had a sign-out card. Nothing in a browser could plan
  a journey or create a saved address.
- **Android:** the Flutter planner, place search and location service all exist
  in source with unit and widget tests. Never run on a device from here.
- **iOS:** as Android. Never run.
- **Backend:** complete. `TripService`, `StoreTripRequest`, `PlaceProvider` with
  three implementations, five trip endpoints, three place endpoints, 30 API
  tests and 14 ownership/injection tests.
- **Places:** `PLACES_PROVIDER=development` — twelve real places at their real
  published coordinates. `GooglePlacesProvider` built, never called.
- **Current location:** Flutter had a location service with a watchdog. The web
  had nothing.

## C. Root causes

1. Restart Module 02 created the customer web routes and deferred their content.
2. **Restart Module 04 was never run**, so the web had no saved addresses, which
   made the planner's mandatory Home/Work/Other unreachable in a browser.
3. Three defects only a browser could find — a location request that never
   ended, a discarded reverse-geocode, an infinite render loop — plus three only
   a screenshot could find: a clipped heading, an illegible disabled button and
   a permanent favicon 404.
4. One privacy leak only reading the live log could find.

## D. Architecture

| | |
| --- | --- |
| Web components | `TripPlannerScreen`, `LocationPicker`, `TripsScreen`, `TripScreen`, `AddressesScreen` |
| Web hooks | `usePlaceSearch` (debounce, abort, session token), `useCurrentLocation` (six failure modes, watchdog) |
| Flutter | `trip_planner_screen.dart`, `location_picker_sheet.dart`, `place_search_controller.dart`, `current_location_controller.dart` |
| Backend service | `App\Services\Trip\TripService` |
| Trip API | `POST/GET /api/v1/customer/trips`, `GET /current`, `GET /{trip}`, `POST /{trip}/discard` |
| Place provider | `App\Services\Places\PlaceProvider` → Google / development gazetteer / unconfigured |
| Location | Browser Geolocation API on web; `location_service.dart` on mobile |

## E. Customer Web

| | |
| --- | --- |
| URL | `http://127.0.0.1:5175` (dev, API proxied same-origin as production serves it) |
| Build | Vite 6, React 19, 290 KB JS / 89 KB gzipped |
| Trip planner | **PASS** |
| Saved addresses | **PASS** |
| Place search | **PASS** |
| Current location | **PASS** locally; will report insecure-context on the http review site (MF-28) |
| Create journey | **PASS** |
| Route handoff | **PASS** |

## F. Android

APK: not built here — no SDK. SHA-256: n/a. Device: **none reachable**.
Android version: n/a. **All feature results: PENDING — environment.** CI builds
and runs the release APK on a Pixel 6 emulator on every pull request.

## G. iOS

Build: n/a. Device: **none reachable**. iOS version: n/a.
**PENDING — RUNTIME ENVIRONMENT UNAVAILABLE.** Exact blocker: no Apple hardware
and no Apple Developer account. Not a pass.

## H. Origin sources

Current location **PASS** · Saved address **PASS** · Place search **PASS**

## I. Destination sources

Saved address **PASS** · Place search **PASS**. Current location is deliberately
not offered for a destination.

## J. Saved-address integration

HOME **PASS** · WORK **PASS** · OTHER **PASS (tests)** — the live run used Home
and Work. Foreign address **BLOCKED** (`ADDRESS_NOT_FOUND`, identical to a
nonexistent id). Coordinate tamper **PASS**.

## K. Current location

Web permission: granted, blocked, insecure context, unsupported, timeout and
never-answers, all handled distinctly. Android and iOS permission: **PENDING**.
Location services disabled: reported as `position-unavailable`. Actual result:
controlled fix 28.6129, 77.2295 → "New Delhi", coordinates unchanged. No
background permission: **PASS** — no `watchPosition`, no always-on location
anywhere in the app.

## L. Places provider

Provider: `development` (a fixed gazetteer of twelve real places). Autocomplete:
working. Debounce: 350 ms. Session token: minted per search, reused for details,
rotated on selection. Place details: working. Key restrictions: **not
applicable to the web client — it holds no key and calls no provider.** Google's
own API has **never been called** (MF-29).

## M. Provider cost test

| | |
| --- | --- |
| Search characters typed | 10 (`jaipur air`) |
| Autocomplete calls | **1** |
| Place detail calls | **1** (on selection) |
| Reverse geocode calls | **1** (only when current location is used) |
| Route API calls during trip create | **0** |
| Razorpay calls | **0** |
| Provider calls when selecting a saved address | **0** |

## N. Validation

Origin required **PASS** · Destination required **PASS** · Same location
**PASS** · Invalid latitude **PASS** · Invalid longitude **PASS** ·
Null Island (0, 0) **PASS**, with its own error code.

## O. Journey creation

Customer: a controlled test identity. Origin: saved **Home** (Green Park, New
Delhi). Destination: **Jaipur International Airport**, from a place search.
Trip id: `d11cf553-505c-47e6-a6c2-acb310f1851c`. Status: `ROUTE_PENDING`.
Route status: `NOT_CALCULATED`. Persisted: **PASS** — survives a reload and
appears in both the Trips tab and Home.

## P. Idempotency

Double tap **PASS** (one POST; the CTA disables while in flight).
Lost response **PASS** (same key → same id, `Idempotency-Replayed: true`).
Duplicate trip count: **1**. Negative control: the same body with no key created
**two** trips — so the replay is the mechanism, not a rejection.

## Q. Ownership

Foreign trip **PASS** (404, byte-identical to a nonexistent uuid).
Foreign saved address **PASS**. `customer_id` injection **PASS** (ignored; the
trip belongs to the authenticated caller).

## R. Home / Trips integration

Home active trip **PASS** — and this is where the `uuid`/`id` bug was found.
Trips tab **PASS**.

## S. Route handoff

Route path: `/trips/{tripId}`. Trip id passed: yes, **and only the id**.
Authoritative reload: **PASS**. Route calculation:
**NOT IMPLEMENTED HERE — RESTART MODULE 06.**

## T. Offline and errors

Place search offline: a connection message, not a server error. Current location
unavailable: its own message with alternatives. Trip create offline: refused
with a connection message; nothing queued. Provider error: "We could not load
places right now." — no provider detail reaches the customer.

## U. Responsive

360 **PASS** · 390 **PASS** · 430 **PASS** · 768 **PASS** · 1024 **PASS** ·
1280 **PASS** · 1440 **PASS** · 1920 **PASS**. Zero horizontal overflow at every
width, planner and picker dialog both, negative-controlled.

## V. Accessibility

Keyboard: **PASS**, whole flow with no mouse. Screen reader: **PASS** — combobox
semantics, `aria-activedescendant`, and field names that carry the label and the
choice. Touch: **PASS** — 44 px minimum, 56 px on the two location fields. Large
text: **PASS** — `auto-fit` grids and wrapping rows rather than fixed columns.

## W. Performance (measured, local)

Planner first render < 100 ms · saved addresses 16–19 ms · autocomplete
17–18 ms · place details 17–20 ms · reverse geocode 17–20 ms · trip create
23 ms. Current-location acquisition depends on the device; the controlled
browser fix returned in under a second.

## X. Tests

| Suite | Command | Result |
| --- | --- | --- |
| Backend | `vendor/bin/phpunit` | **1,344 passed**, 5,946 assertions |
| PHPStan | `vendor/bin/phpstan analyse` | **No errors** |
| Pint | `vendor/bin/pint --test` | **passed** |
| Web | `npm test` | **107 passed** (customer 74, ui 22, admin 7, restaurant 4) |
| Web types | `npm run typecheck` | **passed** |
| Mobile | `flutter test` | **1,063 passed** |
| Mobile analyze | `flutter analyze --fatal-infos` | **passed** |

## Y–Z. Live screens and screenshots

22 live states driven, 27 screenshots, all from the running application. Listed
in `LIVE-VIEW-EVIDENCE.md` and stored in this directory. None is a mockup.

## AA. Console and runtime errors

Before: one `/favicon.ico` 404 on every page load.
After: **none** — console, page errors and every HTTP response ≥ 400 were
collected on every capture.
Remaining: `act(...)` warnings in two pre-existing test files (B05-13).

## AB–AD. Bugs

12 found, 12 fixed. 2 recorded and not fixed, with reasons. See
`RM05-BUG-REGISTER.md`.

## AE. Platform parity

See `PLATFORM-PARITY.md`. Every row is Web PASS, Android and iOS code-plus-tests
with device runtime pending. The one genuine divergence is browser geolocation
over http, which is MF-28 and closes with MF-16.

## AF. Files changed

**New:** `web/apps/customer/src/trips/` (11 files incl. 4 test files),
`web/apps/customer/src/addresses/` (4 files), `web/apps/customer/public/favicon.svg`,
`docs/RESTART-MODULE-05-TRIP-PLANNER.md`, `docs/33-customer-web-guide.md`,
`docs/evidence/restart-module-05/` (27 screenshots + 3 documents).

**Changed:** `web/apps/customer/src/App.tsx`, `App.test.tsx`, `index.html`,
`vite.config.ts`, `home/useHome.ts`, `home/HomeScreen.tsx`,
`session/ProfileScreen.tsx`, `shell/shell.css`, `web/packages/ui/src/primitives.css`,
`backend/app/Http/Middleware/LogApiRequests.php`,
`backend/tests/Feature/Api/Customer/TripOwnershipTest.php`,
`backend/tests/Feature/Api/Customer/TripLoggingTest.php`,
`deploy/nginx/app.conf` (a stale comment), and six documents.

## AG. Documents updated

`FRONTEND-FLOW.md`, `MISSING-FEATURES.md`, `PLATFORM-PARITY.md`,
`LIVE-VIEW-EVIDENCE.md`, `CURRENT-APPLICATION-STATUS.md`.

## AH. Customer guide

Planning a journey: **YES** — `docs/33-customer-web-guide.md`. Screenshots
referenced: 10, all web. Android and iOS: none, and the guide says so.

## AI. Missing features still pending

Route and map — Restart Module 06 · Restaurant listing — 07 · Search and
filters — 08 · Restaurant detail — 09 · Menu — 10 · Item — 11 · Cart — 12 ·
Pickup — 13 · Checkout — 14 · Payment — 15 · Confirmation — 16 · Tracking — 17 ·
ETA — 18, never specified. Plus MF-26 (the rest of Module 04 on web), MF-27
(device inspection), MF-28 (geolocation needs TLS), MF-29 (live Places).

## AJ. Restart Module 06 input

- **Trip model:** `trips`, addressed by `uuid`, presented as `id`.
- **Origin and destination:** `source_type`, `display_name`,
  `formatted_address`, `latitude`, `longitude`, `place_id`, `city`, `region`,
  `country_code`, `postal_code` — all populated and validated.
- **Coordinates:** DECIMAL(10,7) / DECIMAL(10,7), in range, never (0,0), and for
  a saved address always the customer's own stored position.
- **Place ids:** present for `PLACE_SEARCH` and for a located saved address;
  null for a current-location fix that nothing could name.
- **Trip id:** a uuid, already the handoff key on Web and Flutter.
- **Route status:** `NOT_CALCULATED` on every trip this module creates.
- **Entry point:** `POST /api/v1/customer/trips/{trip}/route/calculate`, which
  already exists.
- **Missing routing dependency:** a routing provider credential — **MF-12** —
  and a Maps key for tiles — **MF-08**. Both are the client's to supply.

**Do not start Module 06.**

## AK. Zero-skip checklist

Every item, with its honest answer.

- [x] Restart Modules 01–04 reviewed — 04 found never to have been run
- [x] Existing trip code audited · [x] Places integration audited · [x] permission code audited
- [x] Before screenshots captured
- [x] Customer Web planner live
- [ ] **Android planner live — NO.** No SDK or emulator
- [ ] **iOS planner — PENDING**, honestly
- [x] Plan Journey CTA · [x] Origin field · [x] Destination field
- [x] Saved Home · [x] Saved Work · [~] Saved Other — tests only
- [x] Saved addresses refresh after creation
- [x] Current location Web · [ ] Android — pending · [ ] iOS — pending
- [x] Permission requested only on action · [x] No background location · [x] No always-location
- [x] Permission granted · [x] denied · [x] permanently denied/restricted · [x] service disabled
- [x] Current coordinates real · [x] No fake reverse geocode
- [x] Place search real · [x] Provider abstraction · [x] Debounce · [x] Session token
- [x] Suggestions · [x] No results · [x] Provider error · [x] Place details
- [x] Real coordinates · [x] Place id · [x] Search loading
- [x] Search keyboard Web · [x] Search mobile UX
- [x] API key restrictions — **the web client holds no key at all**
- [x] No server secret in the client bundle
- [x] Saved address selection costs 0 provider calls
- [x] Origin normalised · [x] Destination normalised · [x] Source type
- [x] Same-location validation · [x] Coordinate validation
- [x] Foreign saved address blocked · [x] `customer_id` injection blocked
- [x] Saved-address coordinate tamper handled
- [x] Trip create API · [x] Trip customer ownership · [x] Trip persisted
- [x] `route_status` pending · [x] No route calculation in this module
- [x] Double-submit protection · [x] Idempotency · [x] Lost-response handling
- [x] Foreign trip blocked · [x] Route handoff works
- [x] Home active trip updates · [x] Trips tab updates
- [x] Account switch clears trip draft
- [x] Offline search handled · [x] Offline trip create blocked safely
- [x] Session expiry handled
- [x] Origin/destination privacy · [x] Logs inspected — **one leak found and fixed**
- [x] Provider call count measured · [x] Routes calls = 0 · [x] Razorpay calls = 0
- [x] Responsive 360 / 390 / 430 / 768 / 1024 / 1280 / 1440 / 1920
- [x] Large text · [x] Keyboard accessibility · [x] Screen-reader semantics
- [ ] **Android back — not run** · [ ] **iOS back — pending** · [x] Browser back
- [x] Direct route auth guard · [x] Browser refresh
- [x] Backend tests · [x] Web tests · [x] Flutter tests · [x] Security tests · [x] Integration tests
- [x] Database verification · [x] Browser console inspected · [x] Laravel logs inspected
- [ ] **Flutter logs inspected — NO.** Nothing ran to produce any
- [x] Actual screenshots · [x] Client guide updated · [x] Platform parity updated
- [x] Missing features updated · [x] Frontend traceability updated · [x] Bug register updated
- [ ] **Review APK rebuilt / APK SHA-256 — NOT DONE.** No Android toolchain here; CI builds it
- [x] Module 06 input documented

Eleven unchecked items, all of them the same fact stated in different places:
**no Android or Apple runtime is reachable from this environment.**

---

**RESTART MODULE 05 = NOT COMPLETE**

Customer Web is complete and proven. Android and iOS are not proven, and this
report does not claim they are.

**STOP. Restart Module 06 not started.**
