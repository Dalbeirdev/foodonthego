# 09 — Testing strategy

## Principle

A test exists to catch a specific failure. Tests that assert a framework works are noise; tests that
pin a decision (redaction, contrast, idempotency, error disclosure) are the ones worth having.

## Backend — 693 tests

Run against **real MySQL 8**, not SQLite. The schema uses MySQL types and later modules will use
MySQL locking semantics; a SQLite run would pass against a schema production cannot create.
Cache/session/queue use array drivers so a run neither depends on nor pollutes a live Redis — the
Redis integration itself is covered by the readiness test.

| Suite | Covers |
| --- | --- |
| `HealthTest` | Liveness, readiness against real MySQL + Redis, no credential leakage |
| `TripServiceTest` | Endpoint resolution, coordinate validation, the same-place rule, the open limit |
| `TripApiTest` | The trip endpoints as a client sees them; that no DELETE exists and no route field is ever returned |
| `TripOwnershipTest` | The trip IDOR matrix, including creating a trip from another customer's saved address |
| `PolylineCodecTest` | Google's own worked example, round trips, and refusal of empty, truncated and over-long geometry |
| `RouteProviderTest` | The Google Routes v2 adapter against a stubbed transport: field mask, traffic-aware mapping, timeouts, 429, malformed bodies, and the unconfigured/development providers |
| `RouteValidatorTest` | What a provider response has to satisfy before it is stored |
| `RouteCalculationServiceTest` | Freshness window, the concurrency lock, invalidation on an endpoint change, failure kinds, recovery |
| `TripRouteApiTest` | The three route endpoints as a client sees them, including that `GET` never calculates |
| `TripRouteOwnershipTest` | The route IDOR matrix, including selecting another customer's route on your own trip |
| `RouteLoggingTest` | Reads the log file on disk: route events present, geometry and coordinates absent |
| `RouteGeometryTest` | Point-to-polyline projection against distances checkable by hand: perpendicular rather than nearest-vertex, ordering along the route, behind-origin, beyond-destination, self-crossing, simplification safety |
| `RestaurantEligibilityTest` | Every rule, plus **all 72 combinations** asserting the SQL scope and the service never disagree |
| `RestaurantAvailabilityTest` | Opening hours in the restaurant's own timezone, overnight windows, split service days, and that a paused restaurant is never reported as open |
| `RestaurantDiscoveryServiceTest` | The pipeline with a provider the test controls: corridor rejection without a provider call, high-detour exclusion, budget caps, cache reuse, suspension invalidation |
| `DiscoveryRankingTest` | The score as product statements — which of two restaurants should win, and why |
| `TripRestaurantApiTest` | The endpoint as a client sees it, including that no private restaurant column reaches the body |
| `TripRestaurantOwnershipTest` | The discovery IDOR matrix |
| `DiscoveryLoggingTest` | Reads the log file: counts present, restaurant names and coordinates absent |
| `DiscoveryPerformanceTest` | 2 000 restaurants in the table, and the query count that does not grow with the result count |
| `TripLoggingTest` | That no place a customer chose, no coordinate and no search query reaches the log file |
| `PlaceApiTest` | The place endpoints: caching by query alone, session tokens, one opaque failure code |
| `PlaceProviderTest` | All three providers — the Google adapter against a stubbed transport, the refusal, the gazetteer |
| `ErrorContractTest` | Every error shape; that a 5xx never describes itself |
| `RequestIdTest` | Correlation IDs; forged/oversized/injection-shaped inbound ids |
| `SecurityHeadersTest` | Header baseline; CORS never reflects an arbitrary origin |
| `IdempotencyTest` | Replay via a call counter; same key + different body rejected |
| `RateLimitTest` | Limit headers, 429 contract, health exemption |
| `StructuredLoggingTest` | Redaction across 11 sensitive key shapes, nested and deep |
| `RoleTest` | All seven roles; restaurant/platform roles disjoint |
| `ProductionConfigGuardTest` | Every refuse-to-boot condition |
| `UserModelTest` | UUID assignment, route key, hashing, soft delete, default role |
| `PhoneNormalizerTest` | Nine spellings of one number → one identity; landline and hostile input rejected; longest calling code wins |
| `OtpChallengeServiceTest` | Plaintext never stored, peppering, expiry, replay, attempt exhaustion killing a correct code, supersession, delivery failure |
| `RegistrationTokenServiceTest` | Forged, tampered, stale, unconsumed and mismatched tokens all refused |
| `CustomerAuthServiceTest` | No password column, phone≠email verification, role-scoped lookup, ability scoping, status gating, registration race |
| `LogOtpProviderTest` | The development sender refuses production, declares it cannot reach a handset, and writes to its own channel |
| `CustomerOtpTest` | Both endpoints end to end: masking, no enumeration, cooldown, rate limits, every failure code |
| `CustomerRegistrationTest` | Registration bound to the token; a caller-supplied number is ignored; idempotent retry |
| `CustomerSessionTest` | 401 shapes, expiry, logout scope, no cookie auth, no token in a query string |
| `AuthorizationBoundaryTest` | A customer token refused by restaurant- and admin-shaped routes, and the reverse |
| `AuthLoggingTest` | A complete sign-up written to disk, then grepped: no code, no token, no full number |
| `PruneOtpChallengesTest` | Retention window; a live challenge is never pruned |
| `CustomerAddressServiceTest` | The one-default invariant from every angle, including a write that bypasses the service; ownership; deletion promoting a survivor |
| `CustomerProfileServiceTest` | What a customer may change and what is inert however it is sent; email un-verification; Unicode names |
| `AddressSupportTest` | The composed one-line address; per-country postal rules, including a country with none |
| `ProfileApiTest` | Phone, role and status tampering; validation; markup and SQL-shaped input; cross-role refusal |
| `AddressApiTest` | Full CRUD; default handling; every validation rule; the address limit |
| `AddressOwnershipTest` | IDOR read/update/delete/default, ownership injection, concurrent defaults, duplicate submission |
| `AddressLoggingTest` | A full round of operations written to disk, then grepped: no address, no email, no phone |

