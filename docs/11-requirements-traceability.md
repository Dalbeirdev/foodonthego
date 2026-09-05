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

---

## Module 03 — Customer Authentication, Registration, OTP, Session & Security

Role for every row below is **Customer**. FE = Flutter UI. "PASSED (device pending)" carries the
same meaning as in Module 02: built, integrated against the real API, tested and visually inspected
in a rendered widget tree, but not run on an Android emulator or iOS simulator (KI-001, KI-002).

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M03-001 | Welcome / unauthenticated entry screen | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01-welcome.png`; 3 tests |
| M03-002 | Phone entry with country selector | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02/03/04*.png`; 7 tests |
| M03-003 | E.164 normalization, one identity per subscriber | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `PhoneNormalizerTest` (27); unique index |
| M03-004 | Supported-country table mirrored client/server | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `auth_models_test.dart`; `PhoneNormalizerTest` |
| M03-005 | Client validation never authoritative | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `PhoneFormRequest::phoneNumber()` |
| M03-006 | OTP request endpoint | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `CustomerOtpTest`; integration run |
| M03-007 | CSPRNG code generation | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `random_int`; distribution test |
| M03-008 | Codes stored as a peppered hash, never plaintext | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Column-by-column test; live MySQL query |
| M03-009 | Constant-time comparison | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `hash_equals` |
| M03-010 | Code expiry (5 min, configurable) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Service + API tests; on-screen countdown |
| M03-011 | Attempt limit; correct code dies with the challenge | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `OtpChallengeServiceTest`; `CustomerOtpTest` |
| M03-012 | Single-use codes; replay refused | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Replay tests + integration run |
| M03-013 | New code invalidates the previous one | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `superseded` reason; 2 tests |
| M03-014 | Resend cooldown, server-enforced | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `CustomerOtpTest`; integration run |
| M03-015 | Per-phone and per-IP rate limits | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `OtpRateLimiter`; `CustomerOtpTest` |
| M03-016 | Rate-limit responses disclose no threshold | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Threshold-disclosure test |
| M03-017 | OTP entry screen (countdown, resend, change number) | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-05/06*.png`; 11 tests |
| M03-018 | SMS autofill hint, no SMS-read permission | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `AutofillHints.oneTimeCode`; no manifest permission |
| M03-019 | Registration screen, minimum fields | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-07/08/09*.png`; 8 tests |
| M03-020 | Registration bound to the verified challenge | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RegistrationTokenServiceTest` (9); no `phone` field anywhere |
| M03-021 | Registration token expiry and single-challenge binding | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 4 rejection tests |
| M03-022 | Idempotent registration (retry returns the same account) | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Unique-violation path; `CustomerRegistrationTest` |
| M03-023 | Returning customer signs straight in | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `CustomerOtpTest`; integration run (2nd pass) |
| M03-024 | Session token issue, storage, expiry | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Sanctum; live MySQL hash check |
| M03-025 | Secure token storage on device (Keychain / KeyStore) | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `SecureSessionStore`; no plaintext store |
| M03-026 | Session restore without a flash | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `SessionSplash`; 6 restore tests |
| M03-027 | Route guards for every protected screen | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | 5 routes asserted; `state-15*.png` |
| M03-028 | Logout: local clear, server revoke, one device only | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-13/14*.png`; 5 tests |
| M03-029 | `/customer/me` unreachable without a token | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 401 tests + integration run |
| M03-030 | Cross-role authorization (customer ≠ restaurant ≠ admin) | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `AuthorizationBoundaryTest` (8) |
| M03-031 | Account status gating (active/suspended/disabled/deleted) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `AccountStatus` ENUM; 4 tests |
| M03-032 | No account enumeration | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Identical-response test |
| M03-033 | No OTP, token or full number in any log | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `AuthLoggingTest` (5); live log grep |
| M03-034 | Production refuses a sender that cannot reach a handset | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `ProductionConfigGuardTest` (+3) |
| M03-035 | Error-code → message mapping, never server prose | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `auth_error_messages.dart`; coverage test |
| M03-036 | Offline / network-failure handling in the flow | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `ApiException.network`; 3 tests |
| M03-037 | Home and profile use the authenticated identity | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-10/11*.png`; 3 tests |
| M03-038 | Stale-challenge retention policy | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `otp:prune`; `PruneOtpChallengesTest` (4) |
| M03-039 | Real Flutter → Laravel → MySQL integration | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `tool/integration_smoke.dart`, 15 assertions |
| M03-040 | Android build / device test | ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **BLOCKED** | KI-001 — `dl.google.com` denied |
| M03-041 | iOS build / device test | ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **BLOCKED** | KI-002 — no macOS host |
| M03-042 | Module 01 + Module 02 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | 197 backend + 29 web + 154 mobile re-run |

### Summary

40 of 42 Module 03 requirements COMPLETE or PASSED. Two (M03-040 Android, M03-041 iOS) remain
**BLOCKED** by the same environment restrictions recorded in Module 01 — not by the code.

**Android runtime verification = PENDING — environment unavailable.**
**iOS runtime verification = PENDING — environment unavailable.**

---

## Module 04 — Customer Profile & Saved Addresses

Role for every row below is **Customer**. FE = Flutter UI. "PASSED (device
pending)" carries the same meaning as in Modules 02 and 03: built, integrated
against the real API, tested and visually inspected in a rendered widget tree,
but not run on an Android emulator or iOS simulator (KI-001, KI-002).

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M04-001 | Profile screen | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01-profile.png`; 2 tests |
| M04-002 | Authenticated profile data, no fixture | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `ProfileApiTest`; integration run |
| M04-003 | Edit profile | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02/04*.png`; 15 tests |
| M04-004 | Profile validation, server authoritative | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-03*.png`; unicode/blank/length tests |
| M04-005 | Phone read-only and untamperable | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 3 independent defences; API + integration tests |
| M04-006 | Email management, never falsely verified | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `email_verified` always false; un-verify test |
| M04-007 | Profile API (GET + PATCH) | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `ProfileApiTest` (19) |
| M04-008 | Saved address list | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-10/12*.png`; 8 tests |
| M04-009 | Saved address empty state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-05*.png` |
| M04-010 | Add address | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-06/07/08/09*.png`; 10 tests |
| M04-011 | Edit address | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-15*.png`; partial-update tests |
| M04-012 | Delete address, with confirmation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-16*.png`; 4 tests |
| M04-013 | Address types (HOME/WORK/OTHER) | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | MySQL ENUM; `state-12*.png` |
| M04-014 | Custom label, required for OTHER | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11*.png`; blank-label tests |
| M04-015 | Default address, exactly one | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Generated column + unique index; 8 tests |
| M04-016 | First address becomes default | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `state-09*.png`; service + API tests |
| M04-017 | Address data model | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Migration; `SHOW CREATE TABLE` in evidence |
| M04-018 | Future geo-coordinate support, no fake data | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Columns present, values NULL; range validation |
| M04-019 | Customer ownership from the token only | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | No id in any route; `ownedByOrFail()` |
| M04-020 | IDOR protection (read/update/delete/default) | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `AddressOwnershipTest` (14); integration run |
| M04-021 | Mass-assignment protection | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Allow-listed requests; injection tests |
| M04-022 | Offline behaviour: read cached, writes need the network | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-17*.png`; 3 tests |
| M04-023 | Cache isolation across accounts | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `account_isolation_test.dart` (3) |
| M04-024 | Loading states (skeletons, not spinners) | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `_AddressListSkeleton`; row-level progress |
| M04-025 | Error states, no stack traces | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Code-to-message mapping; 500 test |
| M04-026 | Accessibility | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Semantics, text-not-colour, 320dp, 1.4× |
| M04-027 | Android testing | ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **BLOCKED** | KI-001 — `dl.google.com` denied |
| M04-028 | iOS testing | ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **BLOCKED** | KI-002 — no macOS host |
| M04-029 | API tests | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 39 feature tests across 3 suites |
| M04-030 | Flutter tests | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 68 new (widget + unit) |
| M04-031 | Integration test, no mocks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `tool/profile_addresses_smoke.dart`, 24 assertions |
| M04-032 | Live-view inspection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 24 screenshots, zero console errors |
| M04-033 | Database verification | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Direct queries in the evidence file |
| M04-034 | Documentation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `19-*.md` + 11 updated documents |
| M04-035 | Modules 01–03 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | 296 + 224 + 29 tests; M03 integration re-run |
| M04-036 | Per-country postal-code validation | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Four rules + unlisted fallback; 9 tests |
| M04-037 | Address limit, configurable | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `ADDRESS_LIMIT_REACHED`; 2 tests |
| M04-038 | Personal data absent from logs | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `AddressLoggingTest` (6); live log grep |
| M04-039 | Duplicate-submission safety | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Form submission lock + `Idempotency-Key` test |
| M04-040 | Auth state updates after a profile change | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `AuthController.updateProfile()`; 1 test |

### Summary

38 of 40 Module 04 requirements COMPLETE or PASSED. Two (M04-027 Android,
M04-028 iOS) remain **BLOCKED** by the same environment restrictions recorded in
Module 01 — not by the code.

**Android runtime verification = PENDING — environment unavailable.**
**iOS runtime verification = PENDING — environment unavailable.**

---

## Module 05 — Trip Planner: Origin, Destination & Trip Creation

Role for every row below is **Customer**. FE = Flutter UI. "PASSED (device
pending)" carries the same meaning as in Modules 02, 03 and 04: built, integrated
against the real API, tested and visually inspected in a rendered app, but not
run on an Android emulator or iOS simulator (KI-001, KI-002).

Screenshot names refer to the Module 05 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md).

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M05-001 | Home → Plan a Journey opens the planner | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01/02`; `navigation_test.dart` |
| M05-002 | Trip planner screen | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02`; `trip_planner_test.dart` (20) |
| M05-003 | Origin selection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-03/04`; integration run |
| M05-004 | Destination selection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-05/07`; integration run |
| M05-005 | Place search (autocomplete) | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-05`; `PlaceApiTest`, `place_search_test.dart` |
| M05-006 | Place details resolve to a real position | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration run: "details resolve a suggestion to a real position" |
| M05-007 | Saved-address selection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration run; `trip_planner_test.dart` |
| M05-008 | Current-location selection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-04`; real browser geolocation; DB row |
| M05-009 | Reverse geocoding names a fix without moving it | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration run; `PlaceProviderTest` |
| M05-010 | Swap origin and destination | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-08`; 2 tests incl. one end chosen |
| M05-011 | Clear / edit either end | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-12`; `trip_planner_test.dart` |
| M05-012 | Trip validation before submission | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11/13`; 4 tests; nothing sent |
| M05-013 | Trip creation API | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `TripApiTest` (30); integration run |
| M05-014 | Flutter connected to the real API | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Live-view run against the running server |
| M05-015 | Trip input persisted | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Direct MySQL queries in the evidence file |
| M05-016 | Endpoint snapshotted, not referenced | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration: address edited *and* deleted, trip unchanged |
| M05-017 | Trip model and migration | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `SHOW COLUMNS` in the evidence file |
| M05-018 | Location/place model (no vendor JSON in the app) | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `PlaceSuggestion`/`PlaceDetails`; `trip_models_test.dart` |
| M05-019 | Trip listing and retrieval | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-10`; `trips_screen_test.dart` (13) |
| M05-020 | Discarding a trip | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-14/15/16/17`; integration run |
| M05-021 | Customer ID never accepted from the client | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | No self-service route carries one; `TripOwnershipTest` (14) |
| M05-022 | Mass-assignment protection | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration: `customer_id`/`status`/`route_status`/`distance`/`eta` all ignored |
| M05-023 | Ownership: cannot read another customer's trip | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration + `TripOwnershipTest` |
| M05-024 | Ownership: cannot modify or discard another's trip | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration; no DELETE route exists |
| M05-025 | Ownership: cannot use another's saved address | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration; resolved through Module 04's own lookup |
| M05-026 | Refusals leak nothing about the other account | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration sweeps the response for six of her values |
| M05-027 | Missing and forbidden are indistinguishable | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Both 404; asserted side by side |
| M05-028 | Coordinate range validation (−90..90, −180..180) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration; `TripServiceTest` |
| M05-029 | (0, 0) refused as an uninitialised sentinel | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration: `INVALID_COORDINATES` |
| M05-030 | Same-location refused at both layers | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11`; integration; haversine unit tests |
| M05-031 | No coordinates are ever fabricated | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 4 rules in `20-*.md`; unlocated address refused, not guessed |
| M05-032 | No distance, duration, polyline or ETA anywhere | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | No such column; integration sweeps the payload; live view asserts no "km" |
| M05-033 | `route_status` read, never assumed | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `NOT_CALCULATED` on every row in MySQL |
| M05-034 | Google/Places configuration audited and documented | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `20-*.md`, `07-security.md`, `.env.example` |
| M05-035 | No provider key in mobile source or bundle | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Server-mediated; no provider SDK in `pubspec.yaml` |
| M05-036 | Unconfigured provider blocks a production boot | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `ProductionConfigGuardTest` (15) |
| M05-037 | Live Google Places verification | ➖ | ⛔ | ⛔ | ➖ | ➖ | ⛔ | ➖ | ➖ | ✅ | **PENDING** | KI-010 — no API key in this environment |
| M05-038 | Location permission requested contextually | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | 4 tests: nothing asks at launch, on the planner, or on the picker |
| M05-039 | Every permission outcome handled distinctly | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `location_permission_test.dart` (15); `state-21b` |
| M05-040 | Services-disabled never reported as a denial | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Dedicated test; different words, different action |
| M05-041 | The customer is never trapped | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Search offered on every refusal; 25 s hard deadline (M05-B09) |
| M05-042 | No continuous location tracking | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | One-shot API only; no stream, no background permission |
| M05-043 | Debounce, session tokens, stale-answer cancellation | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `place_search_test.dart` (13), race test included |
| M05-044 | Places, coordinates and queries absent from logs | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `TripLoggingTest` (8); live log grep, 11 needles, 0 hits |
| M05-045 | Account cache isolation for trips and searches | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `account_isolation_test.dart`; cache keyed by query alone |
| M05-046 | Android runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **BLOCKED** | KI-001 — SDK unreachable |
| M05-047 | iOS runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **BLOCKED** | KI-002 — no macOS host |
| M05-048 | Live-view inspection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 28 states, no application errors |
| M05-049 | Database verification | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Direct queries in the evidence file |
| M05-050 | Documentation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `20-*.md` rewritten + 12 documents updated |
| M05-051 | Modules 01–04 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | 408 backend + 312 Flutter + 4 web; Pint clean |

### Summary

48 of 51 Module 05 requirements are COMPLETE or PASSED. Three are not, and none
of the three is a code failure:

- **M05-037 Live Google Places verification = PENDING — environment unavailable.**
  No API key is configured here and the provider is unreachable, so the adapter is
  verified against a stubbed HTTP transport rather than against Google. See
  KI-010.
- **M05-046 Android runtime verification = PENDING — environment unavailable.**
  KI-001.
- **M05-047 iOS runtime verification = PENDING — environment unavailable.**
  KI-002.

The ID range grew from the specification's 46 to 51 because five of its
requirements covered two distinguishable things each — reading versus modifying
another customer's trip, range validation versus the (0, 0) sentinel, permission
outcomes versus the services-disabled case — and splitting them keeps each row
independently verifiable. Nothing was removed.

---

## Module 06 — Maps, Route Calculation, Distance & Travel Time

Role for every row below is **Customer**. FE = Flutter UI. "PASSED (device
pending)" carries the same meaning as in Modules 02–05: built, integrated against
the real API, tested and visually inspected in a rendered app, but not run on an
Android emulator or iOS simulator (KI-001, KI-002).

Screenshot names refer to the Module 06 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md) and captured under
`docs/evidence/module-06/`.

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M06-001 | A created trip can have a route calculated | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01/02`; integration run |
| M06-002 | Routing provider abstraction (`RouteProvider`) | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteProviderTest` (28) |
| M06-003 | Google Routes API v2 adapter | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE (unverified live) | `RouteProviderTest`; stubbed transport — see M06-051 |
| M06-004 | `unconfigured` provider fails loudly and blocks production boot | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `ProductionConfigGuardTest` (17) |
| M06-005 | `development` provider refuses production and labels itself | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-04`; `RouteProviderTest` |
| M06-006 | The app never calls a routing provider directly | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | No routing key in the app; `ApiRouteRepository` only |
| M06-007 | Maps SDK key restricted by Android package + signing certificate | ➖ | ➖ | ➖ | ➖ | ✅ | ➖ | ⛔ | ➖ | ✅ | DOCUMENTED (device pending) | `21-maps-and-routing.md`; `07-security.md` |
| M06-008 | Maps SDK key restricted by iOS bundle identifier | ➖ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ⛔ | ✅ | DOCUMENTED (device pending) | Same |
| M06-009 | Routing key restricted by server/IP and API scope, backend only | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `.env.example` guidance; key absent from the app |
| M06-010 | No unrestricted production key committed; no key logged | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteLoggingTest`; live log grep for `AIza`, 0 hits |
| M06-011 | Environment configuration for routing | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `config/foodonthego.php`; `.env.example` |
| M06-012 | `POST /trips/{trip}/route/calculate` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `TripRouteApiTest` (26); integration run |
| M06-013 | `GET /trips/{trip}/routes` never calculates | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `TripRouteApiTest`; integration run asserts 0 provider calls |
| M06-014 | `POST /trips/{trip}/routes/{route}/select` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `TripRouteApiTest`; `route_controller_test.dart` |
| M06-015 | Normalized route response model | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `TripRoute::toApiArray()`; `route_models_test.dart` (25) |
| M06-016 | Distance stored exactly as the provider returned it | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | DB verification; `RouteValidatorTest` |
| M06-017 | Travel duration stored exactly as returned | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Same |
| M06-018 | Traffic duration stored, NULL when not supplied | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteProviderTest`; DB shows `with_traffic = 0` for the development provider |
| M06-019 | Encoded polyline stored and never fabricated | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `PolylineCodecTest` (8); integration run decodes it |
| M06-020 | Viewport bounds stored for camera framing | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RouteBounds`; integration run |
| M06-021 | `trip_routes` table | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Migration; `SHOW COLUMNS` in the evidence file |
| M06-022 | Exactly one selected route per trip, enforced by the database | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Unique index over a virtual column; DB check = 0 violations |
| M06-023 | The recommended route is selected by default | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RouteCalculationServiceTest`; integration run |
| M06-024 | Alternatives listed with their own figures and a comparison | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `route_screen_test.dart` (29) — see M06-052 |
| M06-025 | Route map screen | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02`; `route_screen_test.dart` |
| M06-026 | Camera fits the whole route, once per route | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | `RouteMapView`; KI-011 |
| M06-027 | Markers at both ends | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | Same |
| M06-028 | Selected route distinguished by width and z-order, not colour alone | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | Same; `08-design-system.md` |
| M06-029 | Summary sheet: distance, travel time, traffic delay, age | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02/05`; `journey_measures.dart` tests |
| M06-030 | Loading state is a skeleton, not a blank screen | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `route_screen_test.dart` |
| M06-031 | Timeout state, with a retry | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-12` |
| M06-032 | No-route state, with **no** retry | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-11` |
| M06-033 | Map-unavailable state keeps the whole summary; never a blank map | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-03`; `state-17` |
| M06-034 | Travel mode DRIVE | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteProviderTest` asserts the request body |
| M06-035 | Traffic-aware routing requested | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Same |
| M06-036 | `calculated_at` recorded and shown as an age | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-05`; DB verification |
| M06-037 | Endpoint change invalidates the route | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `EndpointFingerprint`; integration run moves an endpoint |
| M06-038 | Route fingerprint, derived on the trip and stored on the route | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | DB check: 0 null fingerprints |
| M06-039 | `route_status` covers NOT_CALCULATED/CALCULATING/READY/NO_ROUTE/FAILED/STALE | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RouteStatus`; `route_models_test.dart` |
| M06-040 | Retry is safe and never duplicates a route set | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration run: repeated calculation leaves one set |
| M06-041 | Concurrent calculation makes one provider call | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Cache lock; `RouteCalculationServiceTest` |
| M06-042 | Persistence is transactional | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteCalculationServiceTest`; DB check: 0 READY trips without routes |
| M06-043 | Provider responses are validated before storage | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteValidatorTest` (15) |
| M06-044 | Malformed polyline is refused, and never half-drawn | ✅ | ✅ | ➖ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `PolylineCodecTest`; `polyline_codec.dart` tests |
| M06-045 | Oversized route data is refused before storage | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `max_polyline_bytes`; `RouteValidatorTest` |
| M06-046 | Ownership and IDOR across calculate, read and select | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `TripRouteOwnershipTest` (9); integration run (6 IDOR assertions) |
| M06-047 | Route ids are uuids and are resolved within their trip | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `TripRouteApiTest` |
| M06-048 | Mass assignment: measured fields cannot come from a client | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Empty `$fillable`; tamper test in the integration run |
| M06-049 | Provider failure, rate limit and invalid response are told apart | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-12/13/14`; 11 error codes |
| M06-050 | Cost control: freshness window, no calculation on read or rebuild | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 6 backend + 4 Flutter tests count provider calls |
| M06-051 | Live Google Routes API verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | **PENDING — environment unavailable** | KI-012: no key, and every alternative provider is blocked by egress policy |
| M06-052 | Alternative-route runtime test | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | **NOT APPLICABLE for this test response** | The configured provider returned one route; nothing was fabricated to test against |
| M06-053 | Live map SDK render (tiles, camera, markers on a device) | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ⛔ | ✅ | **PENDING — environment unavailable** | KI-011: no Maps key, no Android SDK, no macOS host |
| M06-054 | Offline: a stored route is kept and labelled | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-15`; `route_controller_test.dart` |
| M06-055 | Offline with nothing stored is an offline state, not an empty map | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-16` |
| M06-056 | Home, Trips and the trip detail carry the route figures | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-08/09/10` |
| M06-057 | "Travel time", never "ETA" | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Live run asserts "ETA" appears nowhere |
| M06-058 | Delhi → Jaipur end-to-end journey | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | Live run, 20 states; integration run, 21 assertions |
| M06-059 | Selection persists across a reload | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration run; DB: 1 selected row per trip |
| M06-060 | Responsive at 320/360/430dp, long names and large text | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-17/18/19`; 3 layout tests |
| M06-061 | Dark mode | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-20` |
| M06-062 | Accessibility: labels, touch targets, semantics for the map fallback | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `route_screen_test.dart` |
| M06-063 | Route geometry absent from logs and analytics | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteLoggingTest` (7); live log grep, 13 needles, 0 hits |
| M06-064 | Observability: eight route events recorded by record and actor | ➖ | ✅ | ➖ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Event counts in the evidence file |
| M06-065 | Android runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **PENDING — environment unavailable** | KI-001 |
| M06-066 | iOS runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **PENDING — environment unavailable** | KI-002 |
| M06-067 | Live-view inspection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 20 states, no application errors |
| M06-068 | Database verification | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Direct queries in the evidence file |
| M06-069 | Documentation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `21-*.md` created + 13 documents updated |
| M06-070 | Modules 01–05 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | 527 backend + 382 Flutter + 29 web; 3 integration runs; Module 05 live view |

### Summary

66 of 70 Module 06 requirements are COMPLETE or PASSED. Four are not, and none of
the four is a code failure:

- **M06-051 Live Google Routes API verification = PENDING — environment
  unavailable.** No Routes API key is configured here, and every alternative
  routing provider (OSRM, Valhalla, OpenRouteService, Mapbox, GraphHopper,
  TomTom) is refused by this environment's egress policy. The adapter is verified
  against a stubbed HTTP transport by 28 tests; it has not answered a real
  request. KI-012.
- **M06-052 Alternative-route runtime test = NOT APPLICABLE for this test
  response.** The configured provider returned a single route for the test
  journey. No second route was fabricated in order to have something to select.
- **M06-053 Live map SDK render = PENDING — environment unavailable.** No Maps
  SDK key, no Android SDK (KI-001) and no macOS host (KI-002), so every live
  screenshot shows the documented map-unavailable state. KI-011.
- **M06-065 / M06-066 Android and iOS runtime verification = PENDING —
  environment unavailable.** KI-001, KI-002.

The ID range grew from the specification's minimum of 47 to 70 because several of
its requirements covered two or three distinguishable things each — the three key
restriction contexts, the six route states, offline-with-a-route versus
offline-without — and splitting them keeps each row independently verifiable.
Nothing was removed.

---

## Module 07 — Restaurant Discovery Along the Selected Route

Role for every row below is **Customer**. FE = Flutter UI. "PASSED (device
pending)" carries the same meaning as in Modules 02–06: built, integrated against
the real API, tested and visually inspected in a rendered app, but not run on an
Android emulator or iOS simulator (KI-001, KI-002).

Screenshot names refer to the Module 07 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md) and captured under
`docs/evidence/module-07/`.

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M07-001 | Discovery entry: the "Find food on this route" CTA is real | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01`; `route_screen_test.dart` |
| M07-002 | Route validation before any search | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `TripRestaurantApiTest`; integration run |
| M07-003 | Restaurant discovery data model | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Migration; `SHOW COLUMNS` in the evidence file |
| M07-004 | Centralised eligibility service | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RestaurantEligibilityTest` (13), 72 scope/service combinations |
| M07-005 | Verification check | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Same; integration run |
| M07-006 | Status check (suspended, disabled, draft, closed) | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Same |
| M07-007 | Coordinates required; never derived from an address | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RestaurantEligibilityTest` |
| M07-008 | Opening hours, in the restaurant's own timezone | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RestaurantAvailabilityTest` (13) |
| M07-009 | Availability, including temporary pause | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-05`; integration run |
| M07-010 | Route corridor, configurable | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `config/foodonthego.php`; `RestaurantDiscoveryServiceTest` |
| M07-011 | Indexed geospatial candidate search | ➖ | ✅ | ➖ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `DiscoveryPerformanceTest` — 2 000 rows, candidate set far smaller |
| M07-012 | Point-to-route proximity | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteGeometryTest` (11); integration run matches seeded offsets exactly |
| M07-013 | Detour distance | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE (see M07-055) | `RestaurantDiscoveryServiceTest` |
| M07-014 | Detour duration | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE (see M07-055) | Same |
| M07-015 | Detour threshold excludes an awkward stop | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE (runtime NOT APPLICABLE) | `RestaurantDiscoveryServiceTest`: "a geometrically close restaurant with a long detour is excluded"; see M07-055 |
| M07-016 | Distance ahead | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RouteGeometryTest`; integration run |
| M07-017 | Route progress fraction | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | API returns 0.28 for a fixture seeded at 0.28 |
| M07-018 | Behind-route handling | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11`; integration run: flagged and listed last |
| M07-019 | Deterministic, explainable ranking | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `DiscoveryRankingTest` (11) |
| M07-020 | Discovery API | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `TripRestaurantApiTest` (17) |
| M07-021 | Result limit | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RestaurantDiscoveryServiceTest` |
| M07-022 | Discovery cache | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration run: second call `from_cache = true` |
| M07-023 | Cache invalidation on a material change | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Suspension removes a restaurant immediately, in both the unit suite and the live run |
| M07-024 | Discovery map | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | `state-08`; KI-011 |
| M07-025 | Restaurant markers, only for results | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | `DiscoveryMapView`; KI-011 |
| M07-026 | Discovery list, in journey order | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02`; integration run |
| M07-027 | Map/list toggle preserving state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-08/09`; a toggle never re-searches |
| M07-028 | Marker and card synchronisation | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | One field drives both; `discovery_screen_test.dart` |
| M07-029 | Restaurant preview card | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-02/03` |
| M07-030 | Cuisine, as declared and never inferred | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `TripRestaurantApiTest` |
| M07-031 | Price level, only where declared | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | And spoken as a word, not only as symbols |
| M07-032 | Rating: absent rather than invented | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-06`; every real row's rating is null |
| M07-033 | Facilities preview | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-02` |
| M07-034 | Availability chip, in words | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-05` |
| M07-035 | Loading state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `discovery_screen_test.dart` |
| M07-036 | Empty state, with the corridor named | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-15` |
| M07-037 | Error states, told apart | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-12/13/14` |
| M07-038 | Offline state, cached and cold | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-16/17` |
| M07-039 | Foreign trip protection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `TripRestaurantOwnershipTest` (6); integration run |
| M07-040 | Customer-safe response, no private column | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Raw-body assertion over 13 needles, in both suites |
| M07-041 | Rate limiting | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `TripRestaurantApiTest`: the fourth call is 429 |
| M07-042 | Provider cost control | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Corridor first, capped budget, closest-first, cached; asserted by call counting |
| M07-043 | Performance | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `DiscoveryPerformanceTest`; measurements in the evidence file |
| M07-044 | Android runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **PENDING — environment unavailable** | KI-001 |
| M07-045 | iOS runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **PENDING — environment unavailable** | KI-002 |
| M07-046 | Backend unit and API tests | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 693 passing |
| M07-047 | Flutter unit and widget tests | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 453 passing |
| M07-048 | Integration test, no mocks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `tool/discovery_smoke.dart`, 22 assertions |
| M07-049 | Live-view inspection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 21 states, no application errors |
| M07-050 | Database verification | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Direct queries in the evidence file |
| M07-051 | Privacy review | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `DiscoveryLoggingTest` (5); live log sweep |
| M07-052 | Documentation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `22-*.md` created + 13 documents updated |
| M07-053 | Modules 01–06 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | Full suites plus four integration runs and two live-view runs |
| M07-054 | Module 08 handoff | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Filter-ready fields stored, indexed and returned; documented |
| M07-055 | Live routing-provider detour figures | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | **PENDING — environment unavailable** | KI-012: no Routes key, so detour is measured against a straight-line road network |
| M07-056 | Alternative-route discovery | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | **NOT APPLICABLE for this test response** | Discovery reads the *selected* route by construction; the configured provider returns one route, so there is no alternative to select |
| M07-057 | Live map render with markers | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ⛔ | ✅ | **PENDING — environment unavailable** | KI-011 |
| M07-058 | Marker clustering | ✅ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ⛔ | ✅ | **NOT IMPLEMENTED — documented** | One marker per result, capped at 25. The marker layer is built so clustering can be added without changing the data; see `22-*.md` |
| M07-059 | Responsive at 320/360/430dp, long names, large text | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-18/19/20`; three layout tests |
| M07-060 | Dark mode | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-21` |
| M07-061 | Accessibility | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | One sentence per card; price as a word; availability as words |
| M07-062 | No N+1 queries | ➖ | ✅ | ➖ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `DiscoveryPerformanceTest`: the query count does not grow with the result count |
| M07-063 | Duplicate-request prevention in the client | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `discovery_controller_test.dart`: rebuilds, view switches and rapid opens all cost one request |
| M07-064 | No duplicate restaurants in a result | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RestaurantDiscoveryServiceTest` |
| M07-065 | Route-crossing edge case | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RouteGeometryTest`: a point between two legs projects to the earlier one |
| M07-066 | Test fixtures never masquerade as production | ➖ | ✅ | ➖ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `[TEST]`-prefixed, computed positions, seeder refuses production |

