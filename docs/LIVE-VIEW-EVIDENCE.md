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
