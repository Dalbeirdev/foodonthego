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

## Module 05 — Trip Planner: Origin, Destination & Trip Creation

**Reworked.** A first pass built a journey planner — departure times, traveller
counts, notes, upcoming/past/cancelled scopes — derived from the project roadmap
rather than from the specification. The specification is narrower and different:
choose an origin, choose a destination, create a trip, and stop before anything to
do with a route. The first pass was replaced rather than extended. What follows
describes the module as it now stands.

### Added

**Backend (Laravel 12.69.1, MySQL 8.0.46)**
- `trips`: two endpoint blocks of ten columns each — source type, provenance
  address id, place id, name, formatted address, **NOT NULL** latitude and
  longitude, city, region, country, postal code — plus `status`, `route_status`
  and `cancelled_at`. No distance, duration, polyline or ETA column exists.
- `TripStatus` (`ROUTE_PENDING`, `CANCELLED`), `RouteStatus`
  (`NOT_CALCULATED`, `CALCULATING`, `READY`, `FAILED`), `LocationSourceType`
  (`CURRENT_LOCATION`, `SAVED_ADDRESS`, `PLACE_SEARCH`).
- `Trip` model with an **empty `$fillable`**: every column is written by name.
- `LocationSelection` value object with a haversine distance and the same-place
  rule (matching place id, matching saved address, or ≤ 75 m).
- `TripService`: endpoint resolution, coordinate validation including the (0, 0)
  sentinel, the same-place check, a locked open-trip limit, `ownedByOrFail()`,
  and `discard()`.
- Place provider abstraction — `PlaceProvider` with `GooglePlacesProvider`,
  `UnconfiguredPlaceProvider` and `DevelopmentGazetteerProvider`, bound by
  `PlacesServiceProvider` and guarded by `ProductionConfigGuard`.
- `PlaceController`: `search`, `show`, `reverse-geocode`. Authenticated, cached by
  query alone, every provider failure flattened to one opaque code.
- `TripController`: `index` (filtered by `status`), `current`, `show`, `store`,
  `discard`. No `DELETE` route exists.
- Ten new error codes; `TripLoggingTest` reads the log file on disk.
- 408 tests (up from 391).

**Flutter (3.47.2)**
- `Trip`, `TripEndpoint`, `TripLocation`, `TripDraft`, `PlaceSuggestion`,
  `PlaceDetails` — none of which has anywhere to put a distance or an ETA.
- `LocationService` with a sealed result covering all six outcomes, a
  `GeolocatorLocationService`, and a 25-second hard deadline.
- `PlaceSearchController`: 350 ms debounce, session-token lifecycle, generation
  guard against stale answers.
- `TripPlannerController`, `CurrentLocationController`, a reworked
  `TripsController`.
- `TripPlannerScreen`, `LocationPickerSheet`, reworked `TripsScreen`,
  `TripDetailScreen`, `TripListItem` and `CurrentJourneyCard`.
- "Find this address" on the address form, which closes a Module 04 gap: the API
  accepted coordinates and the client never sent any.
- `geolocator` dependency.
- 312 tests (up from 287), including the search race, the permission matrix and
  the accessibility of every labelled row.

### Fixed outside this module

- **Module 01.** `EnforceIdempotency` derived its actor from `$request->user()`,
  read before authentication runs, so two retries of one request could land on
  different cache keys and both execute. It now fingerprints the `Authorization`
  header.
- **Module 04.** `AddressDraft` never sent `latitude`/`longitude`, so no saved
  address could be used as a trip endpoint.

### Removed

The whole of the first pass: `JourneyEndpoint`, `TripScope` (the service one),
`TripRequest`, `UpdateTripRequest`, `CancelTripRequest`, `TripFormScreen`,
`PlacePickerSheet`, and every departure-time, traveller-count and note field on
both sides of the wire.

### Deliberately not built

Everything Module 06 owns, and the boundary is in the schema rather than in a
convention: route calculation, polyline, geometry, distance, travel duration,
traffic-aware timing, route alternatives, route display and route validation.

Also not built: menu, cart, checkout, payment, orders, the ETA engine,
WebSockets, push notifications, QR pickup, reviews and support workflows.