### Summary

60 of 66 Module 07 requirements are COMPLETE or PASSED. Six are not, and none of
the six is a code failure:

- **M07-055 Live routing-provider detour figures = PENDING — environment
  unavailable.** No Routes API key here, so the detour is measured against the
  development provider's straight-line road network. Every in-corridor stop
  therefore has a trivially small detour, and the detour *threshold* cannot
  exclude anything at runtime. The exclusion rule itself is covered by
  `RestaurantDiscoveryServiceTest` with a provider the test controls, and the
  integration run records `Detour-threshold exclusion = NOT APPLICABLE` rather
  than passing quietly. KI-012.
- **M07-056 Alternative-route discovery = NOT APPLICABLE for this test
  response.** Discovery reads whichever route is *selected*, so choosing an
  alternative changes the results by construction — but the configured provider
  returns a single route, so there is no alternative to select. No second route
  was fabricated to test against.
- **M07-057 Live map render = PENDING — environment unavailable.** KI-011: no
  Maps SDK key, no Android SDK, no macOS host, so every screenshot shows the
  documented map-unavailable state.
- **M07-058 Marker clustering = NOT IMPLEMENTED, and documented as such.** With a
  result limit of 25 the map is legible without it. This is a deliberate scope
  decision rather than an oversight, and the marker layer is built so clustering
  can be introduced without changing the data.
