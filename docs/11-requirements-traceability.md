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
