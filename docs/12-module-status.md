# 12 — Module status

| # | Module | Status | Notes |
| --: | --- | --- | --- |
| 01 | Foundation, Architecture & Design System | **COMPLETE (with 3 environment blockers)** | See below |
| 02 | Customer Mobile App Shell, Navigation & Premium Home | **COMPLETE (Android/iOS device verification pending)** | 82 mobile tests; 11 states inspected live |
| 03 | Customer Authentication, Registration, OTP, Session & Security | **COMPLETE (Android/iOS device verification pending)** | 130 backend + 72 mobile tests; real Flutter→Laravel→MySQL integration run; 20 states inspected live |
| 04 | Customer Profile & Saved Addresses | **COMPLETE (Android/iOS device verification pending)** | 99 backend + 68 mobile tests; real Flutter→Laravel→MySQL integration run; 24 states inspected live |
| 05 | Trip Planner — Origin, Destination & Trip Creation | **COMPLETE (Android/iOS device verification pending; live Places verification pending)** | 408 backend + 312 mobile tests; real Flutter→Laravel→MySQL integration run (31 assertions); 28 states inspected live |
| 06 | Maps, Route Calculation, Distance & Travel Time | **NOT COMPLETE — live routing provider verification unavailable** | 527 backend + 382 mobile + 29 web tests; integration run (21 assertions); 20 states inspected live. See below |
| 07r | Restaurant Availability & Capacity (roadmap numbering) | NOT STARTED | |
| 08 | Order Lifecycle | NOT STARTED | |
| 07 | Restaurant Discovery Along the Selected Route | **NOT COMPLETE — live routing-provider detour figures unavailable** | 693 backend + 453 mobile + 29 web tests; integration run (22 assertions); 21 states inspected live. See below |
| 08 | Restaurant Search, Filters, Sorting & Discovery Ranking | NOT STARTED | Next, on approval |
| 09 | Route & Corridor Management | NOT STARTED | On-route restaurant search; the planner itself moved to 05 |
| 10 | Notifications | NOT STARTED | |
| 11 | Payments, Refunds & Settlements | NOT STARTED | |
| 12 | Restaurant Analytics | NOT STARTED | |
| 13 | Reviews & Ratings | NOT STARTED | |
| 14 | Support | NOT STARTED | |
| 15 | Platform Analytics | NOT STARTED | |
| 16 | Promotions | NOT STARTED | |
| 17 | Platform Configuration | NOT STARTED | |
| 18 | Audit & Compliance | NOT STARTED | |
| — | **ETA engine** | NOT STARTED | The core differentiator; scheduled with Module 08/09 |

## Module 01 detail

**40 of 43 requirements COMPLETE.** Three are BLOCKED by the build environment, not by design:

| ID | Requirement | Blocker |
| --- | --- | --- |
| M01-R41 | Android build validation | `dl.google.com` denied by egress policy (KI-001) |
| M01-R42 | iOS build validation | Requires macOS + Xcode; environment is Linux (KI-002) |
| M01-R43 | PHP static analysis in CI | PHPStan uninstallable via Composer here (KI-003) |

**115 automated tests pass.** All static checks pass. Both web shells and the Flutter app were run
and visually inspected.

## Module 02 detail

**30 of 32 requirements PASSED or COMPLETE.** The two blocked are M02-017 (Android) and M02-018
(iOS) — the same environment restrictions as Module 01, not code defects.

**82 mobile tests pass** (up from 19). `flutter analyze --fatal-infos` clean, `dart format` clean.
All eleven required live-view states were inspected in a rendered app. Module 01 regression: **PASS**
(67 backend + 29 web tests, both web builds).

Eight defects were found and fixed during the module; none left open.

## Module 05 detail

**48 of 51 requirements COMPLETE or PASSED.** Three are pending, none of them a
code failure: Android (KI-001), iOS (KI-002), and live Google Places verification
(KI-004 — no API key in this environment; the adapter is verified against a
stubbed transport).

The module was **reworked**. A first pass built a journey planner — departure
times, traveller counts, notes, upcoming/past/cancelled scopes — derived from the
project roadmap rather than from the specification. The specification is narrower
and different: choose an origin, choose a destination, create a trip, and stop
before anything to do with a route. The first pass was replaced rather than
extended, and the schema, the API, the models and every screen went with it.

**720 automated tests pass** (408 backend, 312 Flutter), plus 4 web. Pint clean,
`flutter analyze` clean, `dart format` clean. Modules 01–04 regression: **PASS**.