## Web — 29 tests

| Suite | Covers |
| --- | --- |
| `AppShell.test.tsx` | Navigation, active state, breadcrumbs, collapse + persistence, account menu, skip link, landmark labelling, localStorage throwing |
| `apiClient.test.ts` | Envelope unwrapping, error codes, transport vs server failure, malformed body, idempotency header, 204, abort |
| `admin/App.test.tsx` | Navigation architecture completeness; System Health states |
| `restaurant/App.test.tsx` | Navigation architecture completeness |

## Mobile — 453 tests

| Suite | Tests | Covers |
| --- | --: | --- |
| `domain_models_test.dart` | 16 | Greeting/initials edge cases, order lifecycle, progress clamping, dashboard states |
| `components_test.dart` | 21 | Every status state, countdown flooring, touch targets, long content, 1.4x text, error kinds, loading button |
| `navigation_test.dart` | 12 | The five-tab matrix, rapid switching, double-tap, Android back, state retention, placeholder routing |
| `home_screen_test.dart` | 14 | Personas A–D, loading, four error kinds, retry re-fetch, dark mode |
| `fixture_isolation_test.dart` | 11 | Environment gating, feature flags, production repository invents nothing |
| `tokens_test.dart` | 8 | 4px grid, touch targets, type floors, **WCAG contrast ratios**, theme wiring |
| `auth_flow_test.dart` | 27 | The whole sign-in walk: guard redirects, local validation, every server failure code, resend countdown, registration binding |
| `auth_session_test.dart` | 12 | Restore with and without a network, expired tokens, sign-out confirmation, sign-out with the server unreachable |
| `api_client_test.dart` | 13 | Envelope unwrapping, unknown codes, gateway HTML, credential placement, one-401-ends-the-session |
| `trip_models_test.dart` | 22 | Trip parsing, the wire shape, the same-place rule, that no payload carries a customer id or a route field |
| `trips_screen_test.dart` | 13 | Two scopes, four states, the row menu, discarding, and that no row shows a distance |
| `trip_planner_test.dart` | 20 | The whole planner: picking, swap, clear, validation, creation, failures, and that labelled rows can be activated |
| `place_search_test.dart` | 13 | Debounce, session-token lifecycle, and the stale-answer race |
| `location_permission_test.dart` | 15 | Every permission outcome, contextual asking, and a device that never answers |
| `address_location_test.dart` | 4 | Locating a saved address, and that an unlocated one sends no coordinates |
| `account_isolation_test.dart` | 6 | A real account switch: no frame of the previous customer's addresses or journeys |
| `auth_models_test.dart` | 21 | Trunk-zero handling, per-country plausibility, masking parity with the server, token never printed, every backend error code mapped |
| `profile_edit_test.dart` | 17 | The locked phone panel, what the form can and cannot send, validation, server field messages, offline, a 500 that shows no stack trace |
| `saved_addresses_test.dart` | 27 | Empty/loaded/error, add, edit, set default, delete with confirmation, long content at 320dp, the type selector on the smallest screen |
| `address_models_test.dart` | 21 | Parsing, absent coordinates staying null, blank-to-absent on the wire, client postal rules mirroring the server |
| `account_isolation_test.dart` | 3 | Rahul → sign out → Ananya through the real sign-in flow; no stale frame, no request while signed out |

