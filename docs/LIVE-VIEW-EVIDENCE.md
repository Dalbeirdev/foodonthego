# LIVE VIEW EVIDENCE

Restart Module 01.

| | |
| --- | --- |
| Commit | `b49dcb4` (2026-09-14T13:02:44Z) |
| Captured | 2026-09-14, 13:45–13:50 UTC |
| Environment | `FOTG_ENV=review`, `APP_ENV=local`, MySQL 8, Redis 7 |
| Customer Web build | `flutter build web --release --dart-define=FOTG_API_BASE_URL=/ --dart-define=FOTG_ENV=review`, Flutter 3.47.2 |
| Restaurant Web build | `index-3VUSiKVV.js`, Vite, base `/restaurant/` |
| Admin Web build | `index-BMnkuULa.js`, Vite, base `/admin/` |
| Capture tool | Playwright 1.63.0 driving Chromium 1194, headed viewport sizes |
| Raw capture log | `docs/evidence/restart-module-01/capture-log.json` |

Every screenshot below was taken from a running application in this session
against a live Laravel API and a live MySQL database. None is a mock, a design
file or a reused older image.

## How it was served

A local stand-in for `deploy/nginx/app.conf` — same routing rules, same single
origin — so a screenshot here is a screenshot of the deployed arrangement:
`/api` proxied to Laravel, the two shells on their sub-paths with SPA fallback,
the customer app at the root.

Confirmed before capture: `/` 200, `/main.dart.js` 200, `/restaurant/` 200,
`/admin/` 200, `/api/v1/health/ready` 200, and `/restaurant/assets/index-*.js`
200 — that last one being the request that 404ed before KI-054 was fixed.

## Screens opened and what was verified

| Screenshot | Surface | Route | Verified | Verdict |
| --- | --- | --- | --- | --- |
| `admin-web-system-health.png` | Admin | `/admin/system-health` | **Live API data**: API Ready (environment: local), MySQL 8 Connected 1.29 ms, Redis 7 Connected 0.3 ms, correlation id `ce927f22-…`. Header badge green, reading "API local". | **PASS — VERIFIED COMPLETE** |
| `admin-web-current.png` | Admin | `/admin/` | Full 14-item navigation renders, grouped Marketplace / Money / Operations / Platform. Overview states plainly that nothing on it is live data. No console errors, no failed requests. | PASS (shell) |
| `restaurant-web-current.png` | Restaurant | `/restaurant/` | Full 11-item navigation renders, grouped Service / Catalogue / Business / Account. Header badge green. No console errors, no failed requests. | PASS (shell) |
| `customer-web-desktop-home.png` | Customer Web | `/` @1440 | App boots, renders, routes to the welcome screen. Brand mark and CTA draw. **All text invisible** and **CTA spans the full 1440 px**. | **FAIL — MF-01, MF-02** |
| `customer-web-mobile-home.png` | Customer Web | `/` @390 | Same screen at phone width. Layout correct — CTA properly inset with margins. Text still invisible. | PARTIAL — MF-01 |
| `customer-web-{360,390,430,768,1024,1280,1440,1920}.png` | Customer Web | `/` | All eight required breakpoints captured. Renders at every one; no layout collapse, no horizontal scroll. Phone widths inset correctly; ≥1024 stretches. | PARTIAL — MF-02 |
| `customer-web-auth-phone.png` | Customer Web | `/#/auth/phone` | Route resolves, screen renders. | PARTIAL — MF-01 |
| `customer-web-trips.png` | Customer Web | `/#/trips` | Route resolves; redirected to auth as expected when unauthenticated. | PASS (guard works) |
| `customer-web-orders.png` | Customer Web | `/#/orders` | As above. | PASS (guard works) |
| `customer-web-profile.png` | Customer Web | `/#/profile` | As above. | PASS (guard works) |

## Console and network findings

**React shells: zero console errors, zero failed requests** on all three captures.

