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
