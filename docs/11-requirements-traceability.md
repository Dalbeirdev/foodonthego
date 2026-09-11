# 11 — Master requirements traceability matrix

Permanent. Requirements are never removed; they change status.

**Statuses:** NOT STARTED · DESIGNING · FRONTEND COMPLETE · BACKEND COMPLETE · INTEGRATION COMPLETE ·
TESTING · BLOCKED · FAILED · PASSED · VERIFIED · COMPLETE

Legend: ✅ done · ➖ not applicable to this requirement · ⛔ blocked by environment

---

> ### ⚠ Read this before the Android and iOS columns
>
> **The `⛔` marks and "environment unavailable" reasons on the ANDROID and iOS rows are
> stale, and they understate what has been verified.** They were written when this project
> had no runner that could build or run the app. It has had one for several modules.
>
> *This note covers those rows only.* The live-provider rows that say the same words —
> Google Places (KI-010), the Maps SDK render (KI-011), the Routes API (KI-012) — are
> **genuinely** environment-limited: no API keys exist for this project and none were
> invented. Those are accurate as written.
>
> CI today builds the review APK/AAB, installs **that artefact** on a Pixel 6 / API 34
> emulator, and runs the on-device suite; and on `macos-latest` it builds
> `flutter build ios --no-codesign` and runs the same suite on an iPhone simulator.
> **29 integration tests pass on each platform, every pull request.**
>
> **M02-017 and M02-018 are now VERIFIED on device.**
> `integration_test/module_02_shell_test.dart` renders the five destinations and taps
> through each of them on a real emulator and simulator. First run: the iOS simulator
> reported **31 tests passed**, up from 29, so the file executed rather than being
> silently skipped. The Android emulator job passed the same `flutter test
> integration_test/` invocation; its count was not read from the log, so it is recorded
> here as green rather than as a number.
>
> **Module 04 followed, and the count is now 34 on iOS** (`d22d176`, read from the
> log: `🎉 34 tests passed.`). `integration_test/module_04_profile_test.dart` opens
> the profile editor the way a customer does, types the customer's own values back
> through a real software keyboard, saves to the live API, and opens the saved
> addresses screen. **So M04 is off the unverified list**, and what remains without
> a device test is **Modules 03, 05 and 06** — OTP sign-in, the trip planner, and
> routing and the map layer.
>
> **And Android now reports a number too: 34, the same as iOS.** That is the first
> time it has been read in this project. The count had never been *unavailable* —
> it was unreadable, pushed out of the log tail by a second emulator boot and the
> job's cleanup. `ci-device-report.sh` now emits it as a check-run annotation,
> which the API serves regardless of what printed afterwards (KI-038):
>
> ```
> [notice] 'iOS device tests'     :: 34 tests passed (flutter test exited 0)
> [notice] 'Android device tests' :: 34 tests passed (flutter test exited 0)
> ```
>
> So the caveat carried on every Android row since Module 02 is **retired**. Both
> platforms run the same 34 tests and both counts have been read.
>
> **What is still genuinely unverified on a device is narrower again.**
> The on-device suite covers **Modules 11–14** (add to cart, cart management, pickup
> timing, checkout), the Module 16 confirmation and Module 17 tracking screens, the
> Module 02 shell and now **Module 04** (profile and addresses). It does **not**
> exercise **Modules 03, 05 and 06** — OTP sign-in, the trip planner, or routing and
> the map layer. Those rows are correct that they are unverified on a handset; they
> are **wrong about why**.
>
> The blocker changed from *"there is no environment"* to *"no device test has been
> written for this module"*, and that changes what someone would do about it: write the
> tests, rather than wait for a runner that already exists.
>
> Individual rows below are left as written rather than rewritten in bulk — 37 of them,
> in about twenty different phrasings, and a botched sweep through a traceability matrix
> would be worse than the staleness it fixed. Read them with this note in hand.
>
> Also still true, and unchanged: **no physical handset** has run the app on either
> platform, the iOS simulator matrix is **one device** rather than three, and there is no
> signed IPA. See KI-001 and KI-002 in [13-known-issues.md](13-known-issues.md), both
> corrected.

---

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

**Android runtime verification = PENDING — no device test for this module.** (Not an
environment limit: CI runs the on-device suite on an emulator every pull request. See the
note at the top of this document.)
**iOS runtime verification = PENDING — no device test for this module.** (Not an
environment limit: CI runs the on-device suite on a simulator every pull request. See the
note at the top of this document.)

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

**Android runtime verification = PENDING — no device test for this module.** (Not an
environment limit: CI runs the on-device suite on an emulator every pull request. See the
note at the top of this document.)
**iOS runtime verification = PENDING — no device test for this module.** (Not an
environment limit: CI runs the on-device suite on a simulator every pull request. See the
note at the top of this document.)

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
- **M05-046 Android runtime verification = PENDING — no device test for this module.**
  (Not an environment limit; see the note at the top.)
  KI-001.
- **M05-047 iOS runtime verification = PENDING — no device test for this module.**
  (Not an environment limit; see the note at the top.)
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

---

## Module 10 — Menu, categories and menu item browsing

