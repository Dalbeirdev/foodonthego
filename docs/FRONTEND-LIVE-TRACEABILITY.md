# FRONTEND LIVE TRACEABILITY

Restart Module 01. Commit `b49dcb4`.

## The rule this table enforces

**A feature is not COMPLETE until it is visible and usable in the running
application.**

Backend complete ≠ complete. API complete ≠ complete. A component in the source
tree ≠ complete. Passing tests ≠ complete. COMPLETE requires all of:
**code + API + UI + navigation + live view + test + screenshot.**

Customer Web, Android and iOS are one codebase (`mobile/`), so the three customer
columns are filled from the same routes. "Live" means seen running in this audit.

| ID | Feature | Backend | API | Cust. Web | Android | iOS | Rest. Web | Admin Web | Live route | Screenshot | Test | Status | Missing reason | Next module |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M01-1 | API foundation, envelope, correlation ids | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `/api/v1/*` | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M01-2 | System health page | ✔ | ✔ | n/a | n/a | n/a | n/a | ✔ | `/admin/system-health` | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M01-3 | Web design system (`@fotg/ui`) | n/a | n/a | n/a | n/a | n/a | ✔ | ✔ | both shells | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M01-4 | Mobile design system / theme | n/a | n/a | ✔ | ✔ | ✔ | n/a | n/a | all | ✔ | ✔ | **PARTIALLY IMPLEMENTED** | No bundled font — MF-01 | R-01 follow-up |
| M01-5 | Responsive foundation ≥1024 | n/a | n/a | ✖ | n/a | n/a | ✔ | ✔ | `/` | ✔ | ✖ | **MISSING** | Phone layout stretched — MF-02 | R-02 |
| M02-1 | Customer shell + bottom navigation | n/a | n/a | ✔ | ✔ | ✔ | n/a | n/a | `/` | ✔ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven end to end | R-02 |
| M02-2 | Home screen | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/` | ✔ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Signed-in home not photographed | R-02 |
| M03-1 | Phone + OTP sign-in | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/auth/phone` → `/auth/otp` | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M03-2 | SMS delivery | ✔ | ✔ | n/a | n/a | n/a | n/a | n/a | — | — | ✔ | **BLOCKED** | No Twilio credentials / DLT — MF-09 | client |
| M04-1 | Profile | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/profile` | ✔ (guard) | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven signed-in | R-04 |
| M04-2 | Saved addresses | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/profile` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-04 |
| M05-1 | Trip planner | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/trips/plan` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-05 |
| M06-1 | Route calculation | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/trips/:id/route` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-06 |
| M06-2 | Map tiles | n/a | n/a | ✖ | ✖ | ✖ | n/a | n/a | — | ✖ | n/a | **BLOCKED** | No Maps API key — MF-08 | client |
| M06-3 | Traffic-aware duration | ✖ | ✖ | n/a | n/a | n/a | n/a | n/a | — | ✖ | ✔ | **BLOCKED** | No routing provider — MF-12 | client |
| M07-1 | Restaurant listing along route | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/route/restaurants` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-07 |
| M08-1 | Search, filters, sort | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/restaurants` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-08 |
| M09-1 | Restaurant details | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/restaurants/:id` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-09 |
| M10-1 | Menu browsing | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/menu` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-10 |
| M11-1 | Item detail, variants, addons, add to cart | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/menu/items/:id` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-11 |
| M12-1 | Cart + revalidation | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/trips/:id/cart` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-12 |
| M13-1 | Pickup time | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/cart/pickup` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-13 |
| M14-1 | Checkout + commercial calculation | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/checkout` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-14 |
| M14T-1 | Tenant isolation | ✔ | ✔ | n/a | n/a | n/a | ✖ | ✖ | `/api/v1/restaurant/*` | ✖ | ✔ | **BACKEND ONLY** | No operator UI — MF-07 | R-Ops |
| M15-1 | Razorpay payment | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/payment` | ✖ | ✔ | **BLOCKED** | No credentials — MF-10 | client |
| M16-1 | Order confirmation, number, pickup code | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/orders/:id/confirmation` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-16 |
| M16-2 | Pickup **QR** | ✖ | ✖ | ✖ | ✖ | ✖ | n/a | n/a | — | ✖ | ✖ | **MISSING** | A pickup *code* exists; no QR is generated anywhere | R-16 |
| M17-1 | Order tracking + timeline | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/orders/:id/track` | ✖ | ✔ | **PARTIALLY IMPLEMENTED** | Nothing can advance state — MF-11 | R-17 |
| M18-1 | ETA engine | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ | — | ✖ | ✖ | **NOT YET SCHEDULED** | Never specified, never started — MF-03 | R-18 |
| OPS-1 | Staff sign-in | ✖ | ✖ | n/a | n/a | n/a | ✖ | ✖ | — | ✖ | ✖ | **MISSING** | MF-04 | R-Ops |
| OPS-2 | Restaurant dashboard, 11 areas | ✖ | partial | n/a | n/a | n/a | ✖ | n/a | `/restaurant/*` | ✔ (placeholders) | ✖ | **MISSING** | 0 of 11 implemented — MF-05 | R-Ops |
| OPS-3 | Admin panel, 13 remaining areas | ✖ | partial | n/a | n/a | n/a | n/a | ✖ | `/admin/*` | ✔ (placeholders) | ✖ | **MISSING** | 1 of 14 implemented — MF-06 | R-Ops |

## Newly discovered in this audit

**M16-2 — the pickup QR does not exist.** The brief lists "Pickup QR generation"
under Module 16, and Module 16 was reported complete. A pickup *credential* is
generated, hashed and served by `/api/v1/customer/orders/{order}/pickup-credential`
— but nothing renders it as a QR code, on any platform, and no QR library is a
dependency of the mobile app. This was not previously recorded as missing.

## Restart Module 02 — Customer Home & Navigation

Customer Web is now `web/apps/customer` (React). Flutter builds Android and iOS.
The Web column is from screenshots taken in this module; Android and iOS are from
CI, and are not claimed as live inspection.

| ID | Requirement | Web | Android | iOS | Live route | Screenshot | Test | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RM02-001 | Customer Web shell | ✔ | n/a | n/a | `/` | ✔ | ✔ | **VERIFIED COMPLETE** |
| RM02-002 | Flutter shell | n/a | ✔ | ✔ | `/` | ✖ | ✔ | AUDITED, NOT REBUILT — device inspection pending |
| RM02-003 | Authenticated root | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-004 | Home — Web | ✔ | — | — | `/` | ✔ | ✔ | **VERIFIED COMPLETE** |
| RM02-005 | Home — Android | — | ✔ | — | `/` | ✖ | ✔ | IMPLEMENTED, DEVICE VERIFICATION PENDING |
| RM02-006 | Home — iOS | — | — | ✔ | `/` | ✖ | ✔ | **IOS TEST PENDING** |
| RM02-007 | Web primary navigation | ✔ | n/a | n/a | all | ✔ | ✔ | **VERIFIED COMPLETE** |
| RM02-008 | Mobile bottom navigation | ✔ | ✔ | ✔ | all | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-009 | Active nav state | ✔ | ✔ | ✔ | all | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-010 | Home greeting | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — "Good afternoon, Rahul" from the live API |
| RM02-011 | Journey CTA | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-012 | Journey CTA navigation | ✔ | ✔ | ✔ | `/trips/plan` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — route exists; content is Restart Module 05 |
| RM02-013 | Active trip | ✔ | ✔ | ✔ | `/` | ✖ | ✔ | IMPLEMENTED — no live journey existed to photograph |
| RM02-014 | Active trip empty state | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-015 | Active order | ✔ | ✔ | ✔ | `/` | ✖ | ✔ | IMPLEMENTED — no live order existed to photograph |
| RM02-016 | Active order empty behaviour | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — section absent, not an empty card |
| RM02-017 | Trips entry | ✔ | ✔ | ✔ | `/trips` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-018 | Orders entry | ✔ | ✔ | ✔ | `/orders` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-019 | Notifications entry | ✔ | ✔ | ✔ | `/notifications` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-020 | Profile entry | ✔ | ✔ | ✔ | `/profile` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** |
| RM02-021 | Authentication guard | ✔ | ✔ | ✔ | all | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — route-level, not nav-level |
| RM02-022 | No auth flash | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — 0 API calls while anonymous |
| RM02-023 | Session expiry | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **PARTIAL** — a rejected token shows the error state; automatic sign-out on 401 is Restart Module 03 |
| RM02-024 | Browser refresh on protected routes | ✔ | n/a | n/a | all | ✔ | ✔ | **VERIFIED COMPLETE** — SPA fallback returns 200, not 404 |
| RM02-025 | Direct protected route | ✔ | n/a | n/a | `/orders` | ✔ | ✔ | **VERIFIED COMPLETE** — anonymous deep link lands on `/login` |
| RM02-026 | Android system back | — | ✔ | — | all | ✖ | ✔ | **PENDING — no device** |
| RM02-027 | iOS navigation | — | — | ✔ | all | ✖ | ✔ | **IOS TEST PENDING** |
| RM02-028 | Tab state | ✔ | ✔ | ✔ | all | ✔ | ✔ | Flutter uses `StatefulShellRoute.indexedStack`; Web re-renders per route by design |
| RM02-029 | Home loading | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — skeleton, not a blank screen |
| RM02-030 | Home error | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — CTA survives the failure |
| RM02-031 | Home refresh | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE (Web)** — Try again re-requests |
| RM02-032 | Offline state | ✖ | ✔ | ✔ | `/` | ✖ | ✖ | **MISSING on Web** — a network failure renders the error state; no cached view |
| RM02-033 | Account isolation | ✔ | ✔ | ✔ | `/` | ✖ | ✔ | Home is derived from the token; no id is accepted |
| RM02-034 | Role isolation | ✔ | ✔ | ✔ | `/` | ✖ | ✔ | `role:customer` on the route group |
| RM02-035 | Home API efficiency | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE** — exactly 1 request, measured |
| RM02-036 | Google cost control | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE** — 0 calls, asserted by a failing double |
| RM02-037 | Razorpay cost control | ✔ | ✔ | ✔ | `/` | ✔ | ✔ | **VERIFIED COMPLETE** — 0 calls |
| RM02-038…045 | Responsive 360→1920 | ✔ | n/a | n/a | `/` | ✔ | ✖ | **VERIFIED COMPLETE** — all eight captured |
| RM02-046 | Accessibility | ✔ | ? | ? | all | ✔ | partial | **PARTIAL** — keyboard and semantics verified; no screen-reader run |
| RM02-047 | Keyboard navigation | ✔ | n/a | n/a | all | ✔ | ✖ | **VERIFIED COMPLETE** — tab order captured |
| RM02-048 | Android live view | — | ✖ | — | — | ✖ | — | **PENDING — environment** |
| RM02-049 | iOS live view | — | — | ✖ | — | ✖ | — | **PENDING — environment** |
| RM02-050 | Web live view | ✔ | — | — | all | ✔ | — | **VERIFIED COMPLETE** |
| RM02-051 | Screenshot evidence | ✔ | ✖ | ✖ | — | ✔ | — | 19 Web captures; none for Android or iOS |
| RM02-052 | Console audit | ✔ | n/a | n/a | all | ✔ | — | **VERIFIED COMPLETE** — zero console errors on every screen |
| RM02-053 | Flutter runtime audit | — | ✖ | ✖ | — | ✖ | — | **PENDING — no device** |
| RM02-054 | Backend tests | ✔ | ✔ | ✔ | — | — | ✔ | 1341 passed |
| RM02-055 | Web tests | ✔ | — | — | — | — | ✔ | 46 passed (13 new) |
| RM02-056 | Flutter tests | — | ✔ | ✔ | — | — | ✔ | 1065 passed |
| RM02-057 | Platform parity | ✔ | ✔ | ? | — | partial | ✔ | Web verified live; mobile by CI |
| RM02-058 | Missing feature update | ✔ | — | — | — | — | — | MF-01, MF-02 closed; MF-17, MF-18 added |
| RM02-059 | Flow documentation | ✔ | — | — | — | — | — | Updated |
| RM02-060 | Restart Module 03 handoff | ✔ | — | — | — | — | — | See the report |

## Restart Module 03 — Customer Authentication

Web verified live in this module. Android and iOS were not inspected by a person;
their entries come from CI and from the unchanged Flutter implementation.

| ID | Requirement | Web | Android | iOS | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| RM03-001 | Web login | ✔ | n/a | n/a | screenshot | **VERIFIED COMPLETE** |
| RM03-002 | Android login | n/a | ✔ | n/a | CI integration tests | IMPLEMENTED, DEVICE PENDING |
| RM03-003 | iOS login | n/a | n/a | ✔ | CI simulator | **IOS TEST PENDING** |
| RM03-004 | Phone input | ✔ | ✔ | ✔ | `type=tel`, `inputmode=numeric` | **VERIFIED COMPLETE (Web)** |
| RM03-005 | Country code | ✔ | ✔ | ✔ | `+91` shown, architecture not India-only | **PARTIAL** — no country picker yet |
| RM03-006 | Phone normalization | ✔ | ✔ | ✔ | backend test: every written form reaches one account | **VERIFIED COMPLETE** |
| RM03-007 | E.164 storage | ✔ | ✔ | ✔ | `users.phone_e164` UNIQUE | **VERIFIED COMPLETE** |
| RM03-008 | OTP request API | ✔ | ✔ | ✔ | live | **VERIFIED COMPLETE** |
| RM03-009 | Secure generation | — | — | — | `random_int` per digit | **VERIFIED COMPLETE** |
| RM03-010 | Hash storage | — | — | — | HMAC-SHA256; 64-hex in the database | **VERIFIED COMPLETE** |
| RM03-011 | TTL | — | — | — | 300 s, configurable | **VERIFIED COMPLETE** |
| RM03-012 | Resend delay | ✔ | ✔ | ✔ | 30 s, server-supplied countdown | **VERIFIED COMPLETE** |
| RM03-013 | Request rate limit | — | — | — | 5/number, 20/IP per hour | **VERIFIED COMPLETE** |
| RM03-014 | Attempt limit | — | — | — | 5, backend test | **VERIFIED COMPLETE** |
| RM03-015 | Challenge record | — | — | — | `otp_challenges` | **VERIFIED COMPLETE** |
| RM03-016 | Challenge/phone binding | — | — | — | backend test | **VERIFIED COMPLETE** |
| RM03-017 | Verify API | ✔ | ✔ | ✔ | live | **VERIFIED COMPLETE** |
| RM03-018 | Invalid OTP | ✔ | ✔ | ✔ | live screenshot | **VERIFIED COMPLETE (Web)** |
| RM03-019 | Expired OTP | — | ✔ | ✔ | backend test; web unit test | **VERIFIED COMPLETE** |
| RM03-020 | Replay protection | — | — | — | `consumed_at`; backend test | **VERIFIED COMPLETE** |
| RM03-021 | Brute force | — | — | — | attempts + rate limit | **VERIFIED COMPLETE** |
| RM03-022 | Existing customer | ✔ | ✔ | ✔ | live — straight Home | **VERIFIED COMPLETE (Web)** |
| RM03-023 | New customer detection | ✔ | ✔ | ✔ | live — registration step | **VERIFIED COMPLETE (Web)** |
| RM03-024 | Registration Web | ✔ | — | — | live screenshot | **VERIFIED COMPLETE** |
| RM03-025 | Registration Android | — | ✔ | — | CI | DEVICE PENDING |
| RM03-026 | Registration iOS | — | — | ✔ | CI | **IOS TEST PENDING** |
| RM03-027 | Unique phone | — | — | — | DB constraint; verified no duplicates | **VERIFIED COMPLETE** |
| RM03-028 | Registration race | — | — | — | backend test | **VERIFIED COMPLETE** |
| RM03-029 | Verified phone read-only | ✔ | ✔ | ✔ | not editable, not submitted; web test | **VERIFIED COMPLETE** |
| RM03-030 | Role assignment | — | — | — | server-assigned; `role=customer` in DB | **VERIFIED COMPLETE** |
| RM03-031 | Status ACTIVE | ✔ | ✔ | ✔ | live | **VERIFIED COMPLETE** |
| RM03-032 | Status SUSPENDED | ✖ | ✔ | ✔ | backend test only — **not seen on screen** | **PARTIAL — MF-19** |
| RM03-033 | Status DISABLED | ✖ | ✔ | ✔ | backend test only | **PARTIAL — MF-19** |
| RM03-034 | Deleted policy | — | — | — | not defined | **MISSING** |
| RM03-035 | Session creation | ✔ | ✔ | ✔ | Sanctum, ability-scoped | **VERIFIED COMPLETE** |
| RM03-036 | Web session security | ✔ | n/a | n/a | sessionStorage; Authorization header only | **PARTIAL — see MF-18 note** |
| RM03-037 | Mobile secure storage | n/a | ✔ | ✔ | `flutter_secure_storage` | **VERIFIED COMPLETE** |
| RM03-038 | Session restore Web | ✔ | — | — | live refresh | **VERIFIED COMPLETE** |
| RM03-039 | Session restore Android | — | ✔ | — | CI | DEVICE PENDING |
| RM03-040 | Session restore iOS | — | — | ✔ | CI | **IOS TEST PENDING** |
| RM03-041 | `/customer/me` | ✔ | ✔ | ✔ | backend test | **VERIFIED COMPLETE** |
| RM03-042 | Auth route guard | ✔ | ✔ | ✔ | live, route-level | **VERIFIED COMPLETE** |
| RM03-043 | No auth flash | ✔ | ✔ | ✔ | 0 API calls while anonymous | **VERIFIED COMPLETE** |
| RM03-044 | Session expiry | ✔ | ✔ | ✔ | live — forged token cleared | **VERIFIED COMPLETE (Web)** |
| RM03-045 | Central 401 handling | ✔ | ✔ | ✔ | one handler, not per screen | **VERIFIED COMPLETE** |
| RM03-046 | Logout API | ✔ | ✔ | ✔ | live | **VERIFIED COMPLETE** |
| RM03-047 | Logout local cleanup | ✔ | ✔ | ✔ | token cleared; back does not reopen Home | **VERIFIED COMPLETE (Web)** |
| RM03-048 | Account switching | ✔ | ✔ | ✔ | live — no name leaked between customers | **VERIFIED COMPLETE (Web)** |
| RM03-049 | Role isolation | — | — | — | backend tests, both directions | **VERIFIED COMPLETE** |
| RM03-050 | Open redirect | ✔ | n/a | n/a | only `/`-prefixed internal paths | **VERIFIED COMPLETE** |
| RM03-051 | No production bypass | — | — | — | three defences, each tested | **VERIFIED COMPLETE** |
| RM03-052 | OTP logging | — | — | — | 0 in the application log | **VERIFIED COMPLETE** |
| RM03-053 | Token logging | — | — | — | 0 | **VERIFIED COMPLETE** |
| RM03-054 | Enumeration | — | — | — | backend test: identical response either way | **VERIFIED COMPLETE** |
| RM03-055 | Network failure | ✔ | ✔ | ✔ | offline message; no fake success | **VERIFIED COMPLETE** |
| RM03-056 | Device clock independence | ✔ | ✔ | ✔ | server owns expiry and resend | **VERIFIED COMPLETE** |
| RM03-057 | Android OTP autofill | — | ✔ | — | `autocomplete=one-time-code`; no READ_SMS | DEVICE PENDING |
| RM03-058 | iOS OTP autofill | — | — | ✔ | same attribute | **IOS TEST PENDING** |
| RM03-059 | Accessibility | ✔ | ? | ? | labels, `role=alert`, focus rings, 48px targets | **PARTIAL** — no screen-reader run |
| RM03-060 | Responsive | ✔ | n/a | n/a | eight widths, no overflow | **VERIFIED COMPLETE** |
| RM03-061 | Backend tests | ✔ | ✔ | ✔ | 1341 | **VERIFIED COMPLETE** |
| RM03-062 | Web tests | ✔ | — | — | 61 (28 customer) | **VERIFIED COMPLETE** |
| RM03-063 | Flutter tests | — | ✔ | ✔ | 1065 | **VERIFIED COMPLETE** |
| RM03-064 | Security tests | ✔ | ✔ | ✔ | see above | **VERIFIED COMPLETE** |
| RM03-065 | Live Web verification | ✔ | — | — | 19 screenshots | **VERIFIED COMPLETE** |
| RM03-066 | Live Android verification | — | ✖ | — | — | **PENDING — environment** |
| RM03-067 | Live iOS verification | — | — | ✖ | — | **PENDING — environment** |
| RM03-068 | Screenshot evidence | ✔ | ✖ | ✖ | Web only | **PARTIAL** |
| RM03-069 | Platform parity | ✔ | ✔ | ? | Web live, mobile by CI | **PARTIAL** |
| RM03-070 | Review credential documentation | ✔ | ✔ | ✔ | no fake credentials; log-read procedure | **VERIFIED COMPLETE** |
| RM03-071 | Client guide update | ✔ | — | — | module document | **VERIFIED COMPLETE** |
| RM03-072 | Missing feature update | ✔ | — | — | MF-17 closed, MF-19/20 added | **VERIFIED COMPLETE** |
| RM03-073 | Restart Module 04 handoff | ✔ | — | — | see report | **VERIFIED COMPLETE** |
