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
| 07 | Restaurant Discovery Along the Selected Route | NOT STARTED | Next, on approval |
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

Module 07 has **not** been started, per the one-module-at-a-time rule.
