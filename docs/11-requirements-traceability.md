# 11 — Master requirements traceability matrix

Permanent. Requirements are never removed; they change status.

**Statuses:** NOT STARTED · DESIGNING · FRONTEND COMPLETE · BACKEND COMPLETE · INTEGRATION COMPLETE ·
TESTING · BLOCKED · FAILED · PASSED · VERIFIED · COMPLETE

Legend: ✅ done · ➖ not applicable to this requirement · ⛔ blocked by environment

## Module 01 — Foundation, Architecture & Design System

| ID | Feature | Role | FE | BE | API | DB | Sec | Tests | Android | iOS | Web | Docs | Status | Evidence |
| --- | --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M01-R01 | Repository structure (`backend`/`web`/`mobile`/`docs`/`infrastructure`) | All | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | COMPLETE | Tree in repo |
| M01-R02 | Laravel 12 backend boots | All | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `php artisan serve` + health 200 |
| M01-R03 | MySQL 8 connection + migrations | All | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `migrate` ran; `HealthTest` |
| M01-R04 | Redis 7 connection | All | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | readiness 0.36 ms |
| M01-R05 | `/api/v1` versioned contract | All | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `routes/api.php` |
| M01-R06 | Response envelope (`data` + `meta`) | All | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `ApiResponse`; client tests |
| M01-R07 | Single error contract, 11 codes | All | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `ErrorContractTest` (6) |
| M01-R08 | 5xx never leaks internals | All | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | secret-in-exception test |
| M01-R09 | Validation errors list every field | All | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `ErrorContractTest` |
| M01-R10 | Correlation / request IDs | All | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `RequestIdTest` (7) |
| M01-R11 | Forged request ID rejected | All | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | 4 hostile inputs |
| M01-R12 | Rate limiting, per actor | All | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `RateLimitTest` (3) |
| M01-R13 | Health exempt from throttling | All | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `RateLimitTest` |
| M01-R14 | Idempotency for unsafe requests | All | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `IdempotencyTest` (6) |
| M01-R15 | CORS exact allow-list | All | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `SecurityHeadersTest`; live browser |
| M01-R16 | Secure response headers | All | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `SecurityHeadersTest` |
| M01-R17 | Structured JSON logging | All | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `StructuredLoggingTest` |
| M01-R18 | Log sanitisation (secrets redacted) | All | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | 11 key shapes + nested |
| M01-R19 | 7-role RBAC architecture | All | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `RoleTest` (5); `/api/v1/meta` |
| M01-R20 | Database conventions (UUID, soft delete, FK, money) | All | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `UserModelTest` (7) |
| M01-R21 | Environment separation (5 environments) | All | ✅ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `phpunit.xml`; `.env.example` |
| M01-R22 | Production refuses to start misconfigured | All | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `ProductionConfigGuardTest` (10) |
| M01-R23 | Health live/ready separated | All | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `HealthTest` (4) |
| M01-R24 | Centralised design tokens | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | `tokens.css` + `tokens.dart` |
| M01-R25 | Typography scale, legible floors | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | `tokens_test.dart` |
| M01-R26 | Spacing system (4px) | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | `tokens_test.dart` |
| M01-R27 | Component tokens (radius/shadow/motion/z-index/controls) | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | token files |
| M01-R28 | Premium icon system, one family each | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | Lucide / Material Symbols |
| M01-R29 | Animation system + reduced motion | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | Framer Motion; `FotgMotion` |
| M01-R30 | Restaurant dashboard shell (11 areas) | Restaurant | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | 11 routes walked live |
| M01-R31 | Admin panel shell (13 areas) | Admin | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | 14 routes walked live |
| M01-R32 | Collapsible sidebar, active state, breadcrumbs, account menu | Restaurant/Admin | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | `AppShell.test.tsx` + live |
| M01-R33 | Customer mobile shell, 5 destinations | Customer | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ➖ | ✅ | PASSED (build/device pending) | `app_shell_test.dart`; rendered |
| M01-R34 | Web connected to REAL backend API | Admin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | System Health, live MySQL/Redis |
| M01-R35 | Loading / empty / error states | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | Skeletons; degraded state tested |
| M01-R36 | Responsive at 8 widths, no overflow | Restaurant/Admin | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | COMPLETE | automated sweep, API up and down |
| M01-R37 | Accessibility baseline | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | focus, skip link, landmark, contrast, 44/48px |
| M01-R38 | CI for backend / web / Flutter | All | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | ✅ | PASSED (mobile jobs unverified) | `.github/workflows/ci.yml` |
| M01-R39 | Documentation set (15 files) | All | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `docs/` |
| M01-R40 | Realistic personas used, clearly marked as test data | All | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | COMPLETE | Rahul/Priya/Highway Spice |
| M01-R41 | Android build validation | Customer | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ➖ | ✅ | **BLOCKED** | Android SDK unreachable — see 13 |
| M01-R42 | iOS build validation | Customer | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **BLOCKED** | Requires macOS + Xcode — see 13 |
| M01-R43 | PHP static analysis in CI | All | ➖ | ⛔ | ➖ | ➖ | ⛔ | ⛔ | ➖ | ➖ | ➖ | ✅ | **BLOCKED** | PHPStan uninstallable — see 13 |

