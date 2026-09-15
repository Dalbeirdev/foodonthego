# FOODONTHEGO RESTART MODULE 06 — ROUTING & MAPS REPORT

## A. Final status

**RESTART MODULE 06 = NOT COMPLETE.**

The route screen is built and driven live on Customer Web. Three things the
definition of done names are not true, and none of them can be made true from
here:

- **No map is visible on any platform.** No Google Maps key exists (MF-08).
- **No real route has ever been calculated.** No routing provider credential
  exists (MF-12), so every figure comes from a straight-line stand-in.
- **Android and iOS were not looked at by a person.** No SDK, emulator or Apple
  hardware is reachable.

## B. Before-state findings

- **Web:** `/trips/{id}` rendered "Route not calculated yet" whatever the route
  status was — including for a trip whose route was **READY** and selected in
  the database. No map, no distance, no travel time, no CTA.
- **Android / iOS:** the route screen, map view and option cards exist in source
  with tests. Never run here. **And a Maps key had no path into either native
  SDK** — see §C.
- **Backend:** complete. Provider abstraction, calculation, selection,
  validation, freshness, endpoint invalidation, 35 tests.
- **Provider:** `ROUTE_PROVIDER=development` — a straight-line stand-in that
  labels itself. `GoogleRouteProvider` built, never called.
- **Map:** nothing rendered anywhere, on any platform.

## C. Root causes

1. Restart Module 05 shipped a placeholder journey screen and left the content
   here.
2. **`MapsConfig.canRenderMap` turned the map on from a `--dart-define`, and the
   key reached neither native SDK.** Android reads a manifest meta-data element
   that did not exist; `GMSServices.provideAPIKey` was never called. The app was
   arranged to switch its map on the day a key arrived and both SDKs were
   arranged to have nothing to authenticate with. Nothing could catch it: with no
   key, the map is never attempted and every test passes.
3. The customer-safe error allow-list predated the route codes.
4. The split layout's breakpoint made the map shrink as the screen grew.

## D. Routing architecture

Route API `POST …/route/calculate`, `GET …/routes`, `POST …/routes/{route}/select` ·
Service `RouteCalculationService` + `RouteSelectionService` · Interface
`RouteProvider` · Google `GoogleRouteProvider` (never called) · Persistence
`trip_routes`, unique index over (trip, selected) · Cache persisted rows plus a
900-second freshness window.

## E. Real controlled route

Customer: a controlled test identity. Trip `d11cf553-505c-47e6-a6c2-acb310f1851c`.
Origin: saved **Home** — Green Park, New Delhi (28.5590, 77.2070). Destination:
**Jaipur International Airport** (26.8242, 75.8122). Provider: `development`.

## F. Route result

Distance **236,786 m**. Base duration **14,179 s**. Traffic duration **null**.
Traffic available **NO**. Calculated at `2026-09-15 10:46:28`. Freshness
**FRESH** (900 s window). Polyline **154 characters**, decodes to a line.

**None of these is a real routing result.** The provider returns the great-circle
distance and a flat assumed speed, and says so in `provider` and `summary`.

## G. Route alternatives

Returned **1**. Persisted **1**. Default: the provider's recommended route,
auto-selected. Alternative selection: **NOT AVAILABLE** — the provider returns
one route by design and must not fabricate a second. The alternatives UI is
covered by component tests with fixture data and by backend tests.

## H. Customer Web

URL `http://127.0.0.1:5180` (production build, same-origin `/api` proxy).
Build: Vite 6 / React 19.

Map **FAIL — no tiles** (MF-08); route shape, markers and bounds **PASS** ·
Markers **PASS** · Polyline **PASS** · Distance **PASS** · Duration **PASS** ·
Alternatives **NOT AVAILABLE** · Selection **PASS (tests + API)** ·
Find Food **PASS**.

## I. Android

APK: built by CI on the pull-request run, not here. SHA-256: **not known** — the
digest GitHub publishes is the zip archive's, not the `.apk`'s, and hashing the
file needs an authenticated artifact download this session cannot make. Device:
**none reachable**. All feature results **PENDING — environment**.