Two of these earn their keep by asserting things a screenshot cannot show: `retry actually re-asks
the repository` counts calls and caught a silent retry loop; the contrast tests compute WCAG
luminance and caught a palette below AA.

`tokens_test.dart` computes real WCAG relative luminance. It caught a genuine defect: white on
`primary-600` was 3.31:1.

## Integration — the real thing

`mobile/tool/integration_smoke.dart` drives **this app's own `ApiClient` and `ApiAuthRepository`**
against a running Laravel server and a real MySQL database. No mocks, no fakes, no stubs: 15
assertions covering request, wrong code, correct code, registration, `/customer/me`, replay refusal,
logout revocation, an invalid number, and the resend cooldown.

It exists because the widget tests prove the screens behave correctly against a fake and the backend
tests prove the API behaves correctly on its own — but neither proves the two agree on the wire. A
field renamed on one side and not the other passes both suites and fails in a customer's hand.

It is deliberately a `dart run` and not a `flutter test`: `flutter_test` replaces `HttpClient` with
a mock, so a "test" there could never make a real request.

Module 04 adds `mobile/tool/profile_addresses_smoke.dart`, which walks the whole worked example —
Rahul edits his profile, saves Home, Work and a custom address, moves the default, edits, deletes,
and then Ananya's address is attacked four ways and survives. 24 assertions against the running
server and its database.

Module 05 adds `mobile/tool/trip_planner_smoke.dart`: a real place search and resolution, a trip
created from a saved address and a searched place, the address then edited and deleted to prove the
trip did not move with it, coordinate and same-place validation, a mass-assignment payload carrying
`customer_id`, `status`, `route_status`, `distance` and `eta`, and the trip IDOR matrix across two
real accounts — including creating a trip *from somebody else's saved address*. 31 assertions.

Module 06 adds `mobile/tool/route_smoke.dart`: a trip planned through the Module 05
flow, a route calculated, the geometry decoded and checked to run between the two
places, the freshness window proved by counting provider calls, an endpoint moved
underneath a stored route to prove invalidation, a tamper payload carrying
`distance_meters`, `duration_seconds` and `route_status`, and the route IDOR
matrix across two real accounts. 21 assertions.

That run prints what the configured provider actually returned — provider name,
whether it is a real one, route count, distance, duration, traffic figure,
polyline point count — rather than asserting against numbers baked into the test.
Where the provider returns a single route it records
`Alternative-route runtime test = NOT APPLICABLE` instead of inventing a second
one to assert against.

Module 07 adds `mobile/tool/discovery_smoke.dart`: the documented fixtures seeded
through their own development-only seeder, a Green Park → Jaipur trip planned and
routed through Modules 05 and 06, then discovery run against that real geometry —
eligible fixtures found, suspended and unverified ones absent, the far one
rejected, availability told apart, journey ordering, the raw body checked for
seven private columns, cache reuse, a suspension taking effect immediately, and
the ownership boundary. 22 assertions.