**Customer Web: `fonts.gstatic.com` requests failed with `ERR_CONNECTION_RESET`**
on every capture — Roboto, Noto Sans Symbols 2, Noto Color Emoji.

This sandbox blocks that host, so the failure itself is an artefact of where the
audit ran. **What it revealed is not an artefact.** The app declares
`FotgTypography.fontFamily = null`, ships no font asset, and has no
`google_fonts` dependency — so Flutter's CanvasKit renderer fetches Roboto from
Google's CDN at runtime. When that fetch fails, text does not fall back to a
system font and does not raise a visible error: **it renders blank.** On the
deployed site, where the CDN is reachable, text appears — which is why nobody has
seen this. It is recorded as MF-01 because a customer behind a corporate
firewall, on a restricted network, or with that host blocked gets an app with no
words in it.

## Platforms not inspected live

- **Android — NOT INSPECTED IN THIS ENVIRONMENT.** No SDK, no emulator (KI-001).
  CI installs the release APK on a Pixel 6 / API 34 emulator, launches it, asserts
  no crash, and runs 29 integration tests. Green on this commit. That is not a
  screenshot and is not claimed as one.
- **iOS LIVE VIEW = PENDING — ENVIRONMENT UNAVAILABLE.** No Apple hardware is
  reachable from here. CI builds on `macos-latest` and runs the integration tests
  on an iPhone simulator; green on this commit. **Not marked PASS.**

---

# RESTART MODULE 02 — LIVE VIEW EVIDENCE

| | |
| --- | --- |
| Captured | 2026-09-14, 14:20–14:25 UTC |
| Customer Web build | `index-DOKa6EBA.js` (249 KB) / `index-UTrU5lQU.css` (28 KB), Vite 6 |
| Backend | Laravel 12 on `127.0.0.1:8000`, `APP_ENV=local`, MySQL 8, Redis 7 |
| Session | **A real customer**, registered through the real OTP flow: phone → code read from the server log → verify → register → bearer token |
| Capture tool | Playwright 1.63.0 / Chromium 1194 |
| Raw log | `docs/evidence/restart-module-02/capture-log.json` |

The session is not a fixture and not a stub. `+919999900101` requested a code,
the code was read from `storage/logs/otp-development.log`, verification returned a
registration token, registration returned a 50-character bearer token, and that
token was put in `sessionStorage` before each page load. Home then rendered
`Good afternoon, Rahul` from `GET /api/v1/customer/home`.

## Screens opened

| Screenshot | Route | Verified | Verdict |
| --- | --- | --- | --- |
| `restart-m02-web-logged-out.png` | `/` anonymous | Landed on `/login`. **0 API calls made.** | **PASS** |
| `restart-m02-web-protected-route-logged-out.png` | `/orders` anonymous | Landed on `/login`. 0 API calls. | **PASS** |
| `restart-m02-web-home-desktop.png` | `/` @1440 | Rail with five destinations, Home active; "Good afternoon, Rahul"; journey CTA sized to its label; "No active journey". **1 API call.** | **PASS** |
| `restart-m02-web-home-mobile.png` | `/` @390 | Bottom bar with five destinations, Home active; CTA full-width; no rail. **1 API call.** | **PASS** |
| `restart-m02-empty-home.png` | `/` @1024 | Empty-state Home with no order card at all. | **PASS** |
| `restart-m02-web-trips.png` | `/trips` | Renders "Trips — Journeys you have planned will appear here." | **PASS** |
| `restart-m02-web-orders.png` | `/orders` | Renders "Orders — Orders you have placed will appear here." | **PASS** |
| `restart-m02-web-notifications.png` | `/notifications` | "No notifications yet." No fabricated badge. | **PASS** |
| `restart-m02-web-profile.png` | `/profile` | Renders. | **PASS** |
| `restart-m02-web-plan-journey.png` | `/trips/plan` | Renders — the CTA destination exists. | **PASS** |
| `restart-m02-web-{360,390,430,768,1024,1280,1440,1920}.png` | `/` | All eight render. Bottom bar ≤768, rail ≥1024. No horizontal overflow. | **PASS** |
| `restart-m02-web-home-error.png` | `/` with a rejected token | "We couldn't load your home screen", request id `a2228a46-…`, Try again — **and Plan a journey still present**. | **PASS** |
| `restart-m02-web-keyboard-focus.png` | `/` | Tab order: Skip to content → Home → Trips → Orders → Notifications → Profile → Plan a journey. | **PASS** |

