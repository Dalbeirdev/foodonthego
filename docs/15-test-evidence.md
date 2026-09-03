# 15 — Test evidence

Every figure below comes from a command that was actually run. The full console transcript is at
[`evidence/module-01-verification-run.txt`](evidence/module-01-verification-run.txt); screenshots
are in [`evidence/`](evidence/).

## Environment

| Tool | Version |
| --- | --- |
| PHP | 8.4.19 |
| Laravel | 12.69.1 |
| MySQL | 8.0.46 |
| Redis | 7.0.15 |
| Node.js | 22.22.2 |
| Flutter | 3.47.2 (stable) · Dart 3.13 |

## Automated tests — 115 total, 115 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend | `php artisan test` | 67 | 67 | 0 | 0 |
| Web — `@fotg/ui` | `npm test` | 18 | 18 | 0 | 0 |
| Web — `@fotg/admin` | `npm test` | 7 | 7 | 0 | 0 |
| Web — `@fotg/restaurant` | `npm test` | 4 | 4 | 0 | 0 |
| Mobile | `flutter test` | 19 | 19 | 0 | 0 |
| **Total** | | **115** | **115** | **0** | **0** |

Backend: 205 assertions, 1.13s, against real MySQL 8 and Redis 7.

## Static checks

| Check | Command | Result |
| --- | --- | --- |
| PHP code style | `vendor/bin/pint --test` | **passed** |
| TypeScript | `npm run typecheck` | **0 errors** |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --set-exit-if-changed .` | **0 changed** |
| PHP dependencies | `composer audit` | **No advisories** |
| npm dependencies | `npm audit --audit-level=high` | **0 vulnerabilities** |
| PHP static analysis | — | **NOT RUN** — see KI-003 |

## Builds

| Target | Command | Result |
| --- | --- | --- |
| Restaurant dashboard | `npm run build -w @fotg/restaurant` | ✅ 3.86s |
| Admin panel | `npm run build -w @fotg/admin` | ✅ 3.98s |
| Flutter web | `flutter build web --release` | ✅ 43s |
| **Android APK** | `flutter build apk` | **⛔ PENDING** — Android SDK unreachable (KI-001) |
| **iOS** | `flutter build ios` | **⛔ PENDING** — requires macOS + Xcode (KI-002) |

## Live API verification

Against a running `php artisan serve` with real MySQL and Redis:

| Check | Result |
| --- | --- |
| `GET /api/v1/health/ready` | 200 · MySQL **1.9 ms** · Redis **0.59 ms** |
| `GET /api/v1/nope` | 404 · `NOT_FOUND` in the documented envelope |
| `POST /api/v1/health/live` | 405 · `METHOD_NOT_ALLOWED` |
| `Origin: https://attacker.example` | **0** `Access-Control-Allow-Origin` headers returned |
| `Origin: http://localhost:5174` | `Access-Control-Allow-Origin: http://localhost:5174` |
| Structured log line | Valid JSON with `request_id`, `route`, `status`, `duration_ms`; no body, no secrets |

## Live-view verification — web

Headless Chromium, both shells, at **360 · 390 · 430 · 768 · 1024 · 1280 · 1440 · 1920 px**:

| Assertion | Result |
| --- | --- |
| Console errors / page errors / failed requests | **0** |
| Horizontal overflow (`scrollWidth > clientWidth`) | **none**, at every width |
| Horizontal overflow **with the API forced down** | **none** — the degraded state renders the longest topbar string |
| Interactive controls under 44px | **none** |
| Routes visited | **25** (11 restaurant + 14 admin) |
| Exactly one active nav link per route | ✅ |
| Breadcrumb present per route | ✅ |
| Sidebar collapse / expand | ✅ |
| Account menu opens; Escape closes | ✅ |
| Mobile drawer opens and closes on navigate | ✅ |
| Dark mode | ✅ |

**System Health rendered live values from the real API**: `Ready | Connected | Connected`.

### Screenshots

`restaurant-360` · `restaurant-390` · `restaurant-768` · `restaurant-1440` · `restaurant-collapsed` ·
`restaurant-drawer` · `restaurant-dark` · `restaurant-placeholder` · `admin-360` · `admin-768` ·
`admin-1440` · `admin-collapsed` · `admin-drawer` · `admin-dark` · `admin-system-health` ·
`admin-api-down-768`