Ten defects were found and fixed during the module; none left open. Three of them
could only have been found the way they were: a list filter mismatch that no fake
repository could catch, an accessibility defect that only appeared when driving
the built app, and a spinner that never resolved when a browser left a permission
prompt unanswered.

## Module 06 detail

**66 of 70 requirements COMPLETE or PASSED.** Four are not, and none of them is a
code failure — but one of them is the module's own Definition of Done, so the
module is reported as **NOT COMPLETE**:

| ID | Requirement | Status | Blocker |
| --- | --- | --- | --- |
| M06-051 | Live Google Routes API verification | **PENDING** | KI-012 — no Routes key, and every alternative routing provider is blocked by the egress policy |
| M06-052 | Alternative-route runtime test | **NOT APPLICABLE for this test response** | The configured provider returned one route; none was fabricated |
| M06-053 | Live map SDK render | **PENDING** | KI-011 — no Maps key, no Android SDK, no macOS host |
| M06-065/066 | Android and iOS runtime verification | **PENDING** | KI-001, KI-002 |

The specification's Definition of Done requires a **real route result from a real
provider**, and that cannot be produced here. Everything around it is verified:
persistence, validation, invalidation, selection, ownership, cost control and the
screen. The one live call is not, and calling that a pass would be exactly the
kind of invention this module exists to prevent.

**938 automated tests pass** (527 backend, 382 Flutter, 29 web), plus a 21-assertion
integration run against a live server and database, and 20 live states inspected
in a rendered release build. Pint clean, `flutter analyze` clean, `dart format`
clean. Modules 01–05 regression: **PASS** (three integration runs and Module 05's
own 28-state live run, all green).

Eight defects were found and fixed during the module; none left open. Two of them
were in other modules — a Module 01 error-contract defect that answered **500**
to an unauthenticated request without a JSON `Accept` header, and a Module 03
disposal defect — and two more were in the verification harness itself, where
assertions had been quietly incapable of failing for the right reason.

## Module 07 detail

**60 of 66 requirements COMPLETE or PASSED.** Six are not, and none of them is a
code failure — but one of them touches the module's own Definition of Done, so
the module is reported as **NOT COMPLETE**:

| ID | Requirement | Status | Blocker |
| --- | --- | --- | --- |
| M07-055 | Live routing-provider detour figures | **PENDING** | KI-012 — no Routes key, so the detour is measured against a straight-line road network |
| M07-056 | Alternative-route discovery | **NOT APPLICABLE for this test response** | Discovery reads the selected route by construction; the provider returns one route, so there is no alternative to select |
| M07-057 | Live map render with markers | **PENDING** | KI-011 — no Maps key, no Android SDK, no macOS host |
| M07-058 | Marker clustering | **NOT IMPLEMENTED** | A deliberate scope decision at a 25-result limit, documented in `22-*.md` |
| M07-044/045 | Android and iOS runtime verification | **PENDING** | KI-001, KI-002 |

The consequence worth stating plainly: the detour is the number this product
turns on, and with a straight-line road network every in-corridor stop costs
almost nothing to reach — the largest detour the live run produced for a stop
ahead was four seconds. The *rule* is verified (`RestaurantDiscoveryServiceTest`
excludes a restaurant 400 m from the road with an eighteen-minute detour), the
*arithmetic* is verified, and the pipeline around it is verified against real
route geometry. What is not verified is a real road-network detour, and calling
that a pass would be the exact fabrication this module exists to prevent.

**1 175 automated tests pass** (693 backend, 453 Flutter, 29 web), plus a
22-assertion integration run against a live server, real restaurant rows and
Module 06's real stored geometry, and 21 live states inspected in a rendered
release build. Pint clean, `flutter analyze` clean, `dart format` clean. Modules
01–06 regression: **PASS**.

Seven defects were found and fixed during the module; none left open. Two could
only have been found by driving the built app through its semantics tree — a
screen reader was being told "0 m ahead" about a restaurant the screen labelled
"Behind you", and price level was conveyed by rupee symbols alone. Two more were
faults in the *tests*: a fixture that inherited a factory default nobody had
chosen, and a fixture placed so far from the route that the rule it existed to
prove never ran.

Module 08 has **not** been started, per the one-module-at-a-time rule.

---

## Module 08 — Restaurant Search, Filters, Sorting & Discovery Ranking

**Status: COMPLETE**, with two runtime verifications honestly pending.