---

## Module 06 — Maps, Route Calculation, Distance & Travel Time

### Added

**Backend**
- `trip_routes` migration: 21 columns, a unique `(trip_id, provider_route_index)`,
  an index on `(trip_id, is_selected)`, and a **virtual column plus unique index**
  that makes two selected routes for one trip unrepresentable.
- `App\Services\Routing`: `RouteProvider` interface, `GoogleRouteProvider`
  (Routes API v2 `computeRoutes`, six-field mask), `UnconfiguredRouteProvider`,
  `DevelopmentRouteProvider`, `RouteRequest`, `RouteOption`, `RouteBounds`,
  `RouteResult`, `RouteValidator`, `RouteCalculationService`,
  `RouteSelectionService`, `RouteProviderException`, `RouteFailureKind`.
- `Support\Route\PolylineCodec` and `Support\Trip\EndpointFingerprint`.
- `TripRoute` model with an **empty `$fillable`**, `toApiArray()` and a
  geometry-free `toApiSummaryArray()`.
- `Trip::routes()`, `selectedRoute()`, and `selectedRouteSummary()` — guarded by
  both the status and the endpoint fingerprint.
- `TripRouteController`: `GET /trips/{trip}/routes` (never calculates),
  `POST /trips/{trip}/route/calculate` (`?refresh=1`),
  `POST /trips/{trip}/routes/{route}/select`.
- `RouteStatus` gains `NO_ROUTE` and `STALE`, plus `hasUsableRoute()` and
  `isRetryable()`.
- `ApiErrorCode` gains 11 routing codes.
- `config('foodonthego.routing')` and the matching `.env.example` block.
- 527 tests (up from 408): `PolylineCodecTest`, `RouteProviderTest`,
  `RouteValidatorTest`, `RouteCalculationServiceTest`, `TripRouteApiTest`,
  `TripRouteOwnershipTest`, `RouteLoggingTest`.

**Mobile**
- `core/geo/polyline_codec.dart` — `GeoPoint`, decode, encode, great-circle
  distance.
- `domain/models/trip_route.dart` — a route with no distance, no duration or no
  geometry does not construct; geometry that will not decode draws nothing rather
  than throwing.
- `core/format/journey_measures.dart` — distance, duration, traffic delay (null
  under a minute), comparison, and "calculated N minutes ago".
- `core/config/maps_config.dart` — the Maps key, the supported platforms, and one
  place that knows whether a map is possible.
- `data/repositories/api_route_repository.dart`, `shared/state/route_controller.dart`
  with nine distinct failure kinds.
- `features/routes/`: `RouteScreen`, `RouteMapView`, `MapUnavailableView`,
  `RouteOptionCard`.
- `google_maps_flutter` dependency.
- 382 tests (up from 312), a great many of which do nothing but assert the
  provider was **not** called.

**Tooling**
- `mobile/tool/route_smoke.dart` — 21 assertions against a running server and a
  real database, printing what the configured provider actually returned rather
  than asserting against numbers baked into the test.
- `mobile/tool/support/smoke_support.dart` — the session, sign-in and assertion
  helpers the smoke runs share.

**Documentation**
- `21-maps-and-routing.md`, and updates to 02, 05, 06, 07, 08, 09, 11, 12, 13,
  14, 15, 17 and 20.

### Fixed outside this module

- **Module 01.** An unauthenticated request that did not announce
  `Accept: application/json` was answered **500** instead of 401: Laravel's
  default guest redirect points at a `login` route this API does not have, and
  the redirect threw before the authentication exception could be rendered.
- **Module 03.** `AuthController.restore()` wrote `state` after two async gaps
  with no disposal check, throwing whenever a scope was torn down mid-restore.

### Deliberately not built

Everything Module 07 and the ETA engine own: restaurant discovery along the
selected route, cooking-start prediction, restaurant preparation intelligence,
live GPS progress, and any dynamic customer ETA during a journey.

The number this module produces is a **travel duration** — the routing provider's
estimate of the drive — and the UI says so in those words. It is not the
FoodOnTheGo ETA, and the word "ETA" appears nowhere in the module's interface.
