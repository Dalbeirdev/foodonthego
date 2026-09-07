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

---

## Module 08 — testing a thing that must only ever remove

Module 08's central claim is negative: *no filter can add a restaurant.* A
negative claim needs tests that try to break it rather than tests that confirm
it.

### The tests that exist to fail

| Test | What it tries |
| --- | --- |
| `test_a_search_cannot_resurrect_a_restaurant_eligibility_removed` | Searches a suspended restaurant by its exact name |
| `test_no_filter_combination_reaches_an_unverified_restaurant` | Walks seven filter shapes against a pending restaurant |
| `test_an_injection_string_is_refused_and_changes_nothing` | Three SQL payloads, then counts the table |
| `test_filtering_sees_the_whole_eligible_set_not_a_page_of_it` | 29 restaurants; only the 29th has the filtered facility |
| `test_a_stop_behind_the_customer_is_never_first` | Every sort, including the one where tie-breaks decide everything |
| `test_every_weight_actually_reaches_the_score` | That each ranking weight has a measurable effect |
| `test_changing_a_filter_never_calls_the_routing_provider` | Counts provider calls across eight variations |

The last one is the module's cost guarantee, and it is asserted by *counting*,
not by reading the code: `StubDetourProvider::$calls` before and after.

### Where each layer is tested

| Layer | File | Tests |
| --- | --- | --- |
| Query validation | `tests/Unit/DiscoveryQueryTest.php` | 22 |
| Search normalisation and tiers | `tests/Unit/SearchMatcherTest.php` | 14 |
| Ranking | `tests/Unit/DiscoveryRankingTest.php` | 14 |
| Refinement | `tests/Feature/DiscoveryRefinerTest.php` | 30 |
| HTTP contract | `tests/Feature/Api/Customer/TripRestaurantFilterApiTest.php` | 37 |
| Client query model | `mobile/test/discovery_query_test.dart` | 21 |
| Client state | `mobile/test/discovery_refine_controller_test.dart` | 25 |
| Client widgets | `mobile/test/discovery_filters_screen_test.dart` | 34 |

### Race conditions get real tests, not comments

Two things in this module are timing bugs waiting to happen, so both are tested
with controlled latency rather than reasoned about:

- **Stale search responses.** The fake repository takes a per-query delay, so a
  request for `"spi"` can be made to finish *after* one for `"spice"`. The test
  asserts the later answer survives.
- **Stale failures.** The same, with an error scripted for the earlier query
  only, asserting that an error the customer has moved on from does not land on
  top of a good list.

A fake that could only fail "the next call" was not enough for the second one:
it fires for whichever request resolves first, which is the wrong one. The fake
takes an `errorFor(query)` callback for exactly this.

### What the fake deliberately does not do

`FakeDiscoveryRepository` does **not** re-implement filtering. A fake that
filtered by itself would let a test pass while the real request carried no
filters at all — the assertion would be on the fake's arithmetic. What the
client is responsible for is *which query it sends*, so the fake records every
query and the tests assert on those.

### Integration

`mobile/tool/discovery_filters_smoke.dart` — 28 checks through this app's own
network layer against a live Laravel backend, real MySQL rows and real Module 06
route geometry. It walks eligibility, search, every filter, sorting, facets,
pagination, validation, injection, the cost guarantee and ownership.

It clears the rate limiter's own buckets between sections — it makes far more
calls in a minute than any customer would — and says so. The limiter itself is
asserted separately, at its configured value, in the API tests.

---

## Module 09 — testing a screen whose worst failure is a lie

The consequential mistake on a restaurant page is not a crash. It is a live
"View menu" button on a kitchen that has stopped cooking, or a photograph of
somewhere else under a business's name. Both look fine in a screenshot.

### Clocks are always fixed

Every opening-hours test states the moment it is asking about:

```php
$this->at('2026-09-08 01:00')   // Tuesday, 1am, Asia/Kolkata
```

A test about opening hours that depends on the hour it runs is a test that
fails once a day and gets deleted.

### The cases that earn their own tests

| Test | What it catches |
| --- | --- |
| `test_an_overnight_window_is_open_after_midnight` | The classic: reading today's rows at 1am and calling a 18:00–02:00 dhaba shut |
| `test_the_gap_in_a_split_service_is_shut` | Treating two windows as one long one |
| `test_the_opening_minute_is_open_and_the_closing_minute_is_not` | Off-by-one at both ends |
| `test_a_restaurant_open_only_today_wraps_to_next_week` | Why the lookahead is eight days, not seven |
| `test_the_restaurants_timezone_decides_not_the_servers` | A Goa restaurant on Delhi's schedule |
| `test_a_timezone_that_observes_dst_is_handled_by_the_library` | India does not observe DST; this platform will not stay in India |
| `test_the_two_services_agree_about_being_open` | Two implementations of the same rule drifting apart |
| `test_a_permanently_closed_business_is_never_open` | The business state losing to the clock |
| `test_no_undiscoverable_status_can_produce_an_orderable_state` | Every status × every availability, exhaustively |