## Console and network

**Zero console errors on every screen** except the deliberate error-state capture,
where the only entry is the expected `401 (Unauthorized)`.

**Zero external requests on every screen.** No font CDN, no analytics, no third
party. That is the architectural close-out of MF-01.

**Cost control, measured:** Home issued exactly **one** request,
`/api/v1/customer/home`. Google 0, Razorpay 0 — the target was 0/0.

## Not inspected live, stated plainly

- **Android — NOT INSPECTED.** No SDK or emulator in this environment (KI-001).
  CI runs the release APK on a Pixel 6 / API 34 emulator.
- **iOS RESTART MODULE 02 = PENDING — RUNTIME ENVIRONMENT UNAVAILABLE.** No Apple
  hardware is reachable. Not marked PASS.
- **Active trip and active order cards** have unit-test coverage but no
  screenshot: the live customer had neither, and seeding one purely to make Home
  look populated would be exactly the kind of evidence this restart exists to
  reject.

---

# RESTART MODULE 03 — LIVE VIEW EVIDENCE

| | |
| --- | --- |
| Captured | 2026-09-14, ~15:30 UTC |
| Customer Web build | `index-ZKYO5Ulo.js` (256 KB) / `index-rFJ08GHV.css` |
| Backend | Laravel 12, `APP_ENV=local`, MySQL 8, Redis 7, `OTP_PROVIDER=log` |
| Capture tool | Playwright 1.63.0 / Chromium 1194 |
| Raw log | `docs/evidence/restart-module-03/capture-log.json` |

**Codes were read from the server's log, never from the UI.** The browser was
driven exactly as a person would drive it: type a number, press the button, read
the code from elsewhere, type it in.

| Screenshot | Scenario | Verified | Verdict |
| --- | --- | --- | --- |
| `restart-m03-web-login-desktop.png` | `/login` @1280 | Branded panel, phone field with `+91`, Send code | **PASS** |
| `restart-m03-web-login-mobile.png` | `/login` @390 | Full-bleed on a phone, 48px controls | **PASS** |
| `restart-m03-web-otp.png` | Code entry | `Sent to +91 ••••••1122` — the server's mask. "Change number". "Resend code in 30s", disabled. | **PASS** |
| `restart-m03-auth-error.png` | Wrong code | "That code isn't correct. Please check it and try again." No attempts-remaining hint. | **PASS** |
| `restart-m03-web-registration.png` | New number | "What should we call you?"; the number is shown masked and is not editable | **PASS** |
| `restart-m03-web-home-after-signin.png` | After registration | **"Good afternoon, Meera"** — Home, real data | **PASS** |
| `restart-m03-web-existing-customer-home.png` | Existing number | **"Good afternoon, Rahul"** — straight Home, no registration step, no trace of the previous customer | **PASS** |
| `restart-m03-web-signed-in-login-redirect.png` | Signed-in `/login` | Redirected to `/` | **PASS** |
| `restart-m03-web-after-logout.png` | Sign out | Token cleared; back button does not reopen Home | **PASS** |
| `restart-m03-web-session-expired.png` | Forged token | Cleared and sent to sign-in by the central handler | **PASS** |
| `restart-m03-web-login-{360…1920}.png` | Eight widths | No horizontal overflow at any width | **PASS** |

## Database and log checks after the run