- **M07-044 / M07-045 Android and iOS runtime verification = PENDING —
  environment unavailable.** KI-001, KI-002.

The ID range grew from the specification's 54 to 66 because several of its
requirements covered two or three distinguishable things each — the live
provider versus the threshold rule it exercises, offline-with-results versus
offline-without, the map render versus the marker layer — and splitting them
keeps each row independently verifiable. Nothing was removed.

---

## Module 08 — Restaurant search, filters, sorting and discovery ranking

Screenshot names refer to the Module 08 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md) and captured under
`docs/evidence/module-08/`.

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M08-001 | Search field on discovery | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-01`; `discovery_filters_screen_test.dart` |
| M08-002 | Restaurant-name search | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-02`; `SearchMatcherTest`; integration run |
| M08-003 | Cuisine search | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `SearchMatcherTest`; integration run |
| M08-004 | Search debounce (350 ms) and stale-request cancellation | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `discovery_refine_controller_test.dart`: one word = one request |
| M08-005 | Search clear | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-05`; clear button appears only when there is something to clear |
| M08-006 | Search empty state, distinct from the others | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-04`; names the term, offers Clear search |
| M08-007 | Search combined with filters | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `DiscoveryRefinerTest`; integration run |
| M08-008 | Cuisine filter, by slug | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-12`; generated slug column |
| M08-009 | Multi-cuisine filter is an OR | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-15`; documented in `23-*.md` |
| M08-010 | Availability filter — Open now | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `AvailabilityFilter::matches()`; integration run |
| M08-011 | Availability filter — Taking orders, distinct from Open | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-24`: a paused restaurant is open and excluded |
| M08-012 | Rating filter | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | **DEFERRED — no real rating data** | `rating_available: false`; no control rendered (`state-09`); nothing invented |
| M08-013 | Price filter, on normalised levels 1–4 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration run: level 1 returns exactly one fixture |
| M08-014 | Facility filter, by slug | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Generated slug column; integration run |
| M08-015 | Multiple facilities are an AND | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-18`; documented; integration run |
| M08-016 | Maximum-detour filter, in seconds | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE (arithmetic) | `state-10`; cannot exclude at runtime under KI-012 |
| M08-017 | Distance-ahead filter | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE (backend) | `DiscoveryRefinerTest`; API test. Not surfaced in the sheet — see note below |
| M08-018 | Filter bottom sheet | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-07/08/09/10` |
| M08-019 | Draft filter state | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11`; two taps, zero requests |
| M08-020 | Apply filters | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-12`; re-applying an unchanged query costs no request |
| M08-021 | Active filter chips | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (device pending) | `state-13`; labels, never slugs |
| M08-022 | Remove a single filter | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-16`; removes its value, not its group |
| M08-023 | Clear all (keeps the search) | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-17`; documented |
| M08-024 | Filter badge with a count | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-14`; counts values, not groups; in the accessible name |
| M08-025 | Result count | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-03`: "3 of 12 stops" only while something is filtering |
| M08-026 | Filtered empty state, distinct from an empty road | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-18`; `eligible_total` and `filtered_empty` |
| M08-027 | Map/list filter synchronisation | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PASSED (map render pending) | `state-23`; one result set drives both; KI-011 |
| M08-028 | Selected marker cleared when it is filtered out | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `clearSelection` on every new result set |
| M08-029 | Filter state persistence across map/list | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | A toggle never re-searches; state lives in the controller |
| M08-030 | Recommended sort (default) | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `DiscoveryRankingTest` (14) |
| M08-031 | Lowest-detour sort | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-20`; integration run |
| M08-032 | Soonest-along-route sort | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-22`; integration run asserts ascending |
| M08-033 | Highest-rated sort | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | **NOT AVAILABLE — no rating data** | `state-21`; refused with a reason, never silently downgraded |
| M08-034 | Price low-to-high sort | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integration run asserts ascending price levels |
| M08-035 | Ranking model | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Four normalised terms, weighted mean; `DiscoveryRankingTest` |
| M08-036 | Ranking weights centralised in configuration | ➖ | ✅ | ➖ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `config/foodonthego.php`; five `DISCOVERY_WEIGHT_*` env keys |
| M08-037 | Search relevance in the ranking | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `test_an_exact_name_match_outranks_a_more_convenient_stop` |
| M08-038 | Backend query validation | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 12 malformed shapes, each a 422 naming its field |
| M08-039 | Pagination | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `meta.page/per_page/last_page/has_more`; append + de-duplicate |
| M08-040 | Pagination resets on any query change | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `DiscoveryQuery.copyWith` returns to page 1 |
| M08-041 | Cache key covers the route | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Two customers on different roads, integration + API tests |
| M08-042 | Cache normalisation of equivalent filters | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `facilities=restroom,parking` → `[parking, restroom]` |
| M08-043 | Cache invalidation on a status change | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Integration run suspends a restaurant mid-session |
| M08-044 | Search security | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Three injection payloads; the table is intact afterwards |
| M08-045 | Filter security | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Shape-checked slugs, bounded integers, enum sorts |
| M08-046 | Rate limiting on filtered calls | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | The fourth call is 429, filter or no filter |
| M08-047 | Provider cost protection | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Eight variations, zero extra provider calls; zero queries measured |
| M08-048 | Android runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **PENDING — environment unavailable** | KI-001 |
| M08-049 | iOS runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **PENDING — environment unavailable** | KI-002 |
| M08-050 | Accessibility | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | M08-B02 fixed; 1.6× text; chip and badge names |
| M08-051 | Backend unit and API tests | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 741 passing; 106 new test methods |
| M08-052 | Flutter unit and widget tests | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 539 passing; 90 new test cases |
| M08-053 | Integration test, no mocks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `tool/discovery_filters_smoke.dart`, 28 checks |
| M08-054 | Live-view inspection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 28 states, no application errors |
| M08-055 | Performance measured | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Refine: 0.15–0.6 ms, **0 queries**, at 8 and at 5 008 rows |
| M08-056 | Documentation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `23-*.md` created + 13 documents updated |
| M08-057 | Modules 01–07 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | Full suites plus five integration runs |
| M08-058 | Module 09 handoff | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Route data survives every filter and sort; documented in `23-*.md` |
| M08-059 | Facet metadata, route-specific | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Added during implementation. Counts before filters; no hard-coded client list |
| M08-060 | Stale-response cancellation under real latency | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Added during implementation. Generation check, tested with scripted delays |
| M08-061 | Offline behaviour: filters never claim a server confirmation that did not happen | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Added during implementation (M08-B05). Chips revert to the query the visible results came from |