## Live-view verification — mobile

The Flutter app was **built and rendered**, and the real widget tree was screenshotted at four
device sizes plus dark mode, with all five tabs visited.

| Device profile | Logical size |
| --- | --- |
| iPhone SE (compact) | 375 × 667 |
| iPhone 15 (standard) | 393 × 852 |
| iPhone 15 Pro Max (large) | 430 × 932 |
| Small Android | 360 × 800 |

Runtime errors: **0**.

Screenshots: `flutter-iphone-se` · `flutter-iphone-15` · `flutter-iphone-15-pro-max` ·
`flutter-android-small` · `flutter-dark` · `flutter-tab-{home,trips,orders,alerts,profile}`.

> **What this rendering is and is not.** It is the real Flutter widget tree, real theme, real
> navigation — compiled from the same Dart source an Android or iOS build would use. It is **not** an
> Android emulator or an iOS simulator, so it does not exercise platform channels, native safe-area
> insets, the on-screen keyboard, permissions or lifecycle. Those remain **PENDING** (KI-001,
> KI-002).
>
> The screenshots were produced by a **throwaway build** that temporarily bundled a stand-in font,
> because Flutter web fetches its fallback font from a CDN this environment blocks. That change was
> reverted immediately; the committed app uses the platform font. Layout, colour, spacing, icons and
> navigation in the images are the product's own.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Body text contrast, light + dark | WCAG luminance computed in `tokens_test.dart` | ≥ 4.5:1 |
| Secondary text contrast | same | ≥ 4.5:1 |
| Primary button text | same | 4.88:1 (**was 3.31:1 — fixed, R-08**) |
| Touch targets, web | browser sweep, 8 widths | none < 44px |
| Touch targets, mobile | `tokens_test.dart` | 48dp floor |
| Type floors | `tokens_test.dart` | body ≥ 15sp |
| Focus visible | `:focus-visible` ring on all interactives | ✅ |
| Skip link | `AppShell.test.tsx` | ✅ |
| Navigation landmark labelled | `AppShell.test.tsx` | ✅ (**moved off `<aside>` — R-09**) |
| Reduced motion honoured | token-level on web, `FotgMotion` in Flutter | ✅ |

## Defects found and fixed during verification

Thirteen, listed with root causes in [13-known-issues.md](13-known-issues.md). Live-view inspection
found five that no unit test would have caught (CORS, overflow, desktop button visibility, dead CSS
rule, favicon 404); the contrast test found the palette defect.


---

# Module 02 — test evidence

Full transcript: [`evidence/module-02-verification-run.txt`](evidence/module-02-verification-run.txt).
Screenshots: [`evidence/module-02/`](evidence/module-02/).

## Automated tests — 197 total, 197 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Mobile — domain models | `flutter test test/domain_models_test.dart` | 16 | 16 | 0 | 0 |
| Mobile — components | `flutter test test/components_test.dart` | 21 | 21 | 0 | 0 |
| Mobile — navigation | `flutter test test/navigation_test.dart` | 12 | 12 | 0 | 0 |
| Mobile — home screen | `flutter test test/home_screen_test.dart` | 14 | 14 | 0 | 0 |
| Mobile — fixture isolation | `flutter test test/fixture_isolation_test.dart` | 11 | 11 | 0 | 0 |
| Mobile — design tokens | `flutter test test/tokens_test.dart` | 8 | 8 | 0 | 0 |
| **Mobile total** | `flutter test` | **82** | **82** | **0** | **0** |
| Backend (regression) | `php artisan test` | 67 | 67 | 0 | 0 |
| Web (regression) | `npm test` | 29 | 29 | 0 | 0 |
| **Project total** | | **178** | **178** | **0** | **0** |

Mobile grew from 19 tests in Module 01 to 82.

## Static analysis