- OTP hashes: 64-character hex. **No plaintext code is stored anywhere.**
- One customer row per number. No duplicates.
- New accounts: `role=customer`, `status=active` — server-assigned.
- Plaintext codes in the application log: **0**.

## Console

One console error across the whole run: the expected `422` from the deliberate
wrong-code test. Every other screen was clean.

## Not inspected live

Android and iOS authentication was **not** driven by a person — no SDK, emulator
or Apple hardware is reachable. **iOS RESTART MODULE 03 = PENDING — RUNTIME
ENVIRONMENT UNAVAILABLE.**

---

# Restart Module 05 — trip planner

Chromium 1194 (`/opt/pw-browsers/chromium-1194`) against the React customer app
on `http://127.0.0.1:5175`, proxying `/api` to the Laravel API on
`http://127.0.0.1:8000` — the same origin arrangement `deploy/nginx` serves in
production, so no address in the client can be right here and wrong there.

Backend: `PLACES_PROVIDER=development`, `OTP_PROVIDER=log`, MySQL
`foodonthego_local`. Two controlled test customers signed in through the real
OTP flow. **No real personal number, no real OTP, no token and no
`Authorization` header appears in any screenshot.**

## What was driven, and what it answered

| # | State | Result |
| --- | --- | --- |
| 1 | Planner, both ends empty | CTA disabled, nothing invented |
| 2 | Origin picker, saved places present | Home and Work, with their real stored addresses |
| 3 | No saved places (second customer) | "No saved addresses yet" + a link to add one |
| 4 | Place search, 10 characters typed | **1** autocomplete request |
| 5 | Suggestion selected | **1** details request; coordinates 26.8242, 75.8122 |
| 6 | Saved address selected | **0** provider requests |
| 7 | Current location, granted | Controlled fix 28.6129, 77.2295 → "New Delhi"; **1** reverse-geocode |
| 8 | Current location, nothing nearby to name | "Current location" over the real coordinates — no invented address |
| 9 | Current location, blocked | Recovered after the 15 s watchdog; saved places and search still offered |
| 10 | Same place at both ends | Inline error, CTA disabled |
| 11 | No results | "No places match that search." |
| 12 | Provider error (503) | "We could not load places right now." — no provider detail |
| 13 | Offline | "We could not reach FoodOnTheGo. Check your connection and try again." |
| 14 | Double-click create | One POST; one journey |
| 15 | Journey created | `/trips/{uuid}`, "Route not calculated yet" |
| 16 | Reload the handoff URL | The journey is still there — loaded from the server by id |
| 17 | Trips tab | The new journey listed |
| 18 | Home | Active-journey card, CTA href is the real trip id |
| 19 | Session expires mid-search | Token cleared, `/login`, no anonymous trip |
| 20 | Sign out, sign in as the other customer | Empty planner, no saved places, only her own trips |
| 21 | Keyboard only, no mouse | Tab → Enter → type → arrows → Enter → Escape, all working |
| 22 | 360 / 390 / 430 / 768 / 1024 / 1280 / 1440 / 1920 | 0 px overflow, planner and picker both |

**Console errors: none.** Every capture above was recorded with console, page
errors and every HTTP response ≥ 400 collected. The one error the first run did
show — a 404 for `/favicon.ico` — was fixed and the control confirms it: adding
the favicon removed it.

## Server timings, measured

| Call | Typical |
| --- | --- |
| `GET /customer/addresses` | 16–19 ms |
| `GET /customer/places/search` | 17–18 ms |
| `GET /customer/places/{place}` | 17–20 ms |
| `POST /customer/places/reverse-geocode` | 17–20 ms |
| `POST /customer/trips` | 23 ms |
| `GET /customer/trips` | 19–20 ms |
| `GET /customer/home` | 20–21 ms |

Local, against the development gazetteer, so these are the application's own
time and not a provider's. A live Google call adds its own network round trip
that this environment cannot measure.

## Screenshots

`docs/evidence/restart-module-05/` — 27 files, all captured from the running
application. None is a mockup.