### Requirements that are not a plain PASS, and why

- **M08-012 Rating filter = DEFERRED.** There is no reviews module and
  `rating_average` is null for every row. The filter is implemented, validated
  and tested against controlled data; at runtime the facets report
  `rating_available: false` and the client renders no rating control at all. It
  switches itself on the day a rating is written. **Nothing is fabricated to
  make it look functional** — that is the requirement, not a shortfall against
  it.

- **M08-033 Highest-rated sort = NOT AVAILABLE** for the same reason. It is
  advertised in the facets with `available: false` and a reason, and a request
  for it is refused with a 422 rather than silently downgraded to recommended.

- **M08-016 Maximum-detour filter: arithmetic verified, runtime exclusion NOT
  APPLICABLE.** Under `ROUTE_PROVIDER=development` (KI-012) the road network is
  a straight line, so no in-corridor stop can exceed any ceiling the filter can
  set. The comparison is tested with detours the test controls
  (`DiscoveryRefinerTest`), and the integration run says so in its output rather
  than letting a reader assume it was exercised.

- **M08-017 Distance-ahead filter: backend complete, not surfaced in the sheet.**
  The parameter is implemented, validated, tested and documented. It is not
  offered as a control because the sheet already carries five groups and the
  spec's own guidance is to avoid cluttering the MVP with near-duplicate
  distance controls — extra travel time is the signal a traveller acts on. A
  client can send it today; adding the control is UI work, not backend work.