| Check | Command | Result |
| --- | --- | --- |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --output=none --set-exit-if-changed .` | **53 files, 0 changed** |
| Flutter web build | `flutter build web --release` | **✓ Built** |
| Backend style (regression) | `vendor/bin/pint --test` | **passed** |
| TypeScript (regression) | `npm run typecheck` | **0 errors** |

## Live-view verification

The Flutter app was **built and run**, and the rendered widget tree was inspected. Zero runtime
errors and zero console errors across every capture.

### Required states

| # | State | Screenshot | Inspected |
| --: | --- | --- | :-: |
| 1 | Home — new customer | `state-01-home-new-customer.png` | ✅ |
| 2 | Home — active journey | `state-02-home-active-journey.png` | ✅ |
| 3 | Home — active order | `state-03-home-active-order.png`, `state-03b-…-scrolled.png` | ✅ |
| 4 | Trips — empty | `tab-trips.png` | ✅ |
| 5 | Orders — empty | `tab-orders.png` | ✅ |
| 6 | Notifications — empty | `tab-alerts.png` | ✅ |
| 7 | Profile | `tab-profile.png` | ✅ |
| 8 | Offline banner | `state-08-offline-banner.png` | ✅ |
| 9 | Error state | `state-09-error.png` | ✅ |
| 10 | Loading / skeleton | asserted by widget test (`bySemanticsLabel('Loading your home screen')`) | ✅ |
| 11 | Future-feature placeholder | `state-11-coming-soon-placeholder.png` | ✅ |
| + | Long content | `state-11-long-content.png`, `…-scrolled.png` | ✅ |
| + | Dark mode | `home-dark.png` | ✅ |
| + | Large text | `home-large-text.png` | ✅ |
| + | Development harness | `dev-harness-open.png` | ✅ |

### Screen sizes rendered

| Profile | Logical size | Screenshot |
| --- | --- | --- |
| Compact | 320 × 640 | `home-320-compact.png` |
| Small Android | 360 × 800 | `home-360-android.png` |
| iPhone SE | 375 × 667 | `home-375-iphone-se.png` |
| iPhone 15 | 390 × 852 | `home-390-iphone15.png` |
| iPhone 15 Pro Max | 430 × 932 | `home-430-promax.png` |
| Tablet (graceful rendering only) | 768 × 1024 | `home-768-tablet.png` |

### Navigation matrix — all verified by test

| From | Action | Expected | Result |
| --- | --- | --- | --- |
| Home | tap Trips | Trips tab | ✅ |
| Trips | tap Orders | Orders tab | ✅ |
| Orders | tap Notifications | Alerts tab | ✅ |
| Notifications | tap Profile | Profile tab | ✅ |
| Profile | tap Home | Home tab | ✅ |
| Any | 60 rapid un-settled taps | index intact, no exception | ✅ |
| Orders | double-tap Orders | idempotent | ✅ |
| Profile | Android back | returns to Home, does not exit | ✅ |
| Home → Trips → Home | — | no re-fetch (`loadCount` stays 1) | ✅ |

## Android verification

**PENDING — environment unavailable.**

`flutter doctor` reports `✗ Android toolchain — Unable to locate Android SDK`, because
`dl.google.com` is denied by this environment's egress policy (HTTP 000 / CONNECT refused, verified
again in this run). No emulator was launched and no APK was built. Not claimed as passed.

## iOS verification

**PENDING — environment unavailable.**

`xcodebuild` is not present and cannot be: the host is Linux. No simulator was launched. Safe-area,
Dynamic Island, keyboard, gesture-navigation and orientation behaviour on iOS remain **unverified**.
The code uses `SafeArea` and the platform font resolves to San Francisco, but that is design intent,
not evidence.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Touch targets ≥ 48dp | Widget tests measure avatar and buttons | ✅ |
| Text scaling to 1.4x | Order card rendered at 1.4x, no overflow | ✅ |
| Type floors | `tokens_test.dart` | body ≥ 15sp |
| Contrast, light and dark | WCAG ratio computed in `tokens_test.dart` | ≥ 4.5:1 |
| Status not colour-alone | Every state asserted to carry a distinct icon | ✅ |
| Semantic labels | Avatar, chips, progress track, quick actions, route endpoints | ✅ |
| Reduced motion | Token-level durations + `FotgMotion` + skeleton stops looping | ✅ |
| Long content at 320dp | Persona D renders without a RenderFlex overflow | ✅ |

## Defects found and fixed

Eight, with root causes, in [13-known-issues.md](13-known-issues.md) (M02-B01 … M02-B08). Three were
found only by running the app: the harness crash, the 320dp greeting truncation and the full-width
button bug. One — the silent retry loop — was found by a test that counted repository calls rather
than asserting on pixels.