---

# Restart Module 06 — routing and maps

Chromium 1194 against the **production build** (`npm run build`, served with the
same same-origin `/api` proxy nginx provides) on `http://127.0.0.1:5180`, and the
Laravel API on `http://127.0.0.1:8000`.

Production rather than `vite dev` on purpose: React's StrictMode double-invokes
effects in development, which doubles every read and would have made the cost
figures wrong in the reassuring direction.

Backend: `ROUTE_PROVIDER=development`, `PLACES_PROVIDER=development`, MySQL
`foodonthego_local`. The journey is the real one Restart Module 05 created —
Green Park, New Delhi → Jaipur International Airport.

## The before state

`restart-m06-before-web-route.png`. A trip whose `route_status` was **READY**,
with a calculated and selected route in the database, rendered as
**"Route not calculated yet"** — no map, no distance, no travel time, no CTA.

## What was driven

| # | State | Result |
| --- | --- | --- |
| 1 | Route loading | "Working out your route…" with a spinner |
| 2 | Route ready | 237 km, 3 hr 56 min, from the server |
| 3 | Route shape | One polyline path, decoded from the stored geometry |
| 4 | Origin and destination markers | Both present, at the polyline's ends |
| 5 | Fit to bounds | The drawing is shaped from the route's own bounds |
| 6 | Map tiles unavailable | Stated in words, with the reason |
| 7 | Synthetic provider | Warning banner — "These figures are not a real route" |
| 8 | Traffic absent | "Traffic information is not available for this route." |
| 9 | Freshness | "Worked out 7 min ago" |
| 10 | Single route | "Your provider returned one route for this journey." |
| 11 | Explicit refresh | `calculated_at` moved; the provider was asked again |
| 12 | Provider error (503) | "We could not work out a route right now." + Try again + Change journey |
| 13 | No route | "No driving route found" — and **no Find Food CTA at all** |
| 14 | Offline mid-session | "We could not reach FoodOnTheGo…" + retry |
| 15 | Find Food CTA | `/trips/{id}/restaurants?route={routeId}` |
| 16 | Handoff screen | Names both identifiers, says Module 07 owns the listing |
| 17 | 360 / 390 / 430 / 768 / 1024 / 1280 / 1440 / 1920 | 0 px overflow at every width |
| 18 | Keyboard only | Tab reaches refresh and the CTA; Enter navigates |
| 19 | Screen reader | Every figure the drawing shows is also in text |

**Console errors: none**, on every capture, with console, page errors and every
HTTP response ≥ 400 collected.

## Provider cost, measured

| Action | Billed `calculate` | Free `GET` | Maps tiles | Restaurants | Razorpay |
| --- | --- | --- | --- | --- | --- |
| First open of a new journey | **1** | 1 | 0 | 0 | 0 |
| 5 page refreshes | **0** | 5 | 0 | 0 | 0 |
| 5 × Home → Route | **0** | 5 | 0 | 0 | 0 |
| Fresh session | **0** | 1 | 0 | 0 | 0 |

Negative control at the API: a second `calculate` inside the freshness window
left `calculated_at` unchanged; `?refresh=true` changed it. So the reuse is the
freshness window working, not the endpoint failing silently.

## Map size across the breakpoints

Measured because "do not make the map tiny" is a requirement, and because the
first attempt broke it invisibly.

| Width | Map |
| --- | --- |
| 360 | 302 × 109 |
| 768 | 710 × 256 |
| 1024 | 678 × 244 |
| 1280 | 514 × 185 |
| 1440 | 606 × 218 |
| 1920 | 679 × 245 |

The 1280 figure is smaller than 1024 because the two-column layout trades map
width for showing the map and every detail at once. It is stated rather than
smoothed over.

## Screenshots

`docs/evidence/restart-module-06/` — 10 files, all from the running application.
None is a mockup, and none shows a map: there are no tiles to show.
