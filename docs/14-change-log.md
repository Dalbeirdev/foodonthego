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