| Item | Status | Note |
| --- | --- | --- |
| Search (name, cuisine, city) | **PASS** | Scored relevance tiers, Unicode-safe normalisation |
| Cuisine / facility / price / availability filters | **PASS** | Slug-based, OR within cuisine and price, AND within facilities |
| Maximum detour filter | **PASS** (arithmetic) | Cannot exclude at runtime under `ROUTE_PROVIDER=development` — KI-012 |
| Distance-ahead filter | **PASS** | |
| Rating filter | **DEFERRED, honestly** | No reviews module; `rating_available: false`, no control rendered, nothing invented |
| `highest_rated` sort | **NOT AVAILABLE** | Refused with a reason rather than silently downgraded |
| Recommended / lowest detour / soonest / price sorts | **PASS** | |
| Ranking weights centralised | **PASS** | `config/foodonthego.php`, env-overridable |
| Filter draft state, chips, badge, clear-all | **PASS** | |
| Filtered-empty vs search-empty vs empty-road | **PASS** | Three screens, three ways out |
| Map/list consistency | **PASS** | One result set drives both |
| Pagination and reset-on-change | **PASS** | |
| Cache keyed on route, normalised, invalidated on status change | **PASS** | |
| Cost control — no provider call on a filter change | **PASS** | Counted, not assumed |
| SQL injection, validation, sort allow-list, array limits | **PASS** | |
| Android runtime | **PENDING** | KI-001 — no Android SDK; `dl.google.com` blocked |
| iOS runtime | **PENDING** | KI-002 — no macOS host |
| Live map render | **PENDING** | KI-011 — no Maps key |

**1 280 automated tests pass** (741 backend, 539 Flutter), plus a 28-check
integration run against a live server and real MySQL rows, 28 live states
inspected in a rendered release build, and Modules 01–07 regression green
(13 + 24 + 31 + 21 + 22 integration checks across five smoke runs).

Five defects were found and fixed; none left open. Two of them — a ranking score
that was silently zero for every restaurant, and a filter button that announced
a bare "Filters" over a filtered list — could only be found by running the thing
and reading what it actually produced.

Module 09 has **not** been started, per the one-module-at-a-time rule.

---

## Module 09 — Restaurant Details, Facilities, Availability & Customer Preview

**Status: COMPLETE**, with two runtime verifications honestly pending.

| Item | Status | Note |
| --- | --- | --- |
| Detail API, route-aware | **PASS** | Nested under the trip; no route id to substitute |
| Eligibility on a direct uuid | **PASS** | Suspended, pending, disabled, permanently closed all 404 |
| Suspended and missing share a status | **PASS** | So a uuid list cannot enumerate suspensions |
| Outside-route told apart | **PASS** | 409, because the customer's next move differs |
| Customer-safe response | **PASS** | Raw-body assertion over 16 needles |
| Read-only | **PASS** | Four verbs, none accepted |
| Media, with moderation gate | **PASS** | `is_active` defaults false; relation filters it |
| Gallery, fallback, load failure | **PASS** | Branded stand-in, never a broken icon |
| Description / facilities / price / rating | **PASS** | Each omitted where absent; **New**, never 0.0 |
| Availability: open, paused, closed, gone, unknown | **PASS** | Five states, five buttons |
| Opening hours: normal, split, overnight, closed day | **PASS** | Overnight at 01:00 verified live |
| Timezone, and DST-capable zones | **PASS** | Restaurant's zone from server time |
| Next opening | **PASS** | Eight-day lookahead; silent rather than guessing |
| Route context reuse | **PASS** | Same objects as the card; 10 of 10 opens from cache |
| No provider call on open | **PASS** | Structural — the only caller is already cached |
| No N+1 | **PASS** | Query count unchanged by 20 photographs and 15 more restaurants |
| Discovery state on return | **PASS** | Search, filters, sort, view — and zero requests |
| Request race | **PASS** | Generation-checked; the newest wins |
| Offline, with real age | **PASS** | Except a withdrawn restaurant, which loses its page |
| Android runtime | **PENDING** | KI-001 — no Android SDK |
| iOS runtime | **PENDING** | KI-002 — no macOS host |
| Live map render | **PENDING** | KI-011 — no Maps key |

**1 414 automated tests pass** (801 backend, 613 Flutter), plus a 25-check
integration run against a live server, 25 live states inspected in a rendered
release build, and Modules 01–08 regression green across six smoke runs.

One defect was found and fixed, and it could only have been found by reading the
running app's semantics tree: the discovery card was a single merged node, so
the **View** button had no node at all and a screen-reader user could not open a
restaurant's page.

Module 10 has **not** been started, per the one-module-at-a-time rule.
