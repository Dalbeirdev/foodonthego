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

## Module 04 — Customer Profile & Saved Addresses

### Added

**Backend (Laravel 12.69.1, MySQL 8.0.46)**
- Profile self-service: `GET /customer/profile` and `PATCH /customer/profile`, the latter accepting
  exactly three fields — `first_name`, `last_name`, `email`.
- Saved addresses: `GET`, `POST`, `GET/{uuid}`, `PATCH/{uuid}`, `DELETE/{uuid}` and
  `POST /{uuid}/default` under `/api/v1/customer/addresses`. No route carries a customer identifier.
- `customer_addresses` migration — uuid route key, typed address, optional landmark and postal code,
  nullable coordinates, `place_id` reserved for Module 05, and a stored generated column
  `default_for_customer` under a unique index, so at most one default per customer is a database
  guarantee rather than a service convention.
- `CustomerAddressService` — list, ownership-scoped read, create under a row lock with a per-customer
  limit, update, hard delete that promotes the newest survivor, and default transfer.
- `CustomerProfileService` — allow-listed writes, blank optional fields normalised to `NULL`, and an
  email change that clears `email_verified_at`.
- `AddressType` enum (Home / Work / Other, with a custom label required only for Other),
  `AddressFormatter`, and a per-country `PostalCode` rule table.
- `ApiErrorCode`: `ADDRESS_LIMIT_REACHED` (422) and `ADDRESS_NOT_FOUND` (404).
- `config/foodonthego.php`: `addresses.max_per_customer`, `addresses.default_country_code`.
- Address creation reuses Module 01's `Idempotency-Key` middleware.

**Mobile (Flutter)**
- Edit-profile screen with the verified phone rendered read-only, and saved-address list, create and
  edit screens with real loading, empty, error, retry and per-row busy states.
- `SavedAddress` / `AddressDraft` models, `ApiCustomerRepository`, and `AddressesController`, a
  Riverpod `AsyncNotifier` that watches the auth session so no address state can outlive it.
- `ApiClient` gained `patch`, `delete` and `getList`.
- `tool/profile_addresses_smoke.dart` — 24 assertions against the real API and MySQL, including the
  full IDOR matrix between two accounts.

**Documentation**
- `19-customer-profile-and-addresses.md`; Module 04 traceability (40 requirements) and bug register (8).

### Changed

- `AuthController` gained `updateProfile()`, so a saved profile updates the session's customer
  without a round trip through sign-in.
- The Profile tab's "Saved addresses" and "Edit profile" rows open real screens instead of the
  Module 02 placeholders; the row shows a live address count.
- `customer_addresses.customer_id` is `RESTRICT`, not `CASCADE` — MySQL refuses a cascade on a column
  a stored generated column depends on. Recorded as KI-009.
- Address type labels drop their icons below 320dp of usable width rather than wrapping mid-word.

### Fixed

Eight defects, all found by the tests and the live-view run written for this module and all retested
— full table in [13-known-issues.md](13-known-issues.md). The ones worth naming here:

- **M04-B03** (critical) — both forms were built on a `ListView`, which builds lazily, so fields
  scrolled off screen were never registered with the `Form` and `validate()` silently skipped them.
  An invalid address could be submitted. Both forms now use a non-lazy scrolling `Column`.
- **M04-B01/B02** — Laravel appends `NOT NULL` to a `rawColumn`, so the generated default column
  stored `0` rather than `NULL` for every non-default row and the second address a customer saved
  collided on the unique index.
- **M04-B04** — the primary action sat below the fold on a small screen and the tap landed on the
  bottom navigation bar. Both forms now pin the action above the keyboard.
- **M04-B07** — create returned `28.5602` where a subsequent read returned `28.5602000`; the service
  now refreshes the model after saving so the response is what the database holds.
- **M04-B08** — `tool/integration_smoke.dart` indexed a log by byte offset into a Dart string; the
  masking character is three UTF-8 bytes and one UTF-16 unit, so the drift grew with every masked
  number until the tool threw a `RangeError`.

### Not done, and why

- Android and iOS device verification — KI-001, KI-002 (environment).
- Geocoding and Google Places autocomplete — the schema carries `latitude`, `longitude` and
  `place_id`, and they stay `NULL` until Module 05 actually resolves an address. Inventing a
  coordinate from typed text would put a fabricated point into the routing engine.
- Email verification — an email is stored and displayed unverified.
- Changing the verified phone number — that is a re-verification flow, not a profile field.

## Module 05 — Trip Planner: Origin, Destination & Journey Creation

### Added

