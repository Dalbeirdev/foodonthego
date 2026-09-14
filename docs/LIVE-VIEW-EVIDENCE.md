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