- **M08-048 / M08-049 Android and iOS runtime verification = PENDING —
  environment unavailable.** KI-001: no Android SDK, and `dl.google.com` is
  blocked by the egress policy, so it cannot be installed. KI-002: no macOS
  host. Verification was done against a release **web** build of the same
  Flutter code, driven through its real semantics tree. That is a real runtime,
  and it is not an Android device; calling it one would be a false claim.

- **M08-027 Map/list synchronisation: PASSED, map render pending.** The filtered
  set demonstrably drives both views from one piece of state, and the map view
  reports its own count. What cannot be inspected is markers on a rendered
  Google map — KI-011, no Maps SDK key.

---

## Module 09 — Restaurant details, facilities, availability and customer preview

Screenshot names refer to the Module 09 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md) and captured under
`docs/evidence/module-09/`.

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M09-001 | Detail navigation from a discovery result | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01`; the Module 09 placeholder is gone |
| M09-002 | Restaurant detail API, route-aware | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `RestaurantDetailApiTest` (30); integration run |
| M09-003 | Authentication required | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 401 with and without `Accept: application/json` |
| M09-004 | Trip ownership | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `ownedByOrFail()`; 404, and the body says nothing |
| M09-005 | Module 07 eligibility, unbypassable | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Structural: the lookup is inside the discovery result |
| M09-006 | Suspended direct access blocked | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 404, same status as a missing one; integration run |
| M09-007 | Pending direct access blocked | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Same; disabled and permanently closed too |
| M09-008 | Customer-safe response | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Raw-body assertion, 16 needles, in both suites |
| M09-009 | Restaurant name, including long ones | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Wraps; 60-character name tested at 320 dp |
| M09-010 | Description, only where real | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-06`; omitted entirely for `Bare Bones Stop` |
| M09-011 | Hero image | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-04` |
| M09-012 | Image gallery | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Counter and swipe; not offered for a single image |
| M09-013 | Image fallback and load failure | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-15`; branded, never a broken icon |
| M09-014 | Cuisines, as declared | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01`; never inferred |
| M09-015 | Rating summary | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | **NOT APPLICABLE — no rating data** | Field is null; parser and widget tested with controlled data |
| M09-016 | No-rating state | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-05`: **New**, never `0.0` |
| M09-017 | Price level | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Real metadata; announced as a word |
| M09-018 | No-price state | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `Bare Bones Stop` shows no price at all |
| M09-019 | Availability, backend-authoritative | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RestaurantOrderingState`, five cases |
| M09-020 | Accepting-orders state | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-03`; live CTA only here |
| M09-021 | Paused state | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11`; open, and not orderable |
| M09-022 | Closed state | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-12`, with the next opening |
| M09-023 | Opening hours, today and the week | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-07/08`; closed days included |
| M09-024 | Multiple opening windows | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-14`; the gap is shut |
| M09-025 | Overnight hours | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-13`; open at 01:00, asserted at a fixed clock |
| M09-026 | Timezone handling | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Restaurant's zone from server time; DST zone tested |
| M09-027 | Facilities, as declared | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-06`; icon, label and semantics each |
| M09-028 | Route distance ahead | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-02`; identical to the card's |
| M09-029 | Route time ahead | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Same |
| M09-030 | Detour duration | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE (arithmetic) | Magnitude not meaningful under KI-012 |
| M09-031 | Detour distance | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Carried; the card shows time, which is the signal |
| M09-032 | Route data reuse — no provider call | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 10 of 10 opens from cache; measured |
| M09-033 | Route change invalidation | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Cache keyed per route; stale endpoints 409 |
| M09-034 | Location preview | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE (map render pending) | `state-09`; returns to the discovery map. KI-011 |
| M09-035 | View Menu CTA | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | State is the ordering state; Module 10 placeholder behind it |
| M09-036 | Loading skeleton | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-21`; the card's name drawn immediately |
| M09-037 | Error states, told apart | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-17/18/19` |
| M09-038 | Offline cache, with an honest age | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-20`; real `generated_at`, never fabricated |
| M09-039 | Pull to refresh | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | And a withdrawn restaurant loses its page |
| M09-040 | Discovery state restoration | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-10`; search, filters, sort, and zero requests |
| M09-041 | Media security | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Delivery URLs only; unmoderated images unreachable |
| M09-042 | API privacy inspection | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Raw body, both suites |
| M09-043 | Request race handling | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Generation check, tested with scripted delays |
| M09-044 | Android runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ➖ | ✅ | **PENDING — environment unavailable** | KI-001 |
| M09-045 | iOS runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ✅ | **PENDING — environment unavailable** | KI-002 |
| M09-046 | Accessibility | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | M09-B01 fixed; 1.6× text; per-day nodes |
| M09-047 | Backend unit and API tests | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 801 passing; 60 new test methods |
| M09-048 | Flutter unit and widget tests | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 613 passing; 74 new test cases |
| M09-049 | Integration test, no mocks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `tool/restaurant_detail_smoke.dart`, 25 checks |
| M09-050 | Live-view inspection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 25 states, no application errors |
| M09-051 | Performance measured | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | 14 ms per open; 14 queries, constant |
| M09-052 | Cost control | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | No provider call; asserted, not assumed |
| M09-053 | Documentation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `24-*.md` created + 13 documents updated |
| M09-054 | Modules 01–08 regression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | PASS | Full suites plus six integration runs |
| M09-055 | Module 10 handoff | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | `can_order` / `can_browse_menu`; documented |
| M09-056 | Read-only customer access | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Added during implementation. Four verbs, none accepted |
| M09-057 | Unsafe text rendered as text | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Added during implementation. Verbatim, never mangled |
| M09-058 | N+1 review, as an assertion | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | COMPLETE | Added during implementation. Query count unchanged by 20 photographs |

### Requirements that are not a plain PASS, and why

- **M09-015 Rating summary = NOT APPLICABLE.** No restaurant has a rating,
  because there is no reviews module. The field is null, the parser and the
  widget are tested against controlled data, and the screen shows **New**.
  Nothing is fabricated to make the section look populated — that is the
  requirement, not a shortfall against it.

- **M09-030 Detour duration: arithmetic verified, magnitude not meaningful.**
  Under `ROUTE_PROVIDER=development` (KI-012) the road network is a straight
  line, so every in-corridor detour is a second or two. What this module
  establishes about detour is the part it owns: the page shows the *same* figure
  the card did, and reached it without calling a provider again.

- **M09-034 Location preview: PASSED, map render pending.** The section shows
  the address, the published phone where there is one, and a control that
  returns to the discovery map, which already draws this restaurant against the
  route. What cannot be inspected is markers on a rendered Google map — KI-011,
  no Maps SDK key. A second full map on this screen was rejected as the same
  screen twice.

- **M09-044 / M09-045 Android and iOS runtime verification = PENDING —
  environment unavailable.** KI-001: no Android SDK, and `dl.google.com` is
  blocked by the egress policy. KI-002: no macOS host. Verification was done
  against a release **web** build of the same Flutter code, driven through its
  real semantics tree. That is a real runtime and it is not an Android device.