### Summary

40 of 43 requirements COMPLETE. Three BLOCKED by the build environment, none by the design.

---

## Module 02 — Customer Mobile App Shell, Navigation & Premium Home

Role for every row below is **Customer**. FE = Flutter UI, BE/API/DB = ➖ throughout: Module 02
deliberately integrates no backend (see [13-known-issues.md](13-known-issues.md) KI-005).

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M02-001 | Customer app root (init, theme, l10n, lifecycle, safe areas) | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `lib/app.dart`, `main.dart` |
| M02-002 | Bottom navigation, five destinations | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | 12 navigation tests; `tab-*.png` |
| M02-003 | Home screen, three states | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01/02/03*.png` |
| M02-004 | Journey planner CTA | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `JourneyPlannerCard`; placeholder test |
| M02-005 | Active-trip component | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `RouteSummaryCard`; Persona B tests |
| M02-006 | Active-order component | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `ActiveOrderCard`; Persona C tests |
| M02-007 | Trips shell + empty state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `tab-trips.png` |
| M02-008 | Orders shell + empty state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `tab-orders.png` |
| M02-009 | Notifications shell + empty state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `tab-alerts.png` |
| M02-010 | Profile shell, 10 destinations | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `tab-profile.png` |
| M02-011 | Offline UI foundation | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-08-offline-banner.png` |
| M02-012 | Loading / skeleton system | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `HomeSkeleton`; loading test |
| M02-013 | Error system | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-09-error.png`; 4-kind test |
| M02-014 | Premium icon system | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Material Symbols; distinct-icon test |
| M02-015 | Animation + reduced motion | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `FotgMotion`; doc 17 |
| M02-016 | Accessibility | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Targets, labels, 1.4x scaling tests |
| M02-017 | Android verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **BLOCKED** | KI-001 — SDK host denied |
| M02-018 | iOS verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **BLOCKED** | KI-002 — requires macOS |
| M02-019 | Responsive testing, 320→768 | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | 6 rendered widths |
| M02-020 | Documentation | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | COMPLETE | Docs 08, 09, 11–17 |
| M02-021 | State management chosen and documented | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Riverpod 3; doc 16 |
| M02-022 | Routing architecture, persistent tab state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `StatefulShellRoute`; state-retention test |
| M02-023 | Feature flags | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `FeatureFlags`; 2 tests |
| M02-024 | Development fixtures isolated from production | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 9 isolation tests; compile-time const |
| M02-025 | API-ready domain models | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 16 domain tests |
| M02-026 | Localization architecture | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `AppStrings` + delegate |
| M02-027 | Analytics event boundary | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ⛔ | ⛔ | ✅ | COMPLETE | `AnalyticsEvents`; no SDK by design |
| M02-028 | Controlled placeholder for unbuilt features | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `ComingSoonScreen`; 4 tests |
| M02-029 | Pull-to-refresh foundation | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `RefreshIndicator` → provider invalidation |
| M02-030 | Long-content resilience | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Persona D at 320dp; `state-11*.png` |
| M02-031 | Currency architecture (INR-ready) | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integer minor units + currency code |
| M02-032 | Module 01 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | 96 backend/web tests re-run |

### Summary

30 of 32 Module 02 requirements PASSED or COMPLETE. Two (M02-017 Android, M02-018 iOS) remain
**BLOCKED** by the same environment restrictions recorded in Module 01 — not by the code.

"PASSED (device pending)" means: built, tested, and visually inspected in a rendered Flutter widget
tree, but **not** run on an Android emulator or iOS simulator.