### The negative claims

| Test | Claim |
| --- | --- |
| `test_a_suspended_restaurant_cannot_be_opened_by_its_uuid` | A uuid is not a key |
| `test_a_missing_restaurant_and_a_withdrawn_one_answer_the_same_status` | A prober cannot enumerate suspensions |
| `test_a_restaurant_withdrawn_between_the_list_and_the_tap` | The race the module has to survive |
| `test_the_response_carries_no_private_restaurant_data` | Raw-body assertion over 16 needles |
| `test_an_unmoderated_image_never_reaches_a_customer` | The moderation default |
| `test_a_customer_has_no_way_to_change_a_restaurant` | Four verbs, none accepted |
| `test_opening_a_restaurant_is_served_from_the_discovery_cache` | The cost guarantee |

### Performance is asserted, not measured and forgotten

`RestaurantDetailPerformanceTest` adds twenty photographs, ten cuisines and ten
facilities to a restaurant and asserts the **query count is unchanged** — then
puts fifteen more restaurants on the route and asserts it again. An N+1 review
that lives in a document rots; one that lives in an assertion does not.

### Where each layer is tested

| Layer | File | Tests |
| --- | --- | --- |
| Opening hours | `tests/Unit/RestaurantHoursTest.php` | 19 |
| Ordering state | `tests/Unit/RestaurantOrderingStateTest.php` | 8 |
| HTTP contract | `tests/Feature/Api/Customer/RestaurantDetailApiTest.php` | 30 |
| Query cost | `tests/Feature/RestaurantDetailPerformanceTest.php` | 3 |
| Client model | `mobile/test/restaurant_detail_models_test.dart` | 19 |
| Client state | `mobile/test/restaurant_detail_controller_test.dart` | 17 |
| Client widgets | `mobile/test/restaurant_detail_screen_test.dart` | 34 |

### Integration

`mobile/tool/restaurant_detail_smoke.dart` — 25 checks through this app's own
network layer against a live Laravel backend and real MySQL rows. It reads
fixture uuids **straight from the database** for the direct-id tests, because
the point is that an identifier obtained from outside the API buys nothing, and
taking it from an API response would not test that.

---

## Module 10 — testing a screen that must not know more than it was told

Module 09's worst failure was a lie about a restaurant. Module 10's is a lie
about a **dish** — and one of them lands on somebody's plate. The tests are
shaped accordingly: most of them assert an absence.

### The three that matter most

| Test | What it proves |
| --- | --- |
| `test_the_database_itself_refuses_a_cross_restaurant_item` | A direct `INSERT` linking restaurant A's item to restaurant B's category raises MySQL 1452. Not a service check — the storage engine's. |
| `test_metadata_a_restaurant_did_not_give_is_null_not_invented` | Description, image, prep time, diet and spice are each absent, individually, on a dish that has none. |
| `test_opening_a_menu_asks_the_routing_provider_nothing` | The mandatory one. A counting stub across three menu opens, a search and a reopen. |

### Money is tested where floats would hide

`MoneyTest` has ten cases and half of them are refusals: a decimal amount, a
negative amount, a missing currency, a malformed currency, a cross-currency
comparison. `menu_models_test.dart` mirrors them on the client. The one that
would have caught the real-world bug is `a decimal amount is refused rather than
rounded` — because a server that started sending rupees would otherwise be
absorbed silently and be off by a factor of a hundred.

### Performance is asserted, not measured and forgotten

`MenuPerformanceTest` is eleven tests. Three of them add items, categories and
whole 500-item menus and assert the **query count does not move**; one asserts
the menu is exactly two queries by inspecting the query log; one asserts the
payload stays under 600 KB at five hundred items. The 500-item fixture is
generated in the test — production data is never used for a load measurement.

### What the unit tests could not see

Every widget test in this module passed while the client's dietary-type wire
strings did not match the server's (M10-B01), because the fixtures build domain
objects directly and never cross the JSON boundary. That is a real limitation of
fixture-built widget tests and the reason the integration run exists.

The lesson taken: **an enum whose values are a wire contract gets a test that
spells the strings out literally**, not one that derives them from the enum
itself, which would agree with whatever was written.

### Where each layer is tested

