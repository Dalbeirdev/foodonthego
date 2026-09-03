# 14 — Change log

## Module 01 — Foundation, Architecture & Design System

### Added

**Backend (Laravel 12.69.1, PHP 8.4)**
- `/api/v1` route structure with a `Route::fallback()` that answers in the error contract
- `ApiResponse` envelope: `ok`, `created`, `noContent`, `paginated`, `error`
- `ApiErrorCode` (11 codes) and `ApiException` with named constructors
- `ApiExceptionRenderer` — one contract for every throwable; 5xx never self-describes
- `AssignRequestId`, `SecureHeaders`, `LogApiRequests`, `EnforceIdempotency` middleware
- `StructuredFormatter` / `StructuredLogger` — JSON logs with depth-bounded redaction
- `Role` enum (7 roles) with surface routing
- `ProductionConfigGuard` — refuses to boot a misconfigured staging/production
- `HealthController` (live + ready) and `MetaController`
- `users` migration establishing the database conventions; `User` model
- `config/foodonthego.php`, `config/cors.php`, `pint.json`, `.env.example`
- 67 tests

**Web (React 19, TypeScript 5.7, Vite 6)**
- `@fotg/ui`: design tokens, base styles, primitives, `AppShell`, API client, health hook
- `@fotg/restaurant`: 11-area dashboard shell
- `@fotg/admin`: 14-area admin shell, including a live **System Health** page
- 29 tests

**Mobile (Flutter 3.47.2, Dart 3.13)**
- `core/theme`: tokens, typography, light and dark themes
- `core/router`: `FotgAppShell` with five destinations over an `IndexedStack`
- `features/`: home plus four placeholder screens
- `shared/widgets`: `ModulePlaceholder`, `FotgCard`
- `web/flutter_bootstrap.js` self-hosting CanvasKit
- 19 tests

**Docs** — 15 documents.
**CI** — `.github/workflows/ci.yml` for backend, web and Flutter.

### Removed

The repository previously contained a **different product on a different stack**: a generic
food-delivery app (Fastify + SQLite + a React storefront), built before the route-based product
definition and the Laravel/MySQL/Flutter architecture were specified. It was removed wholesale
rather than adapted — the domain and the stack both differ. It remains in git history and in the
pull request that introduced it.

### Fixed

Thirteen defects found during Module 01, listed with root causes in
[13-known-issues.md](13-known-issues.md). The ones worth repeating:

- A WCAG AA contrast failure in the brand palette (3.31:1) — caught by a test that computes the ratio
- A CORS misconfiguration that blocked every browser request — caught by live browser inspection
- A catch-all route that made 405 impossible and shadowed later routes
- A topbar that only fitted while the API was up


---

## Module 02 — Customer Mobile App Shell, Navigation & Premium Home

### Added — mobile only; backend and web untouched

**Foundation**
- `AppEnvironment` — a compile-time constant from `--dart-define=FOTG_ENV`, so the fixture branch is
  tree-shaken out of a release build rather than merely unused
- `FeatureFlags` — one flag per significant capability, all off, each owned by its module
- `AppStrings` + `AppStringsDelegate` — every user-visible string, localization-ready
- `Analytics` boundary and `AnalyticsEvents` names — no vendor SDK, by design
- `ConnectivityService` with an always-online production default and a controllable one for
  development

**State and routing**
- **Riverpod 3** chosen and documented (Module 01 left it undefined). Do not add a second.
- **go_router** with `StatefulShellRoute.indexedStack` — per-branch navigators, so tabs keep state
  and Android back works
- `/coming-soon` as the one controlled destination for unbuilt features

**Domain and data**
- `CustomerSummary`, `ActiveTripSummary`, `ActiveOrderSummary`, `OrderStatus`, `HomeDashboard`
- `HomeRepository` boundary plus `HomeLoadFailure` with four kinds
- `FixtureHomeRepository` (four personas) and `UnconfiguredHomeRepository` (invents nothing)

**Screens** — Home with three states, Trips, Orders, Notifications, Profile, ComingSoon

**Components** — `PrimaryButton`, `SecondaryButton`, `LinkAction`, `SectionHeader`, `EmptyStateView`,
`AppErrorView`, `OfflineBanner`, `AppSkeleton`, `HomeSkeleton`, `OrderStatusChip`,
`OrderStatusTrack`, `CustomerShell`, `GreetingHeader`, `JourneyPlannerCard`, `RouteSummaryCard`,
`ActiveOrderCard`, `QuickActions`, `HowItWorks`

**Development harness** — persona / offline / failure switches, development builds only

**Tests** — 82, up from 19

**Docs** — new `16-mobile-navigation.md` and `17-customer-app-ui.md`; updated 08, 09, 11, 12, 13, 15

### Changed

- `FotgTheme` button minimum sizes use `Size(0, h)` rather than `Size.fromHeight(h)`, whose infinite
  width silently forced every button to fill its parent