Screenshot names refer to the Module 10 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md) and captured under
`docs/evidence/module-10/`.

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M10-001 | Menu opened from the restaurant page | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01`; the Module 10 placeholder is gone |
| M10-002 | Menu API nested under trip and restaurant | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `routes/api.php`; smoke check 2 |
| M10-003 | Categories in the operator's order | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 3; `state-07` |
| M10-004 | Items in the operator's order within a category | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RestaurantMenuApiTest` |
| M10-005 | Category name and optional description | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01` |
| M10-006 | Item name | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01` |
| M10-007 | Item description, or nothing | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-05` (Papad); smoke check 5 |
| M10-008 | Item price, from a real record | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-02` |
| M10-009 | **Money stored as integer minor units** | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `unsignedInteger base_price_minor`; `MoneyTest` (10) |
| M10-010 | No floating point for authoritative money | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `Money::tryFromMinor` rejects floats and decimal strings |
| M10-011 | Currency carried with every amount | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `{amount_minor, currency}` |
| M10-012 | Centralised currency formatting; no hard-coded symbol | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `Money.format()` via `intl`; smoke check 9 (no `₹` on the wire) |
| M10-013 | Zero price rendered as a price | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-09` — Table Water, ₹0 |
| M10-014 | Large price grouped by locale | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-10` — ₹12,999 |
| M10-015 | Item image where one exists | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01` |
| M10-016 | **No stock imagery for an unphotographed dish** | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Monogram fallback; `state-05` |
| M10-017 | Thumbnail falls back to the full image | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RestaurantMenuApiTest`; `menu_models_test` |
| M10-018 | Image load failure degrades to the fallback | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `errorBuilder` in `MenuItemCard` |
| M10-019 | **Preparation time is not a pickup ETA** | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | "15 min to cook"; screen-reader disclaimer; `state-13` |
| M10-020 | Absurd preparation time withheld | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `preparationMinutes()` bounds 0 < n ≤ 240 |
| M10-021 | **Dietary type only from structured data** | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-03`; Dal Makhani has no badge |
| M10-022 | Dietary type never inferred from a name | ✅ | ✅ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | No inference code exists; asserted in `menu_screen_test` |
| M10-023 | **No invented allergen information** | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | NOT APPLICABLE — see note | No allergen column, UI or wire string; smoke asserts absence |
| M10-024 | **Spice level only from real data** | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Out-of-range withheld; never inferred |
| M10-025 | Sold-out item shown and marked | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-04` |
| M10-026 | Unknown stock status is not orderable | ✅ | ✅ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Both enums degrade to sold out |
| M10-027 | Inactive item never appears | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-06`; smoke checks 10 and 22 |
| M10-028 | Inactive category never appears | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-06`; smoke check 11 |
| M10-029 | An item inside an inactive category is unreachable | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 21 — Gulab Jamun by id |
| M10-030 | Time-limited category respected | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Breakfast 06:00–11:00; smoke check 12 |
| M10-031 | Empty category omitted | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `RestaurantMenuApiTest` |
| M10-032 | Restaurant with no menu is a state, not an error | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-19` |
| M10-033 | Empty search told apart from empty menu | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-16`; `visible_item_count` vs `item_count` |
| M10-034 | Menu search, parameterised | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | In memory; no query to inject into |
| M10-035 | Search length limit ≈100 characters | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 422; client `maxLength: 100` |
| M10-036 | SQL injection in search changes nothing | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 17; four probes |
| M10-037 | Category selector, sticky | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-07` |
| M10-038 | Tapping a section scrolls to it | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-08`; including a section never built |
| M10-039 | Scrolling moves the section highlight | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11` |
| M10-040 | Read-only item preview | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-13` |
| M10-041 | Preview fetched fresh, not echoed | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 20 — a changed price is reflected |
| M10-042 | **No customization, addons, cart, checkout or orders** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-14`; no such code exists |
| M10-043 | **Cross-restaurant item refused (IDOR)** | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 20; `ITEM_NOT_FOUND` |
| M10-044 | Cross-restaurant item impossible in the schema | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Composite FK; MySQL 1452 asserted |
| M10-045 | Suspended restaurant's menu refused by uuid | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 25 — 404 |
| M10-046 | Another customer's trip refused | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | smoke check 24 — `TRIP_NOT_FOUND` |
| M10-047 | **No operator-private field on the wire** | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Allow-list; raw-body assertion over 13 needles |
| M10-048 | No internal database key exposed | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | uuids only; smoke check 29 |
| M10-049 | **Menu is read-only to a customer** | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Six verb/path pairs refused; no write method in the app |
| M10-050 | **No N+1 on the menu endpoint** | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 2 queries at 6 items and at 500 |
| M10-051 | **Opening a menu triggers no route calculation** | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Stub count flat; real provider log flat |
| M10-052 | Large menu (20 categories / 500 items) | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Served whole, 2 queries, ~130 KB |
| M10-053 | Payload size within reason | ➖ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Asserted < 600 KB at 500 items |
| M10-054 | Closed or paused restaurant still browsable | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-20`, `state-21` |
| M10-055 | Offline keeps the menu and says so | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-24` |
| M10-056 | **Test seeders are development-only and marked** | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Refuses in production; `[TEST]` prefix; not in `DatabaseSeeder` |
| M10-057 | Android and iOS runtime verification | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ⛔ | ⛔ | ✅ | PENDING — environment | KI-001, KI-002 |

### Notes on the entries that are not a plain PASS

- **M10-023 Allergen information = NOT APPLICABLE.** There is no allergen
  column, no allergen UI and no allergen string anywhere on the wire, because no
  restaurant has declared any. Inventing a field to demonstrate the requirement
  would be exactly the fabrication the requirement forbids. What is verified is
  the honest behaviour: the integration run asserts the word "allergen" does not
  appear in the response body. When operator-declared allergens exist, they will
  be shown the way every other optional field here is — present when published,
  absent when not.

- **M10-014 / M10-012 Locale formatting: verified for `en_IN` and `en_US`.**
  The app ships one locale (English). `Money.format` is asserted against both
  `en_IN` (₹12,999 — Indian grouping) and `en_US` ($249) so the *mechanism* is
  proved locale-driven rather than hard-coded, but no non-English locale is
  shipped to exercise.

- **M10-052 Large menu: generated fixture, not production data.** Twenty
  categories and five hundred items are inserted by the test itself. Production
  data is never used for a load measurement, per the module's own rule.

- **M10-051 Cost control: proved two ways, one of them indirect.** A counting
  stub in `MenuPerformanceTest` shows the provider is never called; the
  integration run counts `route.provider.called` lines in the real log across
  fifteen menu and item requests and finds the count unchanged. Under
  `ROUTE_PROVIDER=development` (KI-012) the provider is not a billed one, so
  what is established is the call count, not a billing figure.

- **M10-057 Android and iOS runtime verification = PENDING — environment
  unavailable.** KI-001: no Android SDK, and `dl.google.com` is blocked by the
  egress policy. KI-002: no macOS host. Verification was done against a release
  **web** build of the same Flutter code, driven through its real semantics
  tree. That is a real runtime and it is not an Android device.

---

## Module 11 — Menu item details, variants, addons, customization and Add to Cart

Screenshot names refer to the Module 11 live-view run recorded in
[15-test-evidence.md](15-test-evidence.md) and captured under
`docs/evidence/module-11/`.

| ID | Feature | FE | BE | API | DB | Sec | Tests | Android | iOS | Docs | Status | Evidence |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | --- | --- |
| M11-001 | Item detail navigation from a real menu item | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-01`; Module 10's sheet deleted |
| M11-002 | Item detail API with customization | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `ItemCustomizationApiTest` (15) |
| M11-003 | Variant model, absolute price | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | ₹329 is the price, not the increment |
| M11-004 | Variant selection changes the price | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-13` |
| M11-005 | Default variant, configured not guessed | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-02`; unavailable default is no default |
| M11-006 | Variant availability | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-03`, `state-14` |
| M11-007 | Modifier group model | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Restaurant-scoped, item-attached |
| M11-008 | Modifier option model | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Unsigned delta |
| M11-009 | Required group | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-04` |
| M11-010 | Optional group | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-05` |
| M11-011 | Minimum selection enforced | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Two codes: required vs min-not-met |
| M11-012 | Maximum selection enforced | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-11` |
| M11-013 | Single select | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-09` — replaces, never adds |
| M11-014 | Multi select | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-10`, `state-11` |
| M11-015 | **Addon architecture decided and documented** | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Modifier groups only; rationale in `26-…md` |
| M11-016 | Paid modifiers | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-10`; never auto-selected |
| M11-017 | Dynamic price preview | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-10`–`state-16` |
| M11-018 | **Backend pricing service** | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `MenuItemPricingService`; the only pricer |
| M11-019 | Money safety | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Integer minor units throughout; no float |
| M11-020 | Quantity selector | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-15`, `state-16` |
| M11-021 | Quantity validation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 0, −1, 999999, "two", 2.5, `true` refused |
| M11-022 | Special instructions | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-17`, `state-18` |
| M11-023 | Note validation and safety | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 300 chars, counted in characters; stored verbatim |
| M11-024 | Item availability before adding | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Re-read in the writing request |
| M11-025 | **Variant unavailable race** | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Smoke check; row changed behind the API |
| M11-026 | **Modifier unavailable race** | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Refused, naming the option |
| M11-027 | **Item sold-out race** | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-26`; nothing added |
| M11-028 | Restaurant pause handling | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-25`; browsing unaffected |
| M11-029 | **Price-change handling** | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-28`; both figures shown |
| M11-030 | Cart model | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Customer, trip, restaurant, currency |
| M11-031 | Cart item model | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Server prices only |
| M11-032 | Modifier snapshots | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Names and deltas at the moment of adding |
| M11-033 | **Cart customer ownership** | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Reached through the trip; no `/carts/{id}` |
| M11-034 | Trip–cart association | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Unique index on a generated column |
| M11-035 | **One restaurant per cart** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-27`; nothing mutated |
| M11-036 | Add to Cart API | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-19` |
| M11-037 | **Server price authority** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | No price field exists in the request |
| M11-038 | **Price tamper protection** | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 8 money fields in one body; real price charged |
| M11-039 | Duplicate tap protection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Guarded in flight *and* by the key |
| M11-040 | Idempotency | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Module 01's middleware, per attempt |
| M11-041 | **Lost-response retry** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | One line at the quantity asked for once |
| M11-042 | Identical configuration merges | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Options sorted before hashing |
| M11-043 | Different configuration separates | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Size, options and note all part of identity |
| M11-044 | Restaurant cart conflict | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Named, and nothing destroyed |
| M11-045 | Trip cart conflict | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Refused, not silently reused |
| M11-046 | Cart badge foundation | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Count and subtotal; no cart screen |
| M11-047 | Offline item read | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | PARTIAL — see note | Detail is not cached; see below |
| M11-048 | **Offline add blocked** | ✅ | ➖ | ➖ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | `state-29`; no fake success |
| M11-049 | Request race handling | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Generation-checked; the newest wins |
| M11-050 | Android testing | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | **PASS** | 8/8 on an API 34 emulator in CI (`c8c1161`) |
| M11-051 | iOS testing | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | **PASS** | 8/8 on a simulator in CI (`c8c1161`), same driver |
| M11-052 | Accessibility | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Sentences, not controls; M11-B04 fixed |
| M11-053 | Backend tests | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 93 new; 957 total |
| M11-054 | Flutter tests | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 86 new; 772 total |
| M11-055 | Integration test | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 48 checks against a live server |
| M11-056 | Database verification | ➖ | ➖ | ➖ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Rows read back out of MySQL |
| M11-057 | Security review | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | Checklist in the completion report |
| M11-058 | Performance | ➖ | ✅ | ✅ | ✅ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 3 customization queries at 1 group or 10 |
| M11-059 | **Cost control** | ➖ | ✅ | ✅ | ➖ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 0 provider calls; stub and real log |
| M11-060 | Live view | ✅ | ➖ | ➖ | ➖ | ➖ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | 30 states in a release build |
| M11-061 | Documentation | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | COMPLETE | `26-…md` created; 12 updated |
| M11-062 | Regression, Modules 01–10 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ | ✅ | COMPLETE | All smoke runs green |
| M11-063 | Module 12 handoff | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ➖ | ✅ | COMPLETE | Recorded at the end of `26-…md` |

### Notes on the entries that are not a plain PASS

- **M11-047 Offline item read = PARTIAL.** The item detail is **not** cached, so
  a customer who opens a dish with no connection sees the load-failure state and
  a retry rather than a stale copy. What the requirement asks for — that
  configuring works offline and only the *add* is blocked — is half met: the
  add is blocked honestly and every selection survives the failure
  (`state-29`), but there is nothing to configure if the page never loaded.

  This is a deliberate omission rather than an oversight. Caching a dish means
  caching its **prices and its availability**, and a customer who configured a
  cached dish would be quoted figures the server has since changed — the exact
  problem `PRICE_UPDATED` exists to prevent, reintroduced one layer down. The
  menu list already caches (Module 10) because a name and a price shown with an
  explicit "offline" banner is honest; a *configurator* built on stale prices is
  not. Revisit when the cart screen exists to explain a stale configuration.

- **M11-050 / M11-051 Android and iOS runtime = PASS, on CI rather than here.**
  The development machine has neither runtime (KI-001: no Android SDK, and
  `dl.google.com` is blocked by the egress policy; KI-002: no macOS host), so
  the `android-device` and `ios-device` jobs run
  `integration_test/module_11_add_to_cart_test.dart` on an API 34 emulator and
  an iPhone simulator, each against a real Laravel server and MySQL brought up
  by `scripts/ci-backend-up.sh`. Eight of eight on both, on `c8c1161`.

  The earlier web run stands as what it always was — a real runtime, and not a
  handset. What the device runs added is what only a device could: real touch
  input through the real hit test, on a 411x890 and a 402x874 screen, which is
  where three defects in the driver showed up that no browser window could have
  surfaced. [15-test-evidence.md](15-test-evidence.md) lists them, and the
  failures that preceded the pass.

- **M11-015 Addon architecture = one system, deliberately.** Add-ons are
  modifier groups. The decision, and the one thing that would justify reversing
  it (per-add-on quantities), are recorded in
  [26-menu-item-customization.md](26-menu-item-customization.md).

---

## Module 12 — cart management, price revalidation and the order summary

- **M12-001 Cart read = `GET /trips/{trip}/cart`.** Lines with their snapshots
  and options, per-line and cart totals. Module 11's badge fields are still in
  the same place; `CartManagementApiTest::test_the_badge_fields_module_11_shipped_are_still_where_they_were`
  is the test that says so.

- **M12-002 Line editing = `PATCH` and `DELETE`.** Quantity `1..CART_MAX_QUANTITY_PER_LINE`,
  re-priced from live menu data through `CartLineRepricer` rather than scaled
  from the snapshot. **Zero is refused**, not read as removal.

- **M12-003 Emptying = `DELETE /trips/{trip}/cart`.** Idempotent: emptying an
  already-empty cart is a success, because a customer who taps twice has got
  what they asked for both times.

- **M12-004 A cart is closed, never deleted.** Five events write `CLOSED`; no
  path deletes a cart row. The rows are what Module 13's orders will point at.

- **M12-005 The order summary is server-calculated**, in integer minor units,
  in one place (`CartTotalsService`). Tax on the subtotal once, rounded half up.
  `CartTotalsTest` covers the boundaries, including a value where the float path
  demonstrably disagrees (7.25% of 200 paise is 14.5 exactly; a float answers
  14).

- **M12-006 Rates and fees are configuration and data, and every default is
  nought.** Not a code decision, and **not yet set for production** — flagged
  for the business. See [14-change-log.md](14-change-log.md).

- **M12-007 Price revalidation = `GET /trips/{trip}/cart/revalidate`**, a read
  that mutates nothing in either direction.
  `CartRevalidationApiTest::test_revalidation_writes_nothing_at_all` calls it
  twice against a cart whose prices and kitchen have all moved, and asserts
  every column is untouched.

- **M12-008 Conflict resolution = two explicit choices**, on the dish the
  customer was adding. No third in which the app decides. The destructive one is
  confirmed with a dialogue naming what will be lost.

- **M12-009 Cost control = zero routing or places calls.** Reading, editing,
  emptying and revalidating a cart call no provider;
  `CartRevalidationApiTest::test_revalidating_calls_no_routing_provider` asserts
  the counter does not move, and carries its own control showing that a cold
  discovery does move it.

- **M12-010 The client never sends a price.** Structural rather than checked:
  `CartRepository` has no price parameter on any method, so there is nothing for
  a modified client to lie in. The API-side assertion is
  `CartManagementApiTest::test_a_price_sent_with_a_quantity_change_is_ignored`,
  which sends eight plausible field names and gets the server's own figures back.

- **M12-011 KI-014 = cleared.** `TripService::discard` closes the trip's active
  cart in the same transaction, and a customer can release one themselves.
  Regression tests in `CartLifecycleApiTest`, and on a device in
  `module_12_cart_test.dart`.

- **M12-050 / M12-051 Android and iOS runtime = PASS, on CI rather than here.**
  The development machine has neither runtime (KI-001, KI-002), so the
  `android-device` and `ios-device` jobs run the whole `integration_test`
  directory on an API 34 emulator and an iPhone simulator, each against a real
  Laravel server and MySQL. **Fifteen of fifteen on both**, on `cbcf4e5` —
  Module 12's seven and Module 11's eight, the latter re-run because the Android
  job now takes the directory rather than one named file.

  Every one of the seven asserts against the **server's rows** after the taps
  rather than against what the screen says. A cart that displays the right
  number while the database holds a different one is precisely the failure this
  module exists to prevent, and a test that only read the screen could not tell
  the two apart.

---

## Module 13 — pickup time selection, arrival window and pre-checkout validation

The module ends when a customer has a valid cart, a feasible selected pickup
window, current pre-checkout validation and a backend-generated
`ready_for_checkout` — and not one step further. No order, no payment, no
pickup code, no restaurant workflow.

### The arithmetic

- **M13-001 Preparation is the maximum of the lines, never the sum.** A kitchen
  cooks several dishes at once. `PreparationEstimateService`; proved live with
  two dishes reading 20 minutes rather than 40 in
  [evidence/module-13-verification-run.txt](evidence/module-13-verification-run.txt).

- **M13-002 Quantity does not multiply preparation.** Three portions of a
  fifteen-minute dish is fifteen minutes. V1 has no evidence about batch sizes
  and inventing a multiplier would be inventing a number.

- **M13-003 Preparation precedence = variant → item → restaurant default →
  platform fallback.** Nought and null are both "not set"; the platform fallback
  is logged every time it is reached, because a menu relying on it is a menu
  somebody has not finished setting up.

- **M13-004 Modifier preparation is NOT APPLICABLE.** There is no column for it
  in this schema. Recorded as absent rather than approximated.

- **M13-005 `earliest_ready_at = now + preparation + buffer`, floored at
  `now + minimum_lead`.** A floor, not an addition: forty minutes of cooking is
  forty, not fifty. `PickupPlanningServiceTest` covers both halves separately,
  because one active cart per journey makes them two tests.

- **M13-006 The operational buffer is a restaurant override falling back to a
  platform default, applied exactly once.** It is a duration and never a charge,
  and it reaches no total. **Zero is a real answer** and is not read as unset.

- **M13-007 `recommended = max(arrival, earliest_ready)`, rounded FORWARD.**
  Rounding back would recommend a time the kitchen cannot meet. Proved live:
  arrival 06:01, ready 05:19, recommendation 06:10.

### Windows

- **M13-008 Windows are generated on a configurable interval and duration**,
  and only where every condition holds: at or after earliest-ready, at or after
  `now + lead`, entirely inside an opening window including its end, at or
  before the last-order cutoff, within the horizon, and the restaurant open and
  accepting orders.

- **M13-009 Every hours comparison happens in the restaurant's own IANA zone**,
  never at a fixed offset. `PickupWindowGeneratorTest` includes a UK
  spring-forward case, and `PickupTimeApiTest` walks the whole flow through the
  jump — with the restaurant's closing hour chosen so that reading the hours as
  UTC gives a different answer, which is what makes the control fire.

- **M13-010 Overnight hours are handled by timezone-aware interval arithmetic**,
  not by special-casing midnight.

- **M13-011 `day_of_week` is 0 for MONDAY.** The one convention in this schema.
  A defect where the generator read Carbon's (Sunday 0) is recorded as
  [BUG-M13-001](13-known-issues.md).

- **M13-012 One window per start, however many opening rows produce it.**
  Overlapping rows are legitimate data; offering "1:00 PM" twice in a list of
  eight is a shorter list than it looks. [BUG-M13-002](13-known-issues.md).

- **M13-013 The last-order cutoff is configurable and defaults to NOUGHT.**
  The schema has no `last_order_at`, and inventing a hidden fifteen-minute rule
  would be a rule no operator agreed to and no customer could discover.

- **M13-014 The horizon binds a window's START.** A window beginning inside the
  horizon and running ten minutes past it is within how far ahead a customer may
  plan; truncating it would drop the last option for no visible reason.

- **M13-015 Which windows are offered is capped from the RECOMMENDATION
  forward**, not from the earliest-ready time. The first eight from earliest-ready
  would all fall before the customer could arrive. When arrival is past every
  window there is no recommendation and the last N are offered — the ones
  nearest to being reachable.

### The ETA boundary

- **M13-016 `ArrivalEstimateProvider` is a seam in the code, not a paragraph in
  a document.** `PlannedRouteArrivalEstimateProvider` is today's implementation;
  the live engine replaces one binding in `PickupServiceProvider` and no
  arithmetic moves.

- **M13-017 This is NOT the ETA engine, and the module does not claim to be.**
  Travel comes from the planned route on the assumption the customer sets off
  now. That is the module's largest approximation and is stated on the class,
  in [28-pickup-time-planning.md](28-pickup-time-planning.md) and here.

- **M13-018 Planning costs no routing-provider call.** Generating windows,
  switching between them, selecting one and pre-checkout validation all read
  rows this platform already holds. The only provider call in this area is a
  journey refresh the customer asks for, which is Module 06's endpoint.

- **M13-019 A stale route is refused, never silently recalculated.**
  `requires_route_refresh` is set and the screen offers **Refresh journey**; the
  app never triggers a billed call on its own.

### Options and selection

- **M13-020 `POST /trips/{trip}/cart/pickup-options`** — a POST because it is a
  calculation over live state whose answers are short-lived and whose side
  effect is writing them down.

- **M13-021 `PUT /trips/{trip}/cart/pickup-selection` takes `pickup_option_id`
  and nothing else.** **There is no field in either request that could carry a
  time.** No signed base64 timing payload: a signed payload still has to be
  verified correctly on every path, and the day one path forgets, a customer
  names their own pickup time.

- **M13-022 Option ids are 256 bits from the CSPRNG, opaque and structureless.**
  No index, no cart id, nothing to read or shift. Asserted on the wire by
  `PickupTimeApiTest::test_the_response_carries_no_timestamp_the_client_could_send_back`.

- **M13-023 OPTION IDOR — one customer cannot use another's id.** The cache key
  is scoped to the customer, which makes it structurally impossible rather than
  merely checked; the record it resolves to also carries the customer and the
  selection service compares it. Two mechanisms for the guarantee the
  specification calls mandatory.

- **M13-024 Expired, forged and belonging-to-somebody-else are indistinguishable.**
  One code for all three. Telling them apart answers "does this id exist" for
  anybody who asks.

- **M13-025 An option is tied to its cart, journey and restaurant**, and a
  customer's own id from a different journey is refused.

- **M13-026 A used option id is retired.** Proved live: replaying the id that
  was just accepted is refused.

- **M13-027 Selection re-checks every condition**: the owner, the cart, the
  journey, the restaurant, the planning fingerprint, and whether the window is
  still one the kitchen can honour. The plan that produced an option was true
  when it was produced; selection is a different moment.

- **M13-028 The chosen window is stored in UTC and reported on the counter's
  clock.** The column holds an instant; `pickup_timezone` travels beside it. Two
  defects came from getting this split wrong — [BUG-M13-003](13-known-issues.md)
  and [BUG-M13-005](13-known-issues.md).

### The planning fingerprint

- **M13-029 A selection is bound to a fingerprint** over the cart's version, the
  selected route's uuid and `calculated_at`, the restaurant's uuid, its
  accepting-orders flag and status, its opening-hours fingerprint, and the
  planning configuration version.

- **M13-030 `carts.version` increments on every CONTENTS change, atomically.**
  Deliberately not on a price change: a dish going up in price does not alter
  how long the kitchen needs, and invalidating a good window over it would be
  caution the customer experiences as breakage.

- **M13-031 The fingerprint ignores the order opening-hours rows were written
  in.** Two identical schedules inserted differently are the same schedule.

- **M13-032 The fingerprint is never published.** It is an internal comparison
  value; returning it would tell a client what the server hashes.

### Selection status

- **M13-033 Only NONE and SELECTED are ever written.** STALE and INVALID are
  conclusions about the customer's intent held against the world, computed by
  `PickupSelectionEvaluator` on every read. A column reading SELECTED after the
  restaurant edits its hours is not wrong because a job failed to run — a column
  cannot know.

- **M13-034 These are deliberately NOT order statuses.** No order exists in this
  module and none can.

### Pre-checkout

- **M13-035 `POST /trips/{trip}/cart/pre-checkout-validate`** — a POST that
  writes nothing. The verb is about caching, not side effects: this renders a
  point-in-time go/no-go, and a stale judgement is somebody at a payment screen
  for a kitchen that has shut. Module 12's `revalidate` reports facts and stays
  a GET.

- **M13-036 `ready_for_checkout` is computed by the backend, in one place.**
  Not a field a request can carry: `test_a_client_cannot_talk_the_server_into_saying_yes`
  posts a body claiming it and gets back no.

- **M13-037 It never says yes over** an unreviewed price rise, a sold-out line,
  a paused kitchen, a stale route, a stale pickup selection, or no selection at
  all. One test each, and each asserts the answer is **no** rather than merely
  that a problem was listed.

- **M13-038 A price that has fallen is reported and does not block.** Nobody
  needs a dialogue to be charged less — but they should be told.

- **M13-039 Validating writes nothing**, including its own conclusion. A
  validator that corrected the thing it was validating would disagree with
  itself on the second run.

### What is not built, and is asserted not to be

- **M13-040 No order, no order number, no pickup code, no payment, no capacity
  reservation.** Tests in both the API suite and the device suite assert the
  `orders`, `order_items`, `payments` and `pickup_codes` tables **do not exist**
  — the check that would catch somebody getting ahead of the module.

- **M13-041 No WebSockets, no FCM, no live GPS tracking, no early/late
  detection, no QR pickup, no restaurant accept/reject, no cooking or ready
  workflow, no multi-day scheduling.** None of these appears in the diff.

### Security and privacy

- **M13-042 Mass assignment is impossible.** Every pickup column is written by
  `forceFill` against names the service states. A request carrying
  `requested_pickup_start_at`, `pickup_selection_status`, `version`,
  `restaurant_id` and `ready_for_checkout` changes none of them, and there is a
  test that sends all five.

- **M13-043 Nothing operational reaches the wire.** No internal notes, no
  commission rate, no owner contact details, no bank reference, no tax
  identifier, no per-line preparation breakdown, and no fingerprint. Asserted by
  searching the raw response body rather than the parsed shape.

- **M13-044 A refusal never names why a restaurant is unavailable.** "Suspended"
  tells anybody who can guess a name something the platform has not published.

- **M13-045 Ownership is proved by the journey in the path**, as everywhere else
  in this API. Another customer's journey is a 404.

### Client discipline

- **M13-046 The Flutter app computes no time and decides no feasibility.** It
  renders what the server worked out and sends back an opaque id. The repository
  interface has **no parameter a time could go in**.

- **M13-047 The app formats the counter's clock, not the phone's.**
  `DateTime.parse` discards the offset the server sent, so the models keep the
  wall-clock fields beside each instant: one for arithmetic, one for reading.
  [BUG-M13-003](13-known-issues.md).

- **M13-048 An unrecognised selection status reads as "nothing chosen".** A
  build that meets a status it cannot interpret must not treat it as settled.

- **M13-049 An issue with an unknown code is kept, with its message and its
  blocking flag.** Both come from the server, so an old build handles a new
  issue correctly rather than ignoring it.

- **M13-050 `ready_for_checkout` is read, never derived from the issue list.**
  The test that pins it is the sharpest case: the server refuses and lists
  nothing the client can point at, and the screen still says no.

### Verification

- **M13-051 1,081 backend tests and 833 Flutter tests pass.** Pint clean,
  `dart analyze --fatal-infos` clean, `dart format` clean.

- **M13-052 More than sixty negative controls were run against this module's
  code**, across six batches. **Exactly eight stayed silent**, and those eight
  are enumerated in [15-test-evidence.md](15-test-evidence.md) — the total is an
  approximate count of mutations attempted, several of which were re-runs of a
  refined mutation against the same target, so it is not quoted as an exact
  figure. Every silent control was chased rather than waved through, and what
  each exposed is recorded in
  [15-test-evidence.md](15-test-evidence.md) — including two cases where the
  test was strengthened and one where an assertion was labelled in the test
  itself as currently unreachable.

- **M13-053 The whole flow was driven against a live server**, with the output
  recorded rather than transcribed:
  [evidence/module-13-verification-run.txt](evidence/module-13-verification-run.txt).

- **M13-054 On-device runs are whatever CI reports**, never what a commit
  message claims. This development machine has no Android SDK and no macOS host
  (KI-001, KI-002).

---

# Module 14 — Checkout, commercial calculation and payment readiness

Full design: [29-checkout-and-payment-readiness.md](29-checkout-and-payment-readiness.md).
Client handover: [30-client-review-package.md](30-client-review-package.md).

## The quote

- **M14-001 A checkout quote is written when, and only when, the order can be
  bought.** `CheckoutPreparationService::prepare` returns `quote: null` when
  pre-checkout validation refuses — a basket nobody can buy is not given a price.

- **M14-002 Amounts are integer minor units throughout.** `checkout_quotes` has
  no floating-point column. Tax is basis points on the subtotal, rounded half up,
  applied once: `intdiv($subtotal * $bps + 5000, 10000)`.

- **M14-003 A quote is not an order and not a payment.** Its statuses are
  `ACTIVE`, `STALE`, `EXPIRED`, `CONSUMED` and nothing else. A test reads the
  column directly rather than through the enum cast, and asserts no order status
  can be found there.

- **M14-004 A quote holds for ten minutes** (`foodonthego.checkout.quote_ttl_minutes`),
  after which it is `EXPIRED` and must be refreshed rather than revived.

- **M14-005 Expiry is decided before staleness.** `CheckoutQuote::effectiveStatus`
  checks consumption, then the clock, then the fingerprint — a quote that has both
  lapsed and gone stale reports `EXPIRED`, which is the one a customer can act on.

- **M14-006 Preparing again supersedes rather than accumulates.** The write runs
  in a transaction that first marks existing `ACTIVE` quotes consumed-by-supersession,
  so two taps arriving together cannot leave a customer holding two live prices.

- **M14-007 The fingerprint covers everything a price depends on** — customer,
  cart, cart version, journey, restaurant identity and its accepting-orders state,
  the route and when it was calculated, the pickup window, Module 13's own planning
  fingerprint, the currency, and the commercial rule version.

- **M14-008 Nothing is reserved.** Preparing a checkout holds no inventory. A
  long-lived reservation has real consequences for other customers and is not
  introduced as a side effect of viewing a screen.

## Commercial calculation

- **M14-009 Money is worked out in one place.** `CommercialCalculationService`
  wraps Module 12's `CartTotalsService` and duplicates none of its arithmetic;
  `payableTotal` is that service's total rather than a re-summation.

- **M14-010 Configured is not the same as zero.** A rule nobody has configured is
  **absent** from the response; a rule configured as zero is a **row** whose
  amount is zero. Tax is configured when the restaurant sets `tax_rate_bps` or the
  platform default is non-zero; the packaging fee when
  `restaurants.packaging_fee_minor` is not null; the platform fee when its config
  value is non-zero.

- **M14-011 `packaging_fee_minor` was made nullable** so that "not configured" is
  expressible at all. It was `NOT NULL DEFAULT 0`, which made every restaurant on
  the platform read as having configured a fee of nothing.

- **M14-012 Discounts are always reported unconfigured.** No discount or promotion
  rule exists in this build, and the response says so rather than sending a zero.

- **M14-013 `has_configured_adjustments` is sent explicitly** rather than left for
  a client to infer from an empty list. "Nothing is configured" and "the charges
  failed to send" look identical otherwise, and only one is a state to render as a
  price.

- **M14-014 No commercial rule has been invented.** GST, service fees, convenience
  fees, commission, packing charges and discounts are all unset, and the report
  says `COMMERCIAL POLICY PRODUCTION READINESS = PENDING CLIENT DECISION`.

## The API

- **M14-015 `POST /trips/{trip}/checkout/prepare`** returns the whole purchase in
  one body — restaurant, journey, pickup, items, money, readiness and the reasons
  behind a refusal.

- **M14-016 `POST /trips/{trip}/checkout/{checkout}/validate`** re-checks
  everything, plus the quote itself.

- **M14-017 Both are POSTs**, because they render a point-in-time judgement and a
  cached yes is somebody at a payment screen for a kitchen that has shut.

- **M14-018 Neither reads money from the request.** A body carrying
  `payable_total_minor`, `items_subtotal_minor`, `tax_minor` or `discount_minor`
  parses to exactly the same thing as a body without them. Asserted by a tamper
  test comparing the two responses.

- **M14-019 `ready_for_payment` is computed by the backend in one place** and is
  not a field a request can carry.

- **M14-020 The journey is context, not data to act on.** No polyline, no
  coordinates: a place label with a fallback chain of name, then city, then
  formatted address.

- **M14-021 The response leaks nothing operational** — no internal notes, no
  commission rate, no owner contact, no bank reference, no tax identifier, no
  fingerprint, no rule version.

## Ownership and tampering

- **M14-022 A quote is scoped by customer AND cart in the query itself**, not
  fetched and then compared. Each clause alone closes the hole; the redundancy is
  deliberate, was measured, and is recorded on the method.

- **M14-023 Another customer's checkout id is a 404**, with the same message as an
  id that never existed — the difference between "not yours" and "not real" is
  what an attacker is trying to learn.

- **M14-024 A checkout id from a different journey is refused.**

- **M14-025 A forged checkout id is refused.**

- **M14-026 Another customer cannot prepare a checkout on this journey.**

- **M14-027 A client cannot talk the server into saying ready.**

## What stops a checkout

- **M14-028 A price rise after quoting stops it.**
- **M14-029 A sold-out line stops it.**
- **M14-030 A paused kitchen stops it.**
- **M14-031 A pickup window that has passed stops it.**
- **M14-032 Changing the cart makes the quote stale.**
- **M14-033 Changing the pickup time makes the quote stale.**
- **M14-034 An expired quote is refused and asks to be refreshed.**

## One response, one clock

- **M14-035 Every instant in a checkout body carries the restaurant's offset.**
  Not a formatting preference: five instants were going out in UTC beside two at
  `+05:30`, which renders as a quote "held until 6:40 am" under a 1:10 pm
  collection.

- **M14-036 The same holds for the pickup body**, which had the same split.
  Module 13's fix had corrected the field somebody looked at rather than the rule.

- **M14-037 Both are pinned by a test that walks the whole response** and fails if
  two offsets appear, rather than by a test naming fields — so a field added later
  is covered by a test written before it existed.

- **M14-038 Both also assert the offset is `+05:30`**, so a body that had become
  self-consistent by sending everything in UTC still fails.

- **M14-039 The client keeps the wall clock beside the instant.**
  `DateTime.parse` discards the offset, so `Checkout.localExpiresAt` is read out
  of the string by `wallClockOf` rather than converted with `.toLocal()`, which
  would be a third clock.

## The Flutter layer

- **M14-040 The screen computes no figure and decides no readiness.**
- **M14-041 `CheckoutRepository` has no parameter that takes an amount**, and the
  requests carry no body at all.
- **M14-042 An unknown quote status is not read as usable**, and is not silently
  read as expired either — which would offer a refresh that fixes nothing.
- **M14-043 Readiness is the server's flag, never derived from an empty issue
  list.**
- **M14-044 A component the server did not send is not drawn**, and no zero row is
  invented for it.
- **M14-045 An unknown charge code is shown using the code itself** rather than
  dropped: a customer paying a charge must see it even on an old build.
- **M14-046 The total shown is the server's**, not the sum of the rows on screen.
- **M14-047 A quote the server has forgotten is replaced, not explained** — an id
  the customer never saw cannot be described to them.
- **M14-048 A stale quote is refreshed rather than revalidated.**
- **M14-049 A failed validate leaves the price on screen** and only stops the
  customer proceeding.
- **M14-050 Proceed to payment is enabled only when the server says ready**, and
  says plainly that payment arrives in the next release rather than showing a row
  of payment logos that cannot be tapped.
- **M14-051 Module 13's Continue to checkout is functional**, shown only once the
  server's pre-checkout verdict says yes.
- **M14-052 The edit controls are stacked** so both labels are readable at 393dp
  and at 200% text.

## Nothing is bought

- **M14-053 Preparing a checkout creates no order and no payment.** Asserted by
  checking that the `orders`, `order_items`, `payments` and `pickup_codes` tables
  do not exist.
- **M14-054 No Razorpay object is created and no key is read.**
- **M14-055 Proceed to payment hands off to nothing.**

## Verification

- **M14-056 1,119 backend tests and 904 Flutter tests pass.** Pint clean,
  `dart analyze --fatal-infos` clean, `dart format` clean.

- **M14-057 Negative controls were run against every layer of this module** —
  parsing, the controller, the screen, the summary card, the pickup entry point
  and the two one-clock tests. Each is named in
  [15-test-evidence.md](15-test-evidence.md) with the mutation applied and the
  tests it made fail. **Every one fired.**

- **M14-058 The device runs are CI's, not a commit message's.** Five Module 14
  integration tests passed on an Android emulator and on an iOS simulator, inside
  a run of 27 tests across Modules 11–14, against a real Laravel server writing to
  a real MySQL database.

- **M14-059 Twelve screenshots were produced by rendering the real app and the
  real web shells** against a real server:
  [evidence/module-14/](evidence/module-14/).

- **M14-060 An Android review APK and app bundle are built by CI** with a
  manifest recording version, commit, toolchain, API address and SHA-256.

- **M14-064 The review APK is installed and launched, not merely built.** The
  emulator job downloads the artefact itself — the file handed over, not a
  rebuild sharing a commit — installs it on a Pixel 6 running Android 14, starts
  it, and checks the process is alive twenty seconds later, that
  `versionName=1.0.0` matches the manifest, and that nothing belonging to this
  package is in the crash buffer.

- **M14-061 `EXTERNAL REVIEW URL = PENDING`** — nothing is deployed, and a
  localhost address is not a review URL.

- **M14-062 `iOS REVIEW BUILD = PENDING — APPLE SIGNING/TESTFLIGHT ENVIRONMENT
  UNAVAILABLE`.** No IPA exists and none has been fabricated.

- **M14-063 Credentials were provided for the one role that has a login**, and
  withheld — with the reason — for the six that do not. Measured:
  `route:list` matches zero routes for those six, and the web shells contain no
  login screen, password field or token handling.

---

# Module 14T — Multi-tenancy, tenant assignment and cross-tenant isolation

Inserted between Modules 14 and 15 at the client's direction. Design:
[33-multi-tenancy-and-tenant-isolation.md](33-multi-tenancy-and-tenant-isolation.md).

## The model

- **M14T-001 A restaurant is a tenant**, and the only way anybody reaches one is
  an assignment row or a platform grant.

- **M14T-002 The tenant role lives on the assignment, not on the user.**
  `users.role` decides which surface somebody signs in to; `restaurant_user.tenant_role`
  decides what they may do at that restaurant. A single column on `users` cannot
  describe an owner at one restaurant who cooks at another.

- **M14T-003 Both are checked.** A customer account with an assignment row
  reaches nothing, so an insert into `restaurant_user` is not by itself a way in.

- **M14T-004 There is no `restaurants.owner_id`.** An owner is an assignment whose
  role is `owner` — one place to look, one place to revoke.

- **M14T-005 One assignment per person per restaurant**, enforced by a database
  unique constraint rather than a validation rule.

- **M14T-006 Access is revoked by status, never by deletion**, and every read
  filters on it through an `active()` scope.

- **M14T-007 `TenantRole` is an ordering**, written once: owner ⊇ manager ⊇ staff.

## Enforcement

- **M14T-008 `TenantAccessService` is the only implementation of reachability.**
  The policy, the scopes and every controller ask it.

- **M14T-009 Isolation is enforced in the query.** `reachableBy()` is a `whereIn`
  against a subquery, never a filter applied after the fetch.

- **M14T-010 A foreign tenant and a non-existent one answer identically** — same
  404, same code, same message, asserted by comparing the two responses.

- **M14T-011 The role middleware is a surface check and never a tenancy check.**
  On its own it would let any manager reach every restaurant.

- **M14T-012 `RestaurantPolicy` has no `before()` hook.** That hook is how "super
  admin sees everything" becomes true by omission.

- **M14T-013 Depth is per action**: view = staff, update and manageMenu =
  manager, manageStaff and viewFinancials = owner.

- **M14T-014 A suspended or deactivated account reaches nothing**, whatever its
  assignments say.

## The indirect path

- **M14T-015 A resource reached by its own id is still tenant-scoped.**
  `BelongsToTenant::scopeInReachableTenant()` reaches back through the owning
  restaurant and filters in the query.

- **M14T-016 Both shapes are routed and both are tested** — the nested one and
  the bare-id one — because a pass on the easy shape says nothing about the
  dangerous one.

## Platform accounts

- **M14T-017 A super administrator with no grant reaches nothing.**
- **M14T-018 Breadth is a row**: `scope = 'all'` or one named restaurant.
- **M14T-019 A revoked grant reaches nothing.**
- **M14T-020 Depth is separate from breadth** — a support agent looking into one
  complaint gets `staff`, not `owner`.
- **M14T-021 Where somebody holds both an assignment and a grant, the stronger
  applies**, worked out by the enum's ordering rather than a second comparison.

## Verification

- **M14T-022 1,141 backend tests pass**, Pint clean. 22 are this module's, all
  over HTTP with real tokens.

- **M14T-023 Seven negative controls were applied to shipping code and reverted.
  Every one fired**, each on the tests that should catch it — enumerated in
  [15-test-evidence.md](15-test-evidence.md).

- **M14T-024 A control found a real bug before it shipped.** `accountUsable()`
  read `is_active === true`; the column defaults to true, so an
  un-round-tripped model held NULL and was read as disabled. Denying by accident
  made every "reaches nothing" assertion pass whether the boundary worked or not.

- **M14T-025 No login for the six operator roles**, unchanged. The boundary exists
  first so that login arrives behind something already tested.

## Module 15 — orders, payment, webhooks and reconciliation

### No credentials, and what follows from that

- **M15-001 No Razorpay credentials exist and none were invented.** The
  container binds `UnconfiguredPaymentGateway`; the app binds
  `UnconfiguredPaymentHandoff`. Both refuse, loudly, rather than degrading.
- **M15-002 A missing integration is a broken deployment, not a quiet one.**
  `ProductionConfigGuard` refuses to boot in staging or production when the key
  id, the key secret or the webhook secret is absent.
  `ProductionConfigGuardTest` covers both halves separately.
- **M15-003 `RazorpayGateway` has never spoken to Razorpay**, and no claim is
  made that it has.

### The client never decides money

- **M15-004 No endpoint in this module accepts an amount.** Not validated —
  absent. `test_amounts_posted_when_placing_an_order_are_ignored_entirely` and
  `test_an_amount_posted_when_verifying_is_ignored_entirely` post bodies full of
  figures and assert the result is unchanged.
- **M15-005 The order's amounts are copied from the quote, never recomputed.**
- **M15-006 The app has no parameter for a price** on `OrderRepository`, and no
  field a key secret could arrive in on `PaymentIntent`.

### The three checks

- **M15-007 Signature.** HMAC-SHA256 over `order_id|payment_id`, compared with
  `hash_equals`. Empty signature and empty secret both fail closed.
- **M15-008 Binding.** The provider's own order id for the payment must match
  the provider order created for this order. A correctly signed payment
  belonging to another order settles nothing.
- **M15-009 Amount and currency**, checked against the order rather than the
  attempt. A genuine, signed, correctly bound ₹1 payment does not settle.
- **M15-010 All three run on every path**, because all three paths call
  `confirmAgainstProvider()`.
- **M15-011 Signature verification is not on the gateway interface**, so the
  test double cannot be the thing deciding whether signatures are valid.

### Webhooks

- **M15-012 Verified over the raw body**, before any parsing. A re-encoded body
  does not verify, and there is a unit test proving the two are different bytes.
- **M15-013 The webhook secret is separate from the API secret**, with a test
  for the reuse mistake.
- **M15-014 Idempotency is a unique index**, not a check-then-write.
- **M15-015 Only verified deliveries are stored.** Recording rejected ones under
  the event id they claimed would let anybody suppress a genuine delivery.
  Tested by name.
- **M15-016 A verified delivery always answers 2xx**, including for subjects
  this deployment does not know, so a provider does not retry into a storm.

### Reconciliation

- **M15-017 It starts from the provider order**, because in the case that
  matters this server has no payment id to ask about.
- **M15-018 A grace period**, so it never races a webhook in flight.
- **M15-019 A captured payment for the wrong amount is counted, not settled**,
  and the command exits non-zero so a scheduler notices.

### Orders

- **M15-020 One quote becomes at most one order**, enforced by a unique index.
  A double tap answers 200 with the order that exists.
- **M15-021 Order lines are snapshots** and do not cascade from the menu.
  Asserted by renaming and repricing the dish after the order exists.
- **M15-022 Status is payment state only.** No fulfilment vocabulary was
  invented, on the server or in the app.
- **M15-023 An order is settled once.** The row is locked and re-read inside the
  transaction.
- **M15-024 One response, one clock** — every instant in an order body on the
  order's stored zone, asserted by walking the whole body.

### Privacy

- **M15-025 No card data is stored**, and there is no column for it.
- **M15-026 Webhook payloads are not stored**, only a digest.
- **M15-027 A provider's decline text is never relayed to the customer.**

### Isolation

- **M15-028 Orders are tenant-scoped** through `BelongsToTenant`, including the
  indirect path — an order reached by its own id, carrying a customer's name and
  what they paid.
- **M15-029 A foreign order and a non-existent one answer identically.**
- **M15-030 Another customer's order answers 404**, for read, intent and verify.

### Verification

- **M15-031 1,201 backend tests and 938 Flutter tests pass.** 60 and 34 new
  respectively.
- **M15-032 Ten negative controls were applied to shipping code and reverted.**
  Nine fired immediately; the tenth stayed silent and exposed a test that could
  not distinguish the guard holding from the guard being absent. See
  15-test-evidence.md.

## Module 16 — order creation, confirmation, order number and pickup code

### The deviation, and the model it produced

- **M16-001 The specification's rule is enforced; its table layout is not.**
  Modules 12–15 write an `orders` row at checkout. Module 16 requires an order
  to exist only downstream of a captured payment. One `orders` table was kept
  and the *meaning* of a row was changed, rather than a fourth module's worth of
  tested payment code being rewritten to reach the same guarantee.
- **M16-002 The deviation is visible in the migration list, not only in a
  document.** `2026_09_17_010000_place_orders_only_on_captured_payment`.
- **M16-003 An `AWAITING_PAYMENT` row is not an order.** No `order_number`, no
  `placed_at`, no pickup credentials. `OrderStatus::AwaitingPayment` says so in
  its own docblock.
- **M16-004 "Not an order yet" is machine-checkable.** `order_number IS NULL`
  and `placed_at IS NULL` are what `orders:check-integrity` and the customer's
  Orders query both key off, so the rule is queryable rather than conventional.
- **M16-005 The cleaner alternative was rejected deliberately, not overlooked.**
  A separate `payment_intents` table was the other option and is recorded as
  such in 35-order-creation-and-pickup-credentials.md.
- **M16-006 A payment target never appears in the customer's Orders tab.**
  `whereNotNull('placed_at')`;
  `test_an_unpaid_payment_target_never_appears_in_the_orders_tab`.

### One captured payment produces at most one order

- **M16-007 The invariant is "at most one", not "usually one".**
  `test_a_captured_payment_produces_exactly_one_placed_order`.
- **M16-008 The guarantee is a unique index on
  `orders.placed_from_payment_id`.** Not a check, not a lock, not a cache.
- **M16-009 The row lock is the fast path and is documented as such.**
  `SELECT ... FOR UPDATE` serialises two attempts; it does not decide the
  second.
- **M16-010 The status is re-read inside the lock**, so the second attempt sees
  `PLACED` and returns the existing order rather than racing.
- **M16-011 A duplicate attempt is a successful call.** The caller is a webhook
  Razorpay will retry or an app resuming after a crash — neither is
  misbehaving. `place()` catches the `QueryException`, re-reads, and returns.
- **M16-012 A duplicate client callback places nothing new.**
  `test_a_duplicate_callback_does_not_place_a_second_order`.
- **M16-013 A duplicate webhook places nothing new.**
  `test_a_duplicate_webhook_does_not_place_a_second_order`.
- **M16-014 A callback and a webhook for one capture place one order.**
  `test_a_callback_and_a_webhook_for_one_capture_place_one_order`.
- **M16-015 Two concurrent workers place one order.**
  `test_two_workers_placing_the_same_payment_produce_one_order`.
- **M16-016 The recovery sweep calls the same method as the live paths.** Not a
  second implementation, so it cannot drift laxer than the path that is
  watched.
- **M16-017 A prevented duplicate is logged as
  `orders.duplicate_creation_prevented`** with identifiers only.
- **M16-018 Idempotency is proven at the service layer too, not only over
  HTTP.** `test_the_service_placed_twice_writes_one_order_and_one_event` — one
  order *and* one outbox event.

### What must be true before an order exists

- **M16-019 Order creation happens only from a payment this server recorded as
  `CAPTURED` after verifying it with the provider.**
- **M16-020 `payment_success = true` from a client is not an input.** It is not
  validated, not rejected, not read. No code path in this module consults a
  client's claim about a payment.
- **M16-021 An `AUTHORIZED` payment places nothing.**
  `test_an_authorized_payment_places_nothing`.
- **M16-022 A `CREATED` payment places nothing.**
  `test_a_created_payment_places_nothing`.
- **M16-023 A `FAILED` payment places nothing.**
  `test_a_failed_payment_places_nothing`.
- **M16-024 A capture for the wrong amount places nothing.**
  `test_a_capture_for_the_wrong_amount_places_nothing`.
- **M16-025 A capture in the wrong currency places nothing.**
  `test_a_capture_in_the_wrong_currency_places_nothing`.
- **M16-026 Those refusals are asserted against the service, not only the
  route.** `test_the_service_refuses_a_payment_that_is_not_captured`,
  `..._a_capture_for_the_wrong_amount`, `..._a_capture_in_the_wrong_currency`.
  This exists because the HTTP-level versions passed with the guards removed —
  see 09-testing-strategy.md.
- **M16-027 The order total is exactly what was captured.**
  `test_the_order_total_is_exactly_what_was_captured`.
- **M16-028 Placing an order spends the basket, the quote and the event.** The
  cart becomes `CONVERTED` and the quote `CONSUMED` inside the same
  transaction. `test_placing_an_order_spends_the_basket_the_quote_and_the_event`.

### The order number

- **M16-029 Shape is `FOTG-YYMMDD-XXXXXXXXXX`.** The date is for humans reading
  a support ticket; it narrows nothing an attacker holding that day's order did
  not already know.
- **M16-030 Drawn from `random_int`**, which is CSPRNG-backed.
- **M16-031 Not `Math.random`, not a timestamp, not the database id, not a
  sequence.** A sequential public number tells its holder how many orders the
  platform has taken and lets them guess their neighbours'.
- **M16-032 Base-32 alphabet with I, L, O and U removed.** I/1, O/0 and L/1 are
  the pairs people mishear; U is dropped so no draw can spell something a
  customer has to say out loud.
- **M16-033 Uniqueness is the unique index**, not the pre-insert existence
  check, which is documented as an optimisation.
- **M16-034 A collision is retried rather than returned.**
  `test_an_order_number_collision_is_retried_rather_than_returned`, using the
  injectable RNG, because the natural collision rate over 2^50 suffixes per day
  is not something a test can wait for.
- **M16-035 AN ORDER NUMBER DOES NOT AUTHORIZE PICKUP.** It is safe to print,
  quote and read aloud precisely because knowing one is never sufficient to
  collect food.
- **M16-036 No route accepts an order number as an identifier.**
  `test_no_route_accepts_an_order_number_as_an_identifier`. Routes are keyed by
  uuid.
- **M16-037 The column was widened to `varchar(24)` rather than the suffix being
  shortened.** `FOTG-YYMMDD-` plus ten characters is 22; spending entropy to fit
  a column would have been the wrong trade.

### Pickup credentials

- **M16-038 THE PLAINTEXT PICKUP CODE IS NEVER STORED.** There is no column it
  could be read out of.
- **M16-039 The plaintext QR token is never stored either.**
- **M16-040 Both are derived on demand.**
  `code = base32(HMAC-SHA256(pepper, "pickup-code:v{n}:{order_uuid}:{restaurant_id}"))[0..8]`.
- **M16-041 The token is `base64url` of a 256-bit HMAC** over the same context
  with the `pickup-token` purpose.
- **M16-042 What is stored is a keyed digest**, `HMAC-SHA256(pepper,
  "{purpose}:{value}")` — not a bare SHA-256. 2^40 is enumerable offline, so a
  plain hash of an 8-character code in a stolen dump is a lookup table away
  from plaintext.
- **M16-043 Proven empirically, not by inspection.**
  `test_no_plaintext_credential_is_ever_written_to_the_database` derives the
  pair and then searches the stored row for either value.
- **M16-044 Comparison is `hash_equals`**, for the code and for the token.
- **M16-045 The order uuid is inside the HMAC input**, so a credential is bound
  to its order by arithmetic rather than by a check that a new call site could
  forget.
- **M16-046 The restaurant id is inside the HMAC input**, giving the same
  property across tenants — and that is proven by
  `test_the_restaurant_id_alone_changes_the_credential`, which holds the uuid
  and the version constant and moves only the restaurant. A negative control
  showed the cross-restaurant test below could not prove this on its own: two
  orders at two restaurants also have two different uuids, so removing
  `restaurant_id` from the context left it green.
- **M16-047 Cross-restaurant replay fails in both directions.**
  `test_a_credential_cannot_be_replayed_at_another_restaurant` builds two placed
  orders at two restaurants and asserts each rejects the other's code and token.
- **M16-048 That test cannot pass against an implementation that matches
  nothing.** Each order first asserts its own credential matches — without it,
  a `return false` would satisfy every negative assertion.
- **M16-049 Credentials are unpredictable and bound to the order.**
  `test_the_pickup_credentials_are_unpredictable_and_bound_to_the_order`.
- **M16-050 `pickup_credential_version` is inside the HMAC input**, so a
  credential can be invalidated without touching the order.
- **M16-051 Rotation is not complete until the digests are re-minted.**
  `test_rotating_the_credential_version_invalidates_the_old_code` asserts the
  derived values change *and* that the stored digest still matches the old code
  — recording the cost so a future rotation path cannot quietly leave it
  working.
- **M16-052 A missing credential version is a thrown exception, not a cast.**
  `PickupCredentialVersionMissing`.
  `test_deriving_from_an_unreloaded_order_is_refused_rather_than_wrong`. This
  shipped as a real bug: `(int) null` is `0`, a usable HMAC input, so one order
  derived two different credentials depending on whether anything had reloaded
  the model.
- **M16-053 The pepper is the single secret, and that trade is stated in the
  service rather than hidden.**
- **M16-054 `ProductionConfigGuard` refuses to boot staging or production
  without `PICKUP_CREDENTIAL_PEPPER`.**
- **M16-055 `derive()` throws `PickupCredentialUnavailable` rather than
  deriving under an empty key.** A scheme that degrades silently to
  `HMAC(pepper: "")` is worse than one that stops.
- **M16-056 Eight characters is 2^40 and is one factor, not the boundary.** The
  256-bit token is the other; the QR path carries the token.
- **M16-057 OPEN: there is no attempt limit on guessing a code, because there is
  no redemption endpoint yet.** Named as an inherited obligation for whichever
  module builds pickup verification rather than left implied. Recorded in
  13-known-issues.md.

### Where credentials may and may not travel

- **M16-058 The credential has its own endpoint**,
  `GET /customer/orders/{order}/pickup-credential`, fetched one order at a time.
- **M16-059 That response is not cacheable, and `SecureHeaders` is what
  guarantees it.** The middleware sets `Cache-Control: no-store, private` on
  every API response and runs after the controller, so the controller's own
  header — still set, as belt to the middleware's braces — is not what ships. A
  negative control established this: changing the controller's value left the
  route's test green; changing the middleware's failed both
  `SecurityHeadersTest` and
  `test_the_credential_endpoint_returns_a_code_and_forbids_caching`. `no-store`
  rather than `no-cache` in both places, because `no-cache` permits storage.
- **M16-060 The order response never carries the credential.**
  `test_the_order_response_never_carries_the_credential`. Putting it on the
  order would ship it through every list refresh and status poll.
- **M16-061 The QR payload is the token and nothing else.**
  `test_the_qr_payload_is_the_token_and_nothing_else`, asserted as equality
  against `prefix + token` — the earlier substring form would have passed
  vacuously against an empty field.
- **M16-062 The order response leaks no provider material.**
  `test_the_order_response_leaks_no_provider_material`.
- **M16-063 Never logged: the plaintext code, the plaintext token, special
  instructions, payment signatures, provider secrets.**
- **M16-064 A credential redacts itself when serialised.**
  `PickupCredential::__toString()` returns `PickupCredential(v2)`;
  `test_a_credential_redacts_itself_when_serialised`. On the Flutter side the
  model has no `toJson` and is never written to disk.
- **M16-065 Another customer cannot read the order.**
  `test_another_customer_cannot_read_the_order` — 404, not 403, because a 403
  confirms the order exists.
- **M16-066 Another customer cannot read the credential.**
  `test_another_customer_cannot_read_the_pickup_credential`.

### After payment, no answer may read as a payment failure

- **M16-067 Three states, and none of them is an error:** `PLACED` (200),
  `ORDER_CREATION_PENDING` (202), `ORDER_RECOVERY_REQUIRED` (202).
- **M16-068 The two 202s are not members of `ApiErrorCode` and cannot become
  members.** `ErrorContractTest` asserts no error code maps to a 2xx status.
  They live in `OrderCreationState`.
- **M16-069 A captured payment with no order yet is a delay, not a failure**,
  and is presented as one. `test_the_status_endpoint_returns_a_placed_order`
  and the pending path alongside it.
- **M16-070 THERE IS NO "PAY AGAIN".** No *Back to Payment*, no retry-payment
  affordance in any phase of the confirmation screen.
- **M16-071 A customer returning after a crash gets their order, not a payment
  screen.**
  `test_a_customer_returning_after_a_crash_gets_their_order_not_a_payment_screen`.
- **M16-072 A network failure never invites a second payment.** An app that
  cannot reach the server knows nothing about the money and must not guess.
  Flutter: *a network failure never invites a second payment*.
- **M16-073 An unrecognised `state` reads as `creating`**, not as an error —
  the client's ignorance must produce a wait, not a payment prompt.
- **M16-074 A missing `is_paid_for` reads as paid for.** Same direction.
- **M16-075 `recovering` is rendered identically to `creating`.** The customer
  gains nothing from being told the first write failed; the distinction exists
  for support and analytics. Flutter: *a recovering order is shown identically
  to a creating one*.
- **M16-076 An order with no payment taken says so honestly**, and that is the
  one phase where offering payment is correct.
  `test_an_unpaid_order_reports_awaiting_payment`.
- **M16-077 Polling is bounded — 10 attempts, 3 seconds apart — and stops as
  soon as the order is placed.** Flutter: *polling stops as soon as the order is
  placed*. The endpoint's idempotency is what makes polling safe.
- **M16-078 A client body with no order number is still parsable.** Flutter: *a
  body with no order number is still a parsable payment target*. Before this,
  `PlacedOrder.orderNumber` was non-nullable and would have thrown a
  `FormatException` on the payment screen for every customer; no widget test
  could see it, because the fake always supplied a number.

### Snapshots — an order records what happened

- **M16-079 Renaming, repricing or deleting a dish does not rewrite an order.**
  `test_renaming_the_dish_does_not_rewrite_the_order`,
  `test_repricing_the_dish_does_not_change_what_was_paid`,
  `test_deleting_the_dish_leaves_the_order_complete`.
- **M16-080 Removing a variant or a modifier option leaves it on the order.**
  `test_removing_the_variant_leaves_the_size_on_the_order`,
  `test_removing_a_modifier_option_leaves_it_on_the_order`.
- **M16-081 Renaming the restaurant leaves the order's snapshot alone.**
  `test_renaming_the_restaurant_leaves_the_order_snapshot_alone`.
- **M16-082 The customer phone snapshot comes from `users.phone_e164`.** The
  obvious column, `users.phone`, is legacy and unpopulated; reading it wrote
  silent `NULL`s. Caught only because the test asserts the fixture is non-empty
  *before* asserting the snapshot matches it — a pattern now used across the
  module.

### Recovery, integrity and the outbox

- **M16-083 A captured payment with no order is a critical state with an owner.**
  `orders:recover-captured` runs every five minutes with a 120-second grace so
  an in-flight creation is not raced; `orders:check-integrity` runs hourly,
  writes nothing, and reports both directions of breakage; `outbox:publish`
  drains events written inside the creation transaction, whose payloads carry
  identifiers only. `test_the_sweep_places_an_order_for_a_stranded_capture`,
  `test_the_sweep_is_idempotent`,
  `test_a_capture_inside_the_grace_period_is_left_alone`,
  `test_the_default_grace_period_leaves_a_fresh_capture_alone` — the second
  exists because a control showed every grace-period test passed `--grace`
  explicitly, leaving the default that actually runs in production untested —
  `test_a_dry_run_reports_without_placing`,
  `test_the_integrity_check_is_quiet_when_every_order_has_its_money`,
  `test_the_integrity_check_reports_an_order_with_no_captured_payment`,
  `test_publishing_drains_the_outbox_exactly_once`,
  `test_the_event_payload_is_identifiers_only`.

## Module 17 — customer order tracking, status timeline and order state presentation

### The Orders tab and the way in

- **M17-001 The Orders tab shows real data**, from `GET /customer/orders`.
  `test_the_orders_tab_separates_active_from_finished`.
- **M17-002 Active orders are separated from finished ones**, and "active" is
  derived from `OrderStateMachine::activeStatuses()` rather than a list kept in
  the controller — so the API's notion of active cannot drift from the
  lifecycle's.
- **M17-003 Each card opens tracking** through a *Track order* button rather
  than a tappable card, so a scroll cannot open it by accident.
- **M17-004 The tracking API is the existing order endpoint, enriched.** Two
  endpoints returning almost the same order would drift; the day they did, a
  customer would read one status in a list and another on the screen opened
  from it.
- **M17-005 The current status comes from the server** and is the largest
  element on the screen.

### The state machine

- **M17-006 One writer.** `OrderStateMachine` is the only thing that assigns
  `order.status`; `OrderTransitionService` is the only general caller.
- **M17-007 The transition matrix is explicit and complete**, including empty
  lists for terminal states. Documented in
  [36-customer-order-tracking.md](36-customer-order-tracking.md).
- **M17-008 PLACED** — reached by Module 16; may go to ACCEPTED, REJECTED or
  CANCELLED.
- **M17-009 ACCEPTED** — may go to COOKING or CANCELLED.
  `test_an_order_walks_the_whole_lifecycle`.
- **M17-010 REJECTED** — terminal.
  `test_a_rejected_order_cannot_be_accepted_after_all`.
- **M17-011 COOKING** — may go to READY only.
  `test_an_order_already_cooking_cannot_be_cancelled` asserts the absence of the
  cancellation edge deliberately, so adding it later is a decision rather than a
  line somebody adds while fixing something else.
- **M17-012 READY** — may go to PICKED_UP only.
- **M17-013 PICKED_UP** — terminal.
  `test_a_picked_up_order_cannot_be_reopened`.
- **M17-014 CANCELLED** — terminal, reachable from PLACED and ACCEPTED only.
  `test_a_cancelled_order_cannot_start_cooking`.
- **M17-015 Payment state is separate from order state.** `REFUNDED` stays an
  unreachable order status; a refunded rejection is two facts on two records.
  **No refund workflow exists**, so nothing claims one.
- **M17-016 Terminal states have no override.** Empty lists, no force flag, no
  `allowUnsafe` parameter anywhere in the state machine.
- **M17-017 Illegal transitions are refused and tested by name** —
  `PLACED → READY`, `PLACED → PICKED_UP`, `ACCEPTED → READY`,
  `COOKING → ACCEPTED`, `READY → COOKING`. Named rather than looped: a loop
  proves the table is self-consistent, which it would be even if it were wrong.

### History and timestamps

- **M17-018 `order_status_history` records every transition**, append-only,
  with from/to, source, actor, internal reason, customer-safe note, correlation
  id and `occurred_at`.
- **M17-019 Placement writes the first entry.**
  `test_a_captured_payment_starts_the_orders_history`, asserted against a real
  captured payment — the earlier version ran against a fixture that wrote the
  row itself and so proved the fixture.
- **M17-020 Milestone timestamps** for accepted, rejected, cooking, ready,
  picked-up and cancelled, written once each by the state machine.
  `test_a_milestone_timestamp_is_not_rewritten_by_a_duplicate`.
- **M17-021 The history is immutable.** No update path in the model, none in any
  service; a correction would be an appended row through a workflow that does
  not exist.
- **M17-022 `order_version` increments on every transition.**
  `test_the_version_increments_once_per_transition`.
- **M17-023 Transitions are concurrency-safe** — row lock, status re-read under
  the lock, unique index behind both.
  `test_two_identical_transitions_produce_one_history_entry`,
  `test_conflicting_transitions_leave_one_coherent_history`.
- **M17-024 A duplicate transition writes nothing** — no history row, no event,
  no version bump.
  `test_asking_for_the_state_it_is_already_in_writes_nothing`.
- **M17-025 Domain events** `OrderAccepted`, `OrderRejected`,
  `OrderCookingStarted`, `OrderReady`, `OrderPickedUp`, `OrderCancelled`, on
  Module 16's outbox rather than a second delivery architecture.
- **M17-026 Events are idempotent**, keyed `{order_uuid}:{status}` against the
  outbox's own unique index.
  `test_each_transition_queues_exactly_one_domain_event`.

### The timeline

- **M17-027 The timeline renders from the server's steps**, each arriving with
  its state already decided.
- **M17-028 The status hero is the most prominent element**, above the order
  number.
- **M17-029 Completed steps carry their timestamp.**
- **M17-030 The current step is marked by weight and icon**, not by colour
  alone.
- **M17-031 Upcoming steps carry no timestamp.**
  `test_a_placed_order_shows_one_current_step_and_four_upcoming` asserts every
  unreached step is null — a fabricated time is the one error a customer cannot
  detect.
- **M17-032 A rejected order shows no steps it will never reach.**
  `test_a_rejected_order_shows_no_cooking_or_ready_step`, plus the widget test.
- **M17-033 A cancelled order keeps the steps it reached** and shows no future.
  `test_a_cancelled_order_keeps_the_steps_it_reached`.
- **M17-034 A picked-up order shows every step complete.**
  `test_a_picked_up_order_shows_every_step_complete`.
- **M17-035 Status copy comes from the server**, with the client's labels as a
  documented fallback for an older backend.
- **M17-036 Customer-safe reasons are authored, never derived** from an internal
  code at render time.

### The rest of the screen

- **M17-037 Restaurant summary**, from the order's snapshot.
- **M17-038 Requested pickup**, labelled "Not a live estimate".
- **M17-039 Order items**, from Module 16's immutable snapshots.
- **M17-040 Commercial summary**, from the order's frozen totals.
- **M17-041 Payment summary read from the payment record**, independently of
  the order's state.
- **M17-042 The pickup code stays on its own endpoint.** Tracking carries
  `pickup_credential.available` — a boolean is not a credential.
  `test_the_tracking_response_never_carries_the_pickup_code`.
- **M17-043 The QR payload likewise.** Available from placement, with the
  tracking screen saying when to use it.
- **M17-044 QR verification is not implemented and is not claimed.** Module 21.

### Refresh

- **M17-045 Manual refresh** by pull-to-refresh and an app-bar action.
- **M17-046 Polling is implemented and named temporary.** 20s from
  `FOTG_ORDER_TRACKING_REFRESH_SECONDS`, floored at 5s.
- **M17-047 Polling stops when the app is backgrounded.**
- **M17-048 Polling stops for a terminal order**, on the server's `is_active`
  rather than a client-side list of terminal states.
- **M17-049 One refresh on resume.**
- **M17-050 Offline shows the cached order, marked stale**, rather than an
  error page. Widget: *a lost connection keeps the order and says it is stale*.
- **M17-051 Freshness is a time, never a `LIVE` badge.** Widget: *the screen
  never claims to be live*.
- **M17-052 A restored connection reconciles** on the next refresh.
- **M17-053 An older response cannot move the screen backwards.** Widget: *an
  older response cannot move the status backwards*, with its control *a newer
  response does update the status* — without which a client that ignored every
  response would pass.
- **M17-054 Version comparison is arithmetic, not lifecycle knowledge.** The
  client compares two integers and never infers that READY follows COOKING.
- **M17-055 Multiple active orders are supported**, sorted soonest-pickup first.
  `test_two_live_orders_are_listed_soonest_pickup_first`.

### Security

- **M17-056 Another customer's order answers 404.**
  `test_another_customer_cannot_track_this_order`.
- **M17-057 An order number is not an identifier.**
  `test_an_order_number_is_not_an_identifier_for_tracking`.
- **M17-058 The pickup credential is ownership-checked**, unchanged from
  Module 16 and re-asserted here.
- **M17-059 Orders stay bound to their restaurant**, through `BelongsToTenant`.
- **M17-060 A restaurant actor cannot move another tenant's order.**
  `test_a_restaurant_cannot_move_another_restaurants_order`, with
  `test_a_restaurant_may_move_its_own_order` as the positive control.
- **M17-061 No customer route writes an order status.**
  `test_no_customer_route_can_change_an_order_status` walks the router rather
  than trying guessed URLs.
- **M17-062 Nothing internal reaches the customer** — no actor, no reason code,
  no correlation id. `test_the_tracking_response_carries_nothing_internal`,
  asserted against the serialised body with a guard proving the fixture carried
  them.
- **M17-063 Logs carry identifiers and categories only**, never the
  customer-safe note, the pickup code or the QR token.
- **M17-064 Performance** — the list eager-loads restaurants and is capped at
  50; tracking loads items, modifiers, restaurant and history in one go.
- **M17-065 Cost control** — twenty refreshes make zero Google and zero
  Razorpay calls. `test_twenty_refreshes_touch_no_external_provider`.

### Verification

- **M17-066 Android runtime** — see the completion report.
- **M17-067 iOS runtime** — see the completion report.
- **M17-068 Accessibility** — three signals per timeline step, weight rather
  than colour for the current one, one spoken sentence per step, and a layout
  test at 320px with 2× text.
- **M17-069 Backend unit and service tests** — state machine, transition
  service, timeline service.
- **M17-070 Backend API tests** — list, tracking, timeline branches, privacy,
  IDOR, route-surface.
- **M17-071 Flutter unit tests** — version handling, timeline parsing, status
  mapping.
- **M17-072 Flutter widget tests** — 11, covering every rendered phase.
- **M17-073 Integration test** — see the completion report.
- **M17-074 Database verification** — see the completion report.
- **M17-075 Live view verification** — see the completion report.
- **M17-076 Review APK rebuild** — see the completion report.
- **M17-077 Client documentation updated.**
- **M17-078 Modules 01–16 regression** — full suite green.
- **M17-079 Module 18 handoff** — status, timing, payment and credential state
  are separate objects in the tracking response, so an ETA can be added beside
  the pickup window without touching the lifecycle.
- **M17-080 Module 19 handoff** — every transition already queues a domain
  event on the outbox, and the client's version handling already tolerates
  updates arriving out of order.

### Discovered during implementation

- **M17-081 One response, one clock.** The timeline, the credential expiry and
  `server_time` first shipped in UTC while every other instant was on the
  restaurant's clock; Module 13's invariant caught it. The zone helper is now
  shared rather than duplicated.
- **M17-082 The status hero and the timeline must use the same wording.** They
  did not, and one screen could show "Being prepared" above "Your food is being
  prepared".
- **M17-083 A negative-control harness must revert from a copy**, never by
  reversing a string edit, and must not score a parse error as a fired control.
  See 09-testing-strategy.md.
- **M17-084 The repository's own wire format needs a test.** `tracking()`
  unwrapped the response envelope twice, so every call against a real server
  threw and the screen honestly reported that it could not load the order. All
  962 widget tests then in the suite drove a fake repository, so the code that
  turns an HTTP body into a model had never executed. Covered by
  `mobile/test/order_repository_wire_test.dart`, whose fixture is copied from
  the live run rather than written from the model's point of view — a fixture
  written from the model's side would have shared the fake's blind spot.
  Found by: the iOS device job. Control: restoring the double unwrap fails 3 of 4.
- **M17-085 A device test must not be measuring the test server.** The device
  jobs ran the API on a single-worker `php artisan serve`, which answers one
  request at a time while the app asks about nine when a screen opens cold;
  under load one of them passed the client's ten-second timeout. Fixed in
  `scripts/ci-backend-up.sh` with `PHP_CLI_SERVER_WORKERS=8 --no-reload`, and
  the script now warns loudly if Laravel ever declines the worker count.
  Evidence: `docs/evidence/module-17/serve-concurrency-run.txt`. KI-032.
- **M17-086 "Always open" must mean always.** The `alwaysOpen` seeder flag and
  the `openAllWeek` test fixture both wrote `00:00:00 – 23:59:59`, and
  `RestaurantAvailabilityService::covers()` asks `$time < closes_at` — so the
  restaurant was closed for the whole 23:59:59 second, every night. CI run
  160's Android device job ran from 23:46 to 00:06 in Asia/Kolkata and a
  checkout was correctly refused `RESTAURANT_NOT_ACCEPTING_ORDERS`. Both now
  write an overnight `00:00:00 – 00:00:00`, which is what a twenty-four hour
  restaurant already means in this schema. Covered by
  `test_a_restaurant_open_around_the_clock_is_open_through_midnight`, which
  asserts every second from 23:59:57 to 00:00:01. Control: restoring
  `23:59:59` fails it. KI-033.
- **M17-087 A screen must not present a status it has stopped checking.** The
  tracking screen showed a cached order behind an "it may have changed" banner
  with no upper bound, so half an hour old and two days old read the same — and
  the two strings for saying the age were already in `AppStrings`, used nowhere.
  The age is now shown, and past `TrackingConfig.vouchedFor` (the polling
  budget) the status and the timeline are withheld while the facts that do not
  change stay. Covered by `mobile/test/order_tracking_freshness_test.dart` (13)
  and four cases in `order_tracking_test.dart`. Controls: always vouching fails
  two; removing the backwards-clock guard fails one; reporting hours as minutes
  fails one. KI-031.
- **M17-088 A scheduled sweep with no caller needs a test, or it can be deleted
  silently.** `payments:reconcile` — the third path to a confirmed payment, for
  when both the callback and the webhook were lost — was never registered in
  `routes/console.php` and would never have run. It is now scheduled every
  fifteen minutes, matching the grace period the command itself insists on.
  More importantly the schedule now has a guard:
  `tests/Feature/Console/ScheduledCommandsTest.php` asserts all four money
  sweeps, their cadences and their `withoutOverlapping()`. Controls: dropping
  the reconciler fails two; demoting the capture sweep to daily fails one;
  removing an overlap guard fails one. KI-025.
- **M17-089 One order vocabulary, not two.** The speculative `OrderStatus` from
  Module 02 is deleted and everything that used it — chip, track, palette, home
  card, fixtures — takes `PlacedOrderStatus`. KI-021 set its own closing
  condition ("when a fulfilment workflow is specified, one of the two goes") and
  Module 17 met it. Where the copy differed, Module 17's wording won. The
  progress track now asks `isOnFulfilmentPath` rather than naming `cancelled`,
  which fixes a latent bug: five states leave the path, not one, and a rejected
  order would have been drawn with four steps still to come. `isActive` was
  deliberately not carried over — the server owns it. KI-021.
- **M17-090 A test must wait for a condition, not for a duration.**
  `place_search_test.dart` slept 20 ms after `retry()` and asserted the request
  had returned; it failed once under load and passed four times after. Replaced
  with a `waitUntil` helper. Control: a no-op `retry()` fails it in five seconds
  with a legible message. KI-034.