| Layer | File | Tests |
| --- | --- | --- |
| Money | `tests/Unit/MoneyTest.php` | 10 |
| HTTP contract | `tests/Feature/Api/Customer/RestaurantMenuApiTest.php` | 42 |
| Query cost | `tests/Feature/MenuPerformanceTest.php` | 11 |
| Client models and money | `mobile/test/menu_models_test.dart` | 24 |
| Client state | `mobile/test/menu_controller_test.dart` | 15 |
| Client widgets | `mobile/test/menu_screen_test.dart` | 34 |

### Integration

`mobile/tool/menu_smoke.dart` — 32 checks through this app's own network layer
against a live Laravel backend and real MySQL rows. Like Module 09's, it reads
fixture uuids **straight from the database** for the direct-id tests. It also
changes a price behind the API's back and re-reads the item, which is the only
honest way to prove the preview is fetched rather than echoed.

---

## Module 11 — testing a screen where the worst failure is a wrong price

Module 09's worst failure was a lie about a restaurant; Module 10's was a lie
about a dish. Module 11's is a customer being charged something they did not
agree to, and the tests are shaped accordingly.

### The three that matter most

| Test | What it proves |
| --- | --- |
| `test_a_client_supplied_price_changes_nothing` | Eight money-shaped fields in one body; the cart line stores the real price. |
| `test_a_price_that_rose_since_the_screen_loaded_is_refused` | The customer is never charged more than they saw — and nothing is added while they have not agreed. |
| `test_a_retry_with_the_same_key_adds_nothing_twice` | A lost response on a motorway connection is one cart line, not two. |

### Testing an absence

Most of `CustomizationPricingTest` asserts a refusal, and the assertions are
deliberately on the **specific** error code rather than "it threw". A screen can
only scroll to an unanswered group if the server distinguishes
`MODIFIER_REQUIRED` from `MODIFIER_MAX_EXCEEDED`, so a test that accepted either
would let that distinction rot.

`expectApiError` compares `ApiErrorCode` values and prints both when they differ,
which is the difference between a five-second diagnosis and a five-minute one.

### N+1 is measured on reads, not on queries

`test_adding_to_a_cart_reads_no_more_for_a_larger_customization` counts `SELECT`
statements and ignores `INSERT`s. Writing five modifier rows is five inserts —
rows being written, not a query being repeated — and an assertion on the total
would either fail on a legitimate write or be loosened until it caught nothing.

### The fixture is deliberately uneven

`configurableItem()` gives two sizes with a default and one sold out, one
required single-select group, and one optional multi-select group with paid
options. A fixture that only exercises the tidy case leaves every disabled
branch unlooked-at — and three of this module's four defects were in exactly
those branches.

### What the widget tests could not see, again

Module 10 learned that fixture-built widget tests never cross the JSON boundary.
Module 11 learned the sibling lesson: they also do not *lay out at every width*.
Three layout overflows at 320 dp were found by a widget test that ran the screen
at 320 dp, and would not have been found by one that ran it at 390.

**Every screen from here gets a 320 dp test**, and it asserts
`tester.takeException()` is null rather than only that some text is present — an
overflow is an exception, and a test that only looks for text sails past it.

### Where each layer is tested

| Layer | File | Tests |
| --- | --- | --- |
| Validation and pricing | `tests/Feature/CustomizationPricingTest.php` | 30 |
| Item detail contract | `tests/Feature/Api/Customer/ItemCustomizationApiTest.php` | 15 |
| Add to cart contract | `tests/Feature/Api/Customer/AddToCartApiTest.php` | 39 |
| Query cost and cost control | `tests/Feature/CartPerformanceTest.php` | 9 |
| Client models | `mobile/test/item_customization_models_test.dart` | 15 |
| Client state | `mobile/test/item_customization_controller_test.dart` | 34 |
| Client widgets | `mobile/test/item_detail_screen_test.dart` | 37 |

### Integration

`mobile/tool/cart_smoke.dart` — 48 checks through this app's own network layer
against a live Laravel backend and real MySQL rows. It provokes every race by
changing rows behind the API's back, which is exactly what a restaurant
dashboard will do to those columns, and it reads the written cart rows back out
of MySQL to check the stored price, the snapshots and the modifier records.

---

## The fourth layer: on-device runs (`integration_test/`)

Three layers existed before this: widget tests against repositories we wrote,
backend tests against a real database, and smoke drivers that put this app's
network layer against a live server. All three run without a phone, which is
their virtue and their limit — **none of them proves the app works on a
handset.**

`integration_test/` is the layer that does. It builds the shipping app,
installs it on a device or emulator, taps the real controls through the real
gesture pipeline, and talks to a live Laravel server writing real rows.

| Layer | Real widgets | Real HTTP | Real database | Real device |
| --- | --- | --- | --- | --- |
| `test/` — widget tests | ✅ | ❌ | ❌ | ❌ |
| `backend/tests/` — PHPUnit | ❌ | ✅ | ✅ | ❌ |
| `tool/*_smoke.dart` | ❌ | ✅ | ✅ | ❌ |
| `integration_test/` | ✅ | ✅ | ✅ | ✅ |