**Backend (Laravel 12.69.1, MySQL 8.0.46)**
- Journeys: `GET`/`POST` on `/api/v1/customer/trips`, `GET /next`, and
  `GET`/`PATCH`/`POST /{uuid}/cancel`. No route carries a customer id, and there
  is no DELETE — a journey is cancelled, never removed.
- `trips` migration — uuid route key, an eight-column **snapshot** of each end of
  the journey plus a nullable provenance link to the saved address it came from,
  a UTC departure, a nullable stated arrival, traveller count, note, and the
  cancellation pair.
- `TripService` — list by scope, the next journey, ownership-scoped read, create
  under a row lock with a per-customer limit on journeys still ahead, partial
  update, and cancellation that refuses to happen twice.
- `JourneyEndpoint` — the value object both a saved address and a typed place
  become, so the rest of the module deals with one shape.
- `TripStatus` enum with **two** cases, `TripScope`, and three `ApiErrorCode`
  cases: `TRIP_NOT_FOUND` (404), `TRIP_LIMIT_REACHED` (422),
  `TRIP_NOT_EDITABLE` (422).
- `config/foodonthego.php`: `trips.max_upcoming_per_customer`,
  `trips.max_days_ahead`, `trips.departure_grace_minutes`, `trips.max_travellers`.

**Mobile (Flutter)**
- The Trips tab: three scopes over one list, with loading, empty, error and data
  states, a row menu that names its own row, and cancellation with a reason.
- A planner used for both creating and editing, with a place picker that offers
  the customer's Module 04 saved addresses first and a short form for anywhere
  else.
- A journey detail screen that says why it is read-only when it is.
- `Trip`, `JourneyPlace`, `TripDraft`, `JourneyPlaceDraft`, `ApiTripRepository`,
  `TripsController` and `NextTripController` — both controllers watching the auth
  session so no journey state can outlive it.
- `JourneyTime` — the module's date and time formatting, written rather than
  pulling in `intl` for four formats.
- `ApiClient.getOrNull()`, for an endpoint where a null answer is ordinary.
- `tool/trip_planner_smoke.dart` — 30 assertions against the real API and MySQL.

**Documentation**
- `20-trip-planner.md`; Module 05 traceability (46 requirements) and bug register (5).

### Changed

- The home screen shows the customer's **real** next journey from
  `/customer/trips/next`, with a card that shows only where, when and how many.
- The "Plan a journey" call to action opens the real planner instead of the
  placeholder that named this module.
- `EmptyStateView` shrinks its motif below 420px of height, so a primary action
  is never pushed below the fold on the smallest supported screen.
- `TripDraft.travellerCount` has no default, so a partial update cannot send a
  count the customer never chose.

### Removed

- `ActiveTripSummary`, `RouteSummaryCard` and `HomeDashboard.activeTrip`. They
  were Module 02 scaffolding for exactly this moment; holding a second,
  fixture-shaped journey next to the real one is how two halves of one screen
  come to disagree about whether somebody is travelling. Their `TripStatus` enum
  went with them, which also removes a name that now had two meanings.
- The greeting's `isTravelling` branch and its string. Nothing observes travel
  yet, and a planned journey is not a journey in progress. Module 09 brings the
  branch back with a signal behind it.

### Fixed

Five defects, all found by the tests, the database review or the live-view run
written for this module, and all retested — full table in
[13-known-issues.md](13-known-issues.md). The ones worth naming here:

- **M05-B03** — the Trips empty state's only action sat 13px below a 320×568
  screen. Reachable by scrolling, but a call to action that has to be hunted for
  is one most people never see. Fixed in the shared empty state, so every empty
  screen in the app benefits.
- **M05-B04** — a partial update silently reset the traveller count, because the
  client draft defaulted it to 1. The API assertions could not see it: the update
  response reported the right number and the row underneath held the wrong one.
  Found by reading the database back after the integration run.
- **M05-B02** — the cancel dialog disposed its text controller while its own exit
  animation was still building the field.
- **M05-B01** — `create()` leaned on the form request for the departure check
  while `update()` enforced it itself, so any caller reaching the service another
  way could write a journey into the past.

### Not done, and why

- Android and iOS device verification — KI-001, KI-002 (environment).
- Routing, corridors, distance, duration and restaurant discovery — Module 09.
- Geocoding and Places autocomplete — the schema carries `place_id` at both ends
  and nothing fills it. Coordinates stay `NULL`.
- GPS and live tracking — and `TripStatus` has two cases rather than five because
  of it, instead of carrying states nothing can establish.
- The ETA engine — scheduled with Modules 08 and 09.