## J. iOS

Build: CI only. Device: **none reachable**. iOS version: n/a.
**PENDING — RUNTIME ENVIRONMENT UNAVAILABLE.** Exact blocker: no Apple hardware
and no Apple Developer account. Not a pass.

## K. Map verification

Origin marker **PASS** · Destination marker **PASS** · Route polyline **PASS** ·
Fit bounds **PASS** (the drawing is shaped from the route's own bounds) ·
Pan/zoom **N/A** — there are no tiles to pan · Selected vs alternate visual
**PASS (tests)** — design tokens, brand shade at full weight against neutral.

## L. Traffic verification

Provider returned traffic **NO** · Displayed **NO** · Any fake traffic **NO**.
The screen says "Traffic information is not available for this route." and six
tests assert `formatTrafficLine` returns null rather than reusing the base
duration.

## M. Route selection

Selected route `c5302c3f-a379-41a0-b3ac-b6f74befb20a`. Persisted **PASS** ·
Browser refresh **PASS** · Android restart **PENDING** · iOS restart **PENDING** ·
Exactly one selected **PASS** (verified across the whole table: no trip has two) ·
Concurrent selection **PASS** — added this module.

## N. Security

Foreign trip **PASS** · Foreign route **PASS** · Trip/route mismatch **PASS** ·
Distance tamper **PASS** · Duration tamper **PASS** · Polyline tamper **PASS** ·
`customer_id` injection **PASS**. All driven live against the API; the stored
values were unchanged in every case.

## O. Provider key security

Web: **no key of any kind in the bundle** — and with no key defined at build
time, no Google code at all survives tree-shaking. Android: wiring added, key
absent. iOS: wiring added, key absent. Server: no routing key exists.
**Unrestricted server key found in client: NO.**

## P. Cost control

Initial Routes API calls **1** · 5 web refreshes **+0** · 5 route reopens **+0** ·
Fresh session **+0** · Maps tile/render calls **0** (no key) · Razorpay **0** ·
Restaurant-discovery calls before Find Food **0**.

## Q. Route freshness

Fresh **PASS** — a second calculate inside the window left `calculated_at`
unchanged. Aging **NOT USED** — the model has FRESH and STALE, no middle state.
Stale **PASS** — endpoint changes invalidate. Recalculation **PASS** —
`?refresh=true` changed `calculated_at`, which is the control proving the reuse
above is real.

## R. Offline

Cached route **NOT IMPLEMENTED** (MF-30) · Offline recalculate **BLOCKED**, with
an honest connection message and a retry · Stale indicator **PASS** — "Worked out
N min ago" is always shown.

## S. Restaurant listing handoff

CTA "Find food on this route" → `/trips/{tripId}/restaurants?route={routeId}`.
Trip id and selected route id both carried, as identifiers only. Result: a real
screen naming both. Restaurant listing implementation:
**PENDING RESTART MODULE 07.**

## T. Responsive

360 **PASS** · 390 **PASS** · 430 **PASS** · 768 **PASS** · 1024 **PASS** ·
1280 **PASS** · 1440 **PASS** · 1920 **PASS** — 0 px horizontal overflow at every
width, with the map's rendered size measured at each.

## U. Accessibility

Keyboard **PASS** — Tab reaches refresh and the CTA, Enter navigates, no mouse.
Screen reader **PASS** — every figure the drawing shows is also in text; the SVG
carries `role="img"` and a describing label. Route cards **PASS** — native
buttons with the whole card in the accessible name. Map alternative **PASS** —
the map is never the only representation. Large text **PASS** — wrapping rows,
no fixed columns.

## V. Performance

Route GET 19–21 ms · Route calculate 23 ms (local stand-in; a real provider adds
its own round trip this environment cannot measure) · Selection API ~20 ms ·
Persistence within the calculate figure · Map render: immediate, it is inline SVG.

## W. Tests

Backend `vendor/bin/phpunit` — **1,346 passed**, 5,955 assertions.
Web `npm test` — **159 passed** (customer 126, ui 22, admin 7, restaurant 4).
Mobile `flutter test` — see the preflight log; includes the new 7-assertion
maps-key guard. Provider contract test — **BLOCKED**, no credentials.
Security — IDOR, mismatch, tamper, injection and concurrency, live and in the
suite.

## X. Database / cache verification

One trip, one route row, `is_selected = 1`, `is_recommended = 1`, provider
`development`, 236,786 m, 14,179 s, traffic NULL, 154-character polyline. A query
across the whole `trip_routes` table found **no trip with two selected routes**.

## Y–Z. Live screens and screenshots

19 states driven; 10 screenshots in `docs/evidence/restart-module-06/`. All from
the running application. **None shows a map, because there are no tiles to show.**

## AA. Console / runtime errors

Before: none. After: **none**. Remaining: the pre-existing `act(...)` warnings in
two Restart Module 02/03 test files.

## AB–AD. Bugs

6 found, 6 fixed. 5 findings recorded as not-defects with reasons. See
`RM06-BUG-REGISTER.md`.

## AE. Platform parity

See `PLATFORM-PARITY.md`. Web is live for everything except tiles; Android and
iOS are code-plus-tests with device runtime pending.

## AF. Files changed

**New:** `web/apps/customer/src/route/` (10 files incl. 3 test files),
`mobile/test/maps_key_reaches_the_sdks_test.dart`,
`docs/RESTART-MODULE-06-ROUTING-MAPS.md`,
`docs/evidence/restart-module-06/` (10 screenshots + 3 documents).

**Changed:** `web/apps/customer/src/App.tsx`, `trips/tripErrors.ts`,
`trips/TripsScreen.test.tsx`; **deleted** `trips/TripScreen.tsx` (superseded);
`mobile/android/app/build.gradle.kts`,
`mobile/android/app/src/main/AndroidManifest.xml`,
`mobile/ios/Runner/AppDelegate.swift`, `mobile/ios/Runner/Info.plist`;
`backend/tests/Feature/Api/Customer/TripRouteApiTest.php`; and six documents.

## AG. Documents updated

`FRONTEND-FLOW.md`, `MISSING-FEATURES.md`, `PLATFORM-PARITY.md`,
`LIVE-VIEW-EVIDENCE.md`, `CURRENT-APPLICATION-STATUS.md`,
`33-customer-web-guide.md`.

## AH. Customer guide

Route section: **YES** — "Reviewing your route", sections 8–11 of
`33-customer-web-guide.md`. Screenshots referenced: 4.

## AI. Missing features still pending

Restaurant listing — Restart Module 07 · Search and filters — 08 · Restaurant
details — 09 · Menu — 10 · Item — 11 · Cart — 12 · Pickup — 13 · Checkout — 14 ·
Payment — 15 · Confirmation — 16 · Tracking — 17 · ETA — 18, never specified.
Plus MF-08, MF-12, MF-26, MF-27, MF-30, MF-35, MF-36.

## AJ. Restart Module 07 input

- **Trip id** — uuid, in the CTA's path.
- **Selected route id** — uuid, in the query, and authoritative server-side as
  the single `is_selected` row for the trip.
- **Polyline** — encoded, on the route row; `bounds` alongside it.
- **Route distance / duration** — 236,786 m / 14,179 s on the controlled trip.
- **Route version** — `calculated_at` plus the endpoint fingerprint that
  `invalidateIfEndpointsChanged` compares, so a changed journey invalidates
  downstream results.
- **Restaurant discovery API** — `GET /api/v1/customer/trips/{trip}/restaurants`
  exists with its own throttle, tenant scoping and 3 test files. **No frontend
  calls it on any platform.**
- **Geospatial capability** — corridor, proximity, detour and distance-ahead
  arithmetic exist in `App\Support\Geo` and the discovery engine.
- **Missing dependencies** — a routing credential (**MF-12**) and a Maps key
  (**MF-08**). Discovery ranking computed over a straight-line corridor will be
  wrong in the same way the distances are.

**Do not start Module 07.**

## AK. Zero-skip checklist

- [x] Restart Modules 01–05 reviewed · [x] Real trip exists · [x] Route code audited
- [x] Provider config audited · [x] Map SDK config audited — **and found broken**
- [x] Before screenshots captured
- [x] Customer Web route live · [ ] **Android route live — NO** · [ ] **iOS — PENDING**
- [x] Route calculation API · [x] Customer ownership · [x] Origin authoritative · [x] Destination authoritative
- [x] Provider abstraction · [ ] **Google provider real — NO, never called**
- [x] Route status · [x] Calculating · [x] Ready · [x] Failure · [x] No route · [x] Stale
- [x] Distance real *for the provider configured* · [x] Duration likewise
- [x] Traffic only when actual · [x] No fake traffic
- [ ] **Route alternatives real — NOT RETURNED BY PROVIDER** · [x] No fake alternatives
- [x] Provider default route · [x] Route normalised · [x] Route persisted · [x] Polyline persisted
- [ ] **Map rendered — NO TILES** · [x] Origin marker · [x] Destination marker · [x] Polyline rendered · [x] Fit bounds
- [ ] **Web map — tiles NO** · [ ] **Android map — NO** · [ ] **iOS map — PENDING**
- [x] Single route UX · [x] Alternative route UX (tests) · [x] Route selection · [x] Backend selection
- [x] Exactly one selected · [x] Concurrent selection test
- [x] Browser refresh persistence · [ ] **Android restart — PENDING** · [ ] **iOS restart — PENDING**
- [x] Route IDOR · [x] Trip mismatch · [x] Distance tamper · [x] Duration tamper · [x] Traffic tamper · [x] Polyline tamper · [x] customer_id injection
- [x] Route freshness · [x] Fresh reuse · [x] Stale behaviour · [x] Route cache · [x] Cache scoped · [x] Trip change invalidates
- [x] Provider timeout · [x] Provider error · [x] Quota error
- [ ] **Web key restricted — no key exists** · [ ] **Android — no key** · [ ] **iOS — no key** · [ ] **Server — no key**
- [x] No server key in the client bundle · [x] No full polyline in logs · [x] Travel privacy reviewed
- [x] Account switch isolation · [ ] **Offline cached route — NOT IMPLEMENTED** · [x] Offline recalculation blocked · [x] Session expiry
- [x] Find Food CTA · [x] CTA only with a valid selected route · [x] Restaurant listing handoff
- [x] No restaurant listing falsely marked repaired
- [x] Initial Routes calls counted · [x] 5-refresh cost test · [x] 5-revisit cost test · [x] Restart cost test
- [x] Razorpay = 0 · [x] Restaurant calls before CTA = 0
- [x] Responsive 360 / 390 / 430 / 768 / 1024 / 1280 / 1440 / 1920
- [x] Web keyboard · [x] Screen-reader textual route · [x] Map not sole representation · [x] Large text
- [ ] **Android back — not run** · [ ] **iOS back — pending** · [x] Browser back
- [x] Backend tests · [x] Web tests · [x] Flutter tests · [ ] **Provider contract test — BLOCKED** · [x] Security tests · [x] Integration test
- [x] Database inspected · [x] Cache inspected · [x] Browser console inspected · [ ] **Flutter logs — nothing ran to produce any** · [x] Laravel logs inspected
- [x] Actual screenshots · [x] Customer guide · [x] Platform parity · [x] Missing features · [x] Frontend traceability · [x] Bug register
- [x] Build manifest — via this report · [x] APK rebuilt by CI · [ ] **APK SHA-256 — not knowable here**
- [x] Restart Module 07 input documented

Twenty unchecked items. Every one of them is one of three facts: **no Maps key**,
**no routing credential**, **no device runtime**.

---

**RESTART MODULE 06 = NOT COMPLETE**

The route screen is real, live and honest about what it cannot show. The map,
the routing figures and the mobile platforms are not verified, and this report
does not claim they are.

**STOP. Restart Module 07 not started.**