### What these drivers deliberately do not re-test

An on-device driver for Module 11 sets its journey up **over HTTP** and launches
the app straight at the item screen. It does not re-drive sign-in, journey
planning or discovery.

That is not a shortcut. Those modules have their own verification, and driving
them again here would mean a Module 07 regression arriving as a Module 11
failure — a test that fails for reasons it does not name is worse than no test.
The rule is: **an on-device driver drives the module it is named after, and sets
everything else up through the API.**

Two overrides make that possible, and they are the only two:

- the **session store**, because there is no way to write a Keychain entry from
  a test process;
- the router's **initial location**.

Everything below — repositories, HTTP client, controllers, widgets — is exactly
what ships.

### Never trust a runner you have not seen fail

This layer was added with a driver that could not be run here, and an attempt to
rehearse it through `flutter drive` in a browser reported **"All tests passed."**
while executing nothing at all. Two negative controls — a truncated credential,
then no credential — both had to fail and both reported success. KI-013 in
[13-known-issues.md](13-known-issues.md) has the detail.

So the rule, which applies to every harness here and not just this one:

**Before believing a new runner, break it on purpose and watch it go red.**
Remove a credential, assert something false, point it at nothing. A harness that
cannot fail cannot pass, and a green from one is not evidence — it is the
absence of evidence, wearing evidence's clothes.

The same caution applies to what a passing browser run would mean even when the
harness works: it exercises the driver and the flow, and says nothing whatever
about Android or iOS.

---

## Time does not move during a backend test (Module 12)

`Tests\TestCase::setUp` freezes the clock at **2026-09-07 06:30 UTC** — noon in
Asia/Kolkata, on a Monday — for every backend test. A test that needs a
different moment calls `Carbon::setTestNow()` itself and says why.

This followed four failures of one shape, across three CI reds, two of them on
commits that touched no backend code. Every one was a fixture that seeded
opening hours where the assertion was about something else — an availability
string, an ordering state, a list of restaurant names — and the runner happened
to start inside the window. **A test that passes at noon and fails at 02:08 is
not flaky. It is a test with an unstated dependency**, and freezing the clock
states it.

Three greps for the pattern each missed one, because the assertions have no
textual resemblance to each other. That is the argument for fixing it at the
root rather than one file at a time.

### It must not cost the coverage it replaces

A frozen clock can buy determinism by destroying exactly the coverage that finds
real time bugs — this suite found a twenty-four-hour restaurant announcing
"closing soon" every night *because* CI ran at 23:32 local. So:

**Anything that depends on the time of day gets a test pinned to the instant
that matters.** Not "some instant" — the boundary: the last minute before
closing, the first minute of a window, the moment a threshold flips. Both
instants that broke this suite are now such tests.

Verified by reintroducing both service bugs with the suite frozen and confirming
four pinned tests still caught them. Finding a bug because CI ran in the right
half hour is a lottery; a pinned boundary test runs on every build.

---

## Module 13 — what the negative controls taught

Sixty-three controls were run against this module. Fifty-five fired. The eight
that did not are the interesting ones, and the rule that came out of them is
sharper than the one before it:

> **A control that stays silent has told you something. Find out what.**

Three of the eight silent controls were bad mutations — they had not disabled
the code they targeted, or the scenario under test could not distinguish the
mutation from the original. Those were re-run properly and fired.

The other five each exposed a real gap:

- A guard was **hygiene rather than a defence**, and its comment said otherwise.
  The comment was corrected and the mechanism that actually refuses was given a
  control of its own.
- A test's scenario agreed with the mutation, so a **sharper scenario** was
  added — the server refusing while listing nothing the client can point at.
- The widget fakes built domain objects directly, so **not one line of JSON
  parsing was covered**. A model test file was written for it.
- A fake produced data too clean to exercise the thing under test: its pickup
  options had identical instants and clock faces, so a test asserting the right
  one is rendered would have passed either way. The fake now builds them through
  the real parser from strings carrying an offset.
- One assertion is genuinely unreachable by any single-point mutation, because
  the property is guaranteed at two independent places. That is **recorded in
  the test itself** rather than left to look load-bearing.

### And what only a device could find

One defect in this module was invisible to every unit test by construction: the
chosen pickup window was reported in UTC while the options beside it were
reported in the restaurant's zone. **Each half was correct on its own.** It took
the first screen that renders both halves together — an on-device run — to make
the inconsistency visible as "12:50 am" above a list starting "6:20 am".

A test suite that only ever checks one endpoint at a time cannot see a
disagreement between two of them.
