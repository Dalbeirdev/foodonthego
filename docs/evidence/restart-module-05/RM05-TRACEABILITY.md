# RESTART MODULE 05 — TRACEABILITY

Every requirement the brief numbered, and what was actually verified.

Legend: **PASS** verified running · **PASS (tests)** verified by automated test
only · **PENDING** environment prevents verification · **BLOCKED** waiting on a
credential the client must supply · **PARTIAL** some of it.

| ID | Requirement | Web | Android | iOS | Evidence |
| --- | --- | --- | --- | --- | --- |
| RM05-001 | Trip Planner Web | **PASS** | — | — | Driven in a browser; `restart-m05-web-trip-planner-desktop.png` |
| RM05-002 | Trip Planner Android | — | PASS (tests) | — | `mobile/lib/features/trips/trip_planner_screen.dart`, `trip_planner_test.dart`. No device. |
| RM05-003 | Trip Planner iOS | — | — | **PENDING** | No Apple hardware reachable. Not a pass. |
| RM05-004 | Plan Journey CTA | **PASS** | PASS (tests) | PENDING | Clicked from Home in the live run; lands on `/trips/plan` |
| RM05-005 | Origin selector | **PASS** | PASS (tests) | PENDING | Three sources offered |
| RM05-006 | Destination selector | **PASS** | PASS (tests) | PENDING | Two sources; current location deliberately not offered |
| RM05-007 | Saved-address source | **PASS** | PASS (tests) | PENDING | `restart-m05-web-saved-address.png` |
| RM05-008 | HOME selection | **PASS** | PASS (tests) | PENDING | Created live, selected live, submitted as `saved_address_id` |
| RM05-009 | WORK selection | **PASS** | PASS (tests) | PENDING | Same |
| RM05-010 | OTHER selection | **PASS (tests)** | PASS (tests) | PENDING | `TripPlannerScreen.test.tsx` — the label case; live run used Home/Work |
| RM05-011 | Current location | **PASS** | PASS (tests) | PENDING | Controlled fix 28.6129, 77.2295 → "New Delhi" |
| RM05-012 | Web geolocation | **PASS** | — | — | Granted, blocked, insecure, unsupported, timeout, no-response |
| RM05-013 | Android permission | — | PASS (tests) | — | `location_service.dart`; no device to grant or deny on |
| RM05-014 | iOS permission | — | — | **PENDING** | — |
| RM05-015 | Permission denied | **PASS** | PASS (tests) | PENDING | `restart-m05-location-permission-denied.png`; saved places and search stay available |
| RM05-016 | Service disabled | **PASS** | PASS (tests) | PENDING | Reported as `position-unavailable` with its own copy |
| RM05-017 | Place search | **PASS** | PASS (tests) | PENDING | `restart-m05-web-place-search.png` |
| RM05-018 | Place-search provider | **PASS** | PASS | PASS | `PlaceProvider` + 3 implementations. Google's own API **never called** — MF-29 |
| RM05-019 | Search debounce | **PASS** | PASS (tests) | PENDING | 350 ms. 10 characters → 1 request, measured |
| RM05-020 | Provider session token | **PASS** | PASS (tests) | PENDING | One per search; reused for details; rotated on selection |
| RM05-021 | Place suggestions | **PASS** | PASS (tests) | PENDING | Live, with loading, empty, error |
| RM05-022 | Place details | **PASS** | PASS (tests) | PENDING | 1 call per selection, measured |
| RM05-023 | Place coordinates | **PASS** | PASS (tests) | PENDING | From details, never from the suggestion |
| RM05-024 | Place id | **PASS** | PASS (tests) | PENDING | Stored on the trip |
| RM05-025 | API key security | **PASS** | PARTIAL | PARTIAL | Web bundle has **no** provider key at all. Android/iOS have no Maps key — MF-08 |
| RM05-026 | Origin normalisation | **PASS** | PASS | PASS | `LocationSelection` / `App\Support\Trip\LocationSelection` |
| RM05-027 | Destination normalisation | **PASS** | PASS | PASS | Same |
| RM05-028 | Source type | **PASS** | PASS | PASS | Explicit, never inferred from labels |
| RM05-029 | Same-location validation | **PASS** | PASS (tests) | PENDING | Client greys the CTA; server refuses with `SAME_LOCATION`. Both driven |
| RM05-030 | Coordinate validation | **PASS** | PASS | PASS | lat 999 → `VALIDATION_FAILED`; (0,0) → `INVALID_COORDINATES` |
| RM05-031 | Saved-address ownership | **PASS** | PASS | PASS | Ananya + Rahul's id → `ADDRESS_NOT_FOUND`, same 404 as nonexistent |
| RM05-032 | Coordinate-tamper protection | **PASS** | PASS | PASS | Mumbai coords with a Delhi address id: stored as Delhi. Plus the control |
| RM05-033 | Trip create API | **PASS** | PASS | PASS | `POST /api/v1/customer/trips` |
| RM05-034 | Trip customer ownership | **PASS** | PASS | PASS | `customer_id` in the body ignored; foreign read 404 |
| RM05-035 | Trip status | **PASS** | PASS | PASS | `ROUTE_PENDING` on create |
| RM05-036 | Route status pending | **PASS** | PASS | PASS | `NOT_CALCULATED`; rendered in words |
| RM05-037 | Trip idempotency | **PASS** | PASS | PASS | Replay → same id + `Idempotency-Replayed: true`. Control: no key → two trips |
| RM05-038 | Double submit | **PASS** | PASS (tests) | PENDING | Double click produced one POST; the CTA disables while in flight |
| RM05-039 | Lost response | **PASS (tests)** | PASS | PASS | Key reused across a failed attempt and its retry; server-side replay driven live |
| RM05-040 | Route handoff | **PASS** | PASS (tests) | PENDING | `/trips/{id}`, id only, screen reloads from the server |
| RM05-041 | Trip persistence | **PASS** | PASS (tests) | PENDING | Reloaded the handoff URL; the journey is still there |
| RM05-042 | Trips tab integration | **PASS** | PASS (tests) | PENDING | `restart-m05-web-trips-tab.png` |
| RM05-043 | Home active trip | **PASS** | PASS (tests) | PENDING | CTA href is the real trip id — the `uuid`/`id` bug, MF-23 |
| RM05-044 | Account switch isolation | **PASS** | PASS (tests) | PENDING | Sign out → sign in as Ananya: empty planner, no saved places, her trips only |
| RM05-045 | Offline state | **PASS** | PASS (tests) | PENDING | `restart-m05-web-offline.png` — a connection message, not a server error |
| RM05-046 | Session expiry | **PASS** | PASS (tests) | PENDING | 401 mid-search → token cleared, `/login`, no anonymous trip |
| RM05-047 | Location privacy | **PASS** | PASS | PASS | No origin/destination in any operator or analytics surface |
| RM05-048 | Log privacy | **PASS** | PASS | PASS | Place identifier leak found and fixed — MF-25 |
| RM05-049 | Provider cost control | **PASS** | PASS (tests) | PENDING | Measured table in the module doc |
| RM05-050 | Zero route calls during creation | **PASS** | PASS | PASS | 0 routing calls, 0 Razorpay |
| RM05-051 | Responsive web | **PASS** | — | — | 8 widths, planner and picker, 0 px overflow, negative-controlled |
| RM05-052 | Accessibility | **PASS** | PASS (tests) | PENDING | Keyboard-only run; combobox semantics; 44 px targets; reduced motion |
| RM05-053 | Android runtime | — | **PENDING** | — | No SDK or emulator — MF-27 |
| RM05-054 | iOS runtime | — | — | **PENDING** | No Apple hardware — MF-27 |
| RM05-055 | Web runtime | **PASS** | — | — | Chromium 1194 against the real API |
| RM05-056 | Backend tests | **PASS** | — | — | 1,344 tests |
| RM05-057 | Web tests | **PASS** | — | — | 74 in the customer app |
| RM05-058 | Flutter tests | — | **PASS** | — | 1,063 |
| RM05-059 | Security tests | **PASS** | PASS | PASS | IDOR, injection, tamper, idempotency, plus two negative controls |
| RM05-060 | Provider tests | **PASS (tests)** | — | — | `PlaceProviderTest`, `PlaceApiTest`. Google itself untested — MF-29 |
| RM05-061 | Live screenshots | **PASS** | — | — | 27 files in this directory |
| RM05-062 | Platform parity | **PASS** | — | — | `PLATFORM-PARITY.md` |
| RM05-063 | Client guide update | **PASS** | — | — | "Planning a journey" added |
| RM05-064 | Missing-feature update | **PASS** | — | — | MF-21…MF-29 |
| RM05-065 | Module 06 handoff | **PASS** | — | — | §8 of the module doc |

## Discovered requirements, not in the brief

| ID | Requirement | Status | Why it was added |
| --- | --- | --- | --- |
| RM05-066 | A location request must end even when the browser never answers | **PASS** | Found live: blocked geolocation calls neither callback and ignores its own timeout |
| RM05-067 | Reverse geocoding must not be discarded by the picker closing | **PASS** | Found live: the call was paid for and the label thrown away |
| RM05-068 | A hook must not require callers to memoise a callback | **PASS** | Found by the test harness: an inline arrow produced an infinite render loop |
| RM05-069 | A list screen must survive a payload that is not a list | **PASS** | Found by a stubbed test: `.map` threw and the tab went blank |
| RM05-070 | The customer web app must have a favicon | **PASS** | A permanent 404 in the live console |
| RM05-071 | A page heading must not be clipped by the viewport edge | **PASS** | Found in the screenshots: the shell had no top padding |
| RM05-072 | A disabled button must look disabled and stay legible | **PASS** | White on pale orange, ~2:1, on the state customers see most |
| RM05-073 | Saved addresses must be creatable in a browser | **PASS** | Restart Module 04's web gap; without it the mandatory saved-address integration is unreachable |
