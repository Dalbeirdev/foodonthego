# RESTART MODULE 06 — TRACEABILITY

**PASS** verified running · **PASS (tests)** automated test only · **PENDING**
environment prevents it · **BLOCKED** waiting on a client credential ·
**N/A** the provider did not produce the case.

| ID | Requirement | Web | Android | iOS | Evidence |
| --- | --- | --- | --- | --- | --- |
| RM06-001 | Route screen Web | **PASS** | — | — | `restart-m06-web-route-desktop.png` |
| RM06-002 | Route screen Android | — | PASS (tests) | — | `route_screen.dart`; no device |
| RM06-003 | Route screen iOS | — | — | **PENDING** | No Apple hardware. Not a pass |
| RM06-004 | Route calculation API | **PASS** | PASS | PASS | Driven live; 26 API tests |
| RM06-005 | Provider abstraction | **PASS** | PASS | PASS | `RouteProvider` + 3 implementations |
| RM06-006 | Google route provider | **BLOCKED** | BLOCKED | BLOCKED | Built and unit-tested; **never called** — MF-12 |
| RM06-007 | Trip ownership | **PASS** | PASS | PASS | Foreign trip → 404, live |
| RM06-008 | Origin authority | **PASS** | PASS | PASS | Taken from the trip; no client coordinates accepted |
| RM06-009 | Destination authority | **PASS** | PASS | PASS | Same |
| RM06-010 | Route status | **PASS** | PASS | PASS | NOT_CALCULATED / CALCULATING / READY / FAILED / NO_ROUTE / STALE |
| RM06-011 | Calculating state | **PASS** | PASS (tests) | PENDING | `restart-m06-route-loading.png` |
| RM06-012 | Ready state | **PASS** | PASS (tests) | PENDING | `restart-m06-web-route-desktop.png` |
| RM06-013 | Failed state | **PASS** | PASS (tests) | PENDING | `restart-m06-route-error.png` |
| RM06-014 | No-route state | **PASS** | PASS (tests) | PENDING | `restart-m06-route-no-route.png` |
| RM06-015 | Stale route state | **PASS (tests)** | PASS (tests) | PENDING | Endpoint-move invalidation, backend test |
| RM06-016 | Distance in metres | **PASS** | PASS | PASS | 236,786 m stored; "237 km" rendered |
| RM06-017 | Duration in seconds | **PASS** | PASS | PASS | 14,179 s stored; "3 hr 56 min" rendered |
| RM06-018 | Traffic duration | **N/A** | N/A | N/A | Provider returned none — MF-12 |
| RM06-019 | Traffic-availability honesty | **PASS** | PASS | PASS | `formatTrafficLine` returns null; 6 tests |
| RM06-020 | Route alternatives | **PASS (tests)** | PASS (tests) | PENDING | **NOT RETURNED BY PROVIDER** live — MF-35 |
| RM06-021 | Provider default route | **PASS** | PASS | PASS | `is_recommended` auto-selected |
| RM06-022 | Route polyline | **PASS** | PASS | PASS | 154 chars, decodes, drawn |
| RM06-023 | Origin marker | **PASS** | PASS (tests) | PENDING | 2 markers in the DOM |
| RM06-024 | Destination marker | **PASS** | PASS (tests) | PENDING | Same |
| RM06-025 | Fit bounds | **PASS** | PASS (tests) | PENDING | Drawing shaped from the route's bounds |
| RM06-026 | Web map | **PARTIAL** | — | — | Route shape ✅, **tiles ❌ — MF-08/MF-36** |
| RM06-027 | Android map | — | **BLOCKED** | — | Key wiring now exists; no key — MF-08 |
| RM06-028 | iOS map | — | — | **BLOCKED** | Same |
| RM06-029 | Route option cards | **PASS (tests)** | PASS (tests) | PENDING | Needs alternatives to see live |
| RM06-030 | Route selection API | **PASS** | PASS | PASS | Backend tests + live IDOR checks |
| RM06-031 | Single selected route | **PASS** | PASS | PASS | Unique DB index + service transaction |
| RM06-032 | Selection persistence | **PASS** | PASS (tests) | PENDING | Refresh and fresh session both keep it |
| RM06-033 | Selection concurrency | **PASS (tests)** | PASS | PASS | **Added this module** |
| RM06-034 | Route/trip mismatch | **PASS** | PASS | PASS | `ROUTE_NOT_FOUND`, live |
| RM06-035 | Route IDOR | **PASS** | PASS | PASS | 404, live |
| RM06-036 | Client metric tamper | **PASS** | PASS | PASS | All seven fields ignored, live |
| RM06-037 | Route freshness | **PASS** | PASS | PASS | 900 s; `calculated_at` unchanged on reuse |
| RM06-038 | Route cache | **PASS** | PASS | PASS | Persisted rows + freshness window |
| RM06-039 | Fresh route reuse | **PASS** | PASS | PASS | 0 billed calls across 11 revisits |
| RM06-040 | Stale recalculation | **PASS** | PASS | PASS | `?refresh=true` changed `calculated_at` |
| RM06-041 | Route version | **PASS** | PASS | PASS | `calculated_at` + endpoint fingerprint |
| RM06-042 | Trip-update invalidation | **PASS (tests)** | PASS | PASS | `invalidateIfEndpointsChanged` on every read and write |
| RM06-043 | Provider timeout | **PASS (tests)** | PASS | PASS | Its own code; backend test |
| RM06-044 | Provider quota handling | **PASS (tests)** | PASS | PASS | Backend test: no quota or key reaches the client |
| RM06-045 | API key security | **PASS** | **PASS** | **PASS** | No key of any kind in the web bundle; native wiring added |
| RM06-046 | Web key restriction | **N/A** | — | — | No key exists; the bundle holds none |
| RM06-047 | Android key restriction | — | **PENDING** | — | Wiring exists; restriction is set on the key, which does not exist |
| RM06-048 | iOS key restriction | — | — | **PENDING** | Same |
| RM06-049 | Server key restriction | **PENDING** | — | — | No routing key exists |
| RM06-050 | Travel privacy | **PASS** | PASS | PASS | No polyline or endpoint in any log |
| RM06-051 | Log privacy | **PASS** | PASS | PASS | Existing log test greps for `AIza` and endpoint names |
| RM06-052 | Offline route | **NOT IMPLEMENTED** | NOT IMPLEMENTED | NOT IMPLEMENTED | Honest message + retry — MF-30 |
| RM06-053 | Account isolation | **PASS** | PASS | PASS | Carried from Restart Module 05's verification |
| RM06-054 | Session expiry | **PASS (tests)** | PASS (tests) | PENDING | 401 clears the session |
| RM06-055 | Route cost control | **PASS** | PASS | PASS | Measured table |
| RM06-056 | Provider call count | **PASS** | — | — | 1 initial, 0 across 11 revisits |
| RM06-057 | Responsive web | **PASS** | — | — | 8 widths, 0 px overflow, map size measured |
| RM06-058 | Accessibility | **PASS** | PASS (tests) | PENDING | Keyboard-only run; every figure also in text |
| RM06-059 | Android runtime | — | **PENDING** | — | MF-27 |
| RM06-060 | iOS runtime | — | — | **PENDING** | MF-27 |
| RM06-061 | Web runtime | **PASS** | — | — | Chromium against the production build |
| RM06-062 | Backend tests | **PASS** | — | — | Full suite |
| RM06-063 | Web tests | **PASS** | — | — | 126 in the customer app |
| RM06-064 | Flutter tests | — | **PASS** | — | Including the new maps-key guard |
| RM06-065 | Provider contract test | **BLOCKED** | — | — | No Google credentials — MF-12 |
| RM06-066 | Security tests | **PASS** | PASS | PASS | IDOR, mismatch, tamper, injection, concurrency |
| RM06-067 | Database verification | **PASS** | — | — | Exactly one selected row; figures match the API |
| RM06-068 | Cache verification | **PASS** | — | — | Freshness window + its negative control |
| RM06-069 | Live screenshots | **PASS** | — | — | 10 files |
| RM06-070 | Find Food CTA | **PASS** | PASS (tests) | PENDING | `restart-m06-find-food-cta.png` |
| RM06-071 | Restaurant listing handoff | **PASS, honestly pending** | — | — | Real screen; listing is Module 07 |
| RM06-072 | Platform parity | **PASS** | — | — | `PLATFORM-PARITY.md` |
| RM06-073 | Client guide update | **PASS** | — | — | `33-customer-web-guide.md` |
| RM06-074 | Missing-feature update | **PASS** | — | — | MF-30…MF-36 |
| RM06-075 | Module 07 handoff | **PASS** | — | — | §8 of the module doc |

## Discovered requirements, not in the brief

| ID | Requirement | Status | Why it was added |
| --- | --- | --- | --- |
| RM06-076 | A Maps key must reach the native SDKs, not only Dart | **PASS** | Found in the audit: neither platform could receive one |
| RM06-077 | Customer-safe route error codes must reach the customer | **PASS** | The allow-list predated them and replaced a good message with a generic one |
| RM06-078 | The map must not shrink as the screen grows | **PASS** | The split layout started 176px too early |
| RM06-079 | The drawing must be shaped like the journey | **PASS** | A fixed panel gave a wide route a tall frame it filled a twelfth of |
| RM06-080 | A polyline decoder must be tested against the format's own fixture | **PASS** | A round trip of our own encoder passes while both halves are wrong |