It prints the figures the run actually produced rather than asserting against
numbers baked into the test, and where the configured provider cannot exercise a
rule it says so instead of passing quietly: with a straight-line road network no
in-corridor stop can exceed the detour limit, so the run records
`Detour-threshold exclusion = NOT APPLICABLE` and points at the automated test
that covers it with a provider the test controls.

One of those assertions exists because of a defect no fake could have caught: the client was sending
`?scope=open` and the server filters on `?status=`. An unknown query parameter is *ignored*, so every
list came back unfiltered — discarded trips sat in the open list — while every widget test against a
fake repository still passed. **A contract with a real server has to be tested against a real
server.**

The earlier lesson still holds and this run keeps applying it: **read the database back**. Reading
the `trips` rows directly is what showed every journey starting from a place called "Use my current
location" — an instruction rather than anywhere — which no API assertion would have questioned.

## Live-view verification

Automated, not manual claims. `web` shells are driven in headless Chromium across **360, 390, 430,
768, 1024, 1280, 1440 and 1920px**, asserting on each:

- no console errors, page errors or failed requests
- `scrollWidth <= clientWidth` (no horizontal overflow) — **including with the API forced down**,
  because the degraded state renders the longest string in the topbar
- no interactive control shorter than 44px

Then every one of the 25 nav routes is visited, asserting exactly one active link and a breadcrumb;
the sidebar collapse, the account menu, Escape-to-close and the mobile drawer are exercised.

Flutter is built for web and rendered at iPhone SE / iPhone 15 / iPhone 15 Pro Max / small-Android
logical sizes, with all five tabs visited and dark mode captured.

For Module 03 the Flutter build is driven **against the real API and database** — a `production`
build, so no fixtures and no development harness — through Flutter's DOM semantics tree: welcome →
country picker → phone → code (wrong, then right) → registration → home → profile → sign out →
reload. 20 screenshots, and the run asserts no console errors and no page errors throughout.

Module 05 drives the same way, with the browser's own geolocation standing in for a handset's: home
→ planner → picker → a real device fix → search → results → no results → both ends → swap → create →
detail → list → same-place refusal → clear → validation → discard → discarded scope → the address
locator → a location refusal → a provider failure → offline, then 320/360/430dp and dark mode.
28 states, and the run asserts throughout that no screen anywhere shows a distance, a duration or an
ETA.

Two defects came out of that run and could not have come from anywhere else. The picker's rows were
wrapped in `Semantics(excludeSemantics: true)` to give each row one sensible label, which also
removed the tap action underneath: the rows announced themselves as buttons and could not be
activated by anything but a finger on the glass. And with the browser's permission prompt left
unanswered, `geolocator`'s own `timeLimit` never fired, so the sheet sat on "Finding you…"
indefinitely. Both are now pinned by widget tests.

Module 06 drives the route screen the same way: a journey planned from a real
device fix, calculated, recalculated, then the trip detail, the journeys list and
a cold reload of home to prove the figures reached every surface — followed by
each provider failure injected at the network (no route, timeout, rate limit,
outage), offline with a stored route and offline with none, 320/360/430dp and
dark mode. 20 states, and the run asserts throughout that the word **"ETA"**
appears nowhere.

Three defects came out of *that* run, and two of them were in the harness rather
than the app — which is itself the point. `Playwright`'s `hasText` matches
case-insensitively, so the assertion "the screen never says ETA" was quietly
matching the word "d**eta**ils" and reporting a failure that did not exist; and
Flutter renders a semantic heading as an `<h2>`, not an `<flt-semantics>`
element, so a query written against the tag name alone could never see a section
title. **An assertion that can neither pass nor fail for the right reason is
worse than no assertion**, and both were fixed by walking the whole semantics host
and matching case. The third was real: the development-provider banner, overlaid
on the space a map would occupy, landed on top of the place names in the
map-unavailable state at 320dp.

## What is not tested yet

- **No end-to-end test across all three clients** — the customer app now has a real integration run
  against the API (above), but the restaurant and admin shells still have nothing to authenticate
  with. That arrives with the module that gives them a sign-in.
- **No Android instrumentation or iOS UI test** — see [13-known-issues.md](13-known-issues.md).
- **No PHP static analysis** — PHPStan could not be installed; see the same document.