- Module 01's `FotgAppShell` replaced by the go_router shell; its tests rewritten

### Fixed

Eight defects, in [13-known-issues.md](13-known-issues.md). The three worth repeating:

- **A silent retry loop.** Riverpod 3 retries failed providers automatically — on a highway that
  burns battery and data on requests that cannot succeed, while *Try again* does nothing observable.
- **The greeting lost the customer's name at 320dp**, truncating to "Good evening, R…".
- **The development harness crashed the app**, because `MaterialApp.builder` sits above the Navigator
  and the handle's `Tooltip` found no `Overlay`.

---

## Module 03 — Customer Authentication, Registration, OTP, Session & Security

### Added

**Backend (Laravel 12.69.1, Sanctum 4.3.3)**
- Phone + OTP sign-in: `POST /auth/customer/otp/request`, `POST /auth/customer/otp/verify`,
  `POST /auth/customer/register`, plus `GET /customer/me` and `POST /auth/logout` behind a token.
- `OtpChallengeService` — CSPRNG codes, peppered SHA-256 HMAC storage, constant-time comparison,
  expiry, single use, attempt exhaustion that kills a correct code, and supersession on resend.
- `RegistrationTokenService` — an encrypted, signed, short-lived token that carries the verified
  number so registration cannot be pointed at a different one.
- `PhoneNormalizer` / `PhoneNumber` — E.164 normalization for four markets, trunk-prefix handling,
  and a masking form shared with the client.
- OTP sender abstraction: `LogOtpProvider` (development, refuses production) and
  `UnconfiguredOtpProvider` (the production default, fails loudly).
- `OtpRateLimiter` — per-phone and per-IP budgets on hashed keys; a server-enforced resend cooldown.
- `EnsureRole` middleware, plus Sanctum's `abilities`/`ability` aliases, so a protected route states
  its account kind and its token scope rather than only its authentication.
- `AccountStatus` enum and gating; 12 new `ApiErrorCode` cases.
- `otp:prune` artisan command, scheduled daily, with a 48-hour retention window.
- Migrations: customer identity on `users` (`first_name`, `last_name`, `phone_e164` unique,
  `status` ENUM, `last_login_at`; `password`/`email`/`name` made nullable), `otp_challenges`, and
  Sanctum's `personal_access_tokens`.

**Mobile (Flutter)**
- Welcome, phone entry with a country picker, code entry, and registration screens.
- `ApiClient` — the single place the app speaks HTTP, unwrapping the documented envelope and
  translating failures into `ApiErrorCode`.
- `SecureSessionStore` — Keychain / Android KeyStore, never plaintext preferences.
- `AuthController` + `AuthState` — session restore that is confirmed with the server but survives a
  network outage, and one 401 anywhere ending the session everywhere.
- Router guard over every protected route, with `SessionSplash` so restore never flashes.
- `authErrorMessage()` — code-to-wording mapping, never the server's prose.
- `tool/integration_smoke.dart` — a real run against Laravel and MySQL.

**Documentation**
- `18-customer-authentication.md`; Module 03 traceability (42 requirements) and bug register (12).

### Changed

- `config/sanctum.php`: `guard` emptied, so a session cookie can never authenticate an API request.
- `ProductionConfigGuard` now refuses to boot on a sender that cannot reach a real handset, or while
  the simulated-failure switch is on.
- `UnconfiguredHomeRepository` carries the signed-in customer's real name; the profile header reads
  the session rather than the home dashboard payload.
- `SecondaryButton` gained `isLoading`, matching `PrimaryButton`'s contract.
- `PhoneFormRequest` extracted so requesting and verifying cannot normalize differently.
- KI-005 renumbered where it had been used twice for different issues.

### Fixed

Thirteen defects, all found by the tests and the live-view run written for this module and all
retested — full table in [13-known-issues.md](13-known-issues.md). The ones worth naming here:

- **M03-B01** — the OTP transaction closure never captured `$code`, so every challenge stored the
  hash of an empty string and no code could ever verify.
- **M03-B02/B03** — PHP casts numeric string array keys to int, so the country table's keys came
  back as integers: every international number raised a `TypeError`, and the country list was
  serialised as numbers.
- **M03-B07** — the country picker, built as a `prefixIcon` around an aligned `Container`, expanded
  to fill the whole field and made the number being typed invisible.
- **M03-B10** — `users.status` shipped as `varchar` where `role` is a MySQL `ENUM`, against the
  Module 01 convention.
- **M03-B13** — the OTP countdowns decremented a counter on a timer, and both platforms suspend
  timers for a backgrounded app; switching to the SMS app to read the code froze the clock the
  customer was watching. Now derived from absolute deadlines.

### Not done, and why

- Android and iOS device verification — KI-001, KI-002 (environment).
- Token revocation when an account is suspended — KI-008; belongs with the admin module that
  performs the suspension.
- Profile editing, saved addresses, social sign-in, biometric unlock — later modules.
