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
  performs the suspension. (Read alongside the entry after Module 17: the *serving* half of this
  was closed there. What is still outstanding is deleting the token row, not refusing the request.)
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

---

## Module 07 — Restaurant Discovery Along the Selected Route

### Added

**Backend**
- `restaurants` migration: identity, position (nullable coordinates, and that
  nullability is a rule), visibility (`status`, `verification_status`,
  `is_discoverable`, `is_accepting_orders`), preview metadata, and seven columns
  that must never reach a customer — present so the privacy tests have something
  real to catch.
- `restaurant_cuisines`, `restaurant_facilities`, `restaurant_opening_hours`:
  tables rather than JSON columns, because Module 08 filters on all three.
- `RestaurantStatus`, `RestaurantVerificationStatus`, `RestaurantAvailability`
  enums.
- `App\Support\Geo`: `Coordinate`, `Distance` (haversine for reported figures,
  equirectangular for the inner loop), `RouteGeometry` (decode, simplify,
  cumulative distance, projection, bounding box), `RouteProjection`.
- `App\Services\Discovery`: `RestaurantDiscoveryEligibilityService`,
  `RestaurantAvailabilityService`, `RestaurantDetourService`, `DetourEstimate`,
  `DiscoveryRankingService`, `RestaurantDiscoveryService`,
  `DiscoveredRestaurant`, `DiscoveryResult`.
- `TripRestaurantController` and `GET /api/v1/customer/trips/{trip}/restaurants`,
  with its own `throttle:discovery`.
- `RouteRequest` gains `waypoints`; `GoogleRouteProvider` maps them to
  `intermediates` with `optimizeWaypointOrder: false`; `DevelopmentRouteProvider`
  bends its straight line through them so the detour arithmetic is exercised
  rather than skipped.
- Five routing error codes; a `discovery` rate limiter keyed by customer.
- `config('foodonthego.discovery')`: ten settings, every threshold a pilot
  assumption rather than a fact about the world.
- `DiscoveryTestRestaurantSeeder` — eight `[TEST]`-prefixed fixtures at computed
  positions, refusing to run in production.
- 693 tests (up from 527): `RouteGeometryTest`, `RestaurantEligibilityTest`,
  `RestaurantAvailabilityTest`, `RestaurantDiscoveryServiceTest`,
  `DiscoveryRankingTest`, `TripRestaurantApiTest`,
  `TripRestaurantOwnershipTest`, `DiscoveryLoggingTest`,
  `DiscoveryPerformanceTest`.

**Mobile**
- `domain/models/discovered_restaurant.dart` — `RestaurantAvailability`,
  `RouteRelation`, `DiscoveredRestaurant`, `RestaurantDiscovery`. A restaurant
  with no id, no name, no position or no relation to the route does not
  construct.
- `data/repositories/api_discovery_repository.dart` and
  `shared/state/discovery_controller.dart`, with eight distinct failure kinds and
  one field driving both the map's and the list's idea of "selected".
- `features/discovery/`: `DiscoveryScreen`, `DiscoveryMapView`,
  `DiscoveryMapUnavailableView`, `RestaurantPreviewCard`, `AvailabilityChip`.
- The Module 06 CTA — "Find food on this route" — is wired to a real screen.
- 453 tests (up from 382).

**Tooling**
- `mobile/tool/discovery_smoke.dart` — 22 assertions against a running server,
  real restaurant rows and Module 06's real stored geometry.

**Documentation**
- `22-restaurant-route-discovery.md`, and updates to 02, 05, 06, 07, 08, 09, 11,
  12, 13, 14, 15, 17, 20 and 21.

### Fixed outside this module

Nothing. Modules 01–06 needed no changes; `RouteRequest` gained an optional
field, which every existing caller ignores.

### Deliberately not built

The restaurant detail page, menus, cart, checkout, payments, order acceptance,
cooking status, the ETA engine, live GPS progress and pickup scheduling.

Also not built, and belonging to Module 08: customer-facing filters (cuisine,
price, rating, availability, facilities, detour), sort options, text search, and
marker clustering. The fields those need are stored, indexed where it matters and
returned; the ranking is a single deterministic function whose final ordering a
customer-chosen sort can replace without touching the pipeline.

**The figure this module produces about time is still a travel figure.**
`time_ahead_seconds` is the route's own duration scaled by how far along the stop
is — an interpolation of a real number, shown as "About 1 hr ahead". It is not a
pickup time, and `default_preparation_minutes` is stored but never added to it.

---

## Module 08 — Restaurant Search, Filters, Sorting & Discovery Ranking

Search, filters, a sort and pagination over the set Module 07 already decided
the customer may see.

### The shape of it

One new service sits between the discovery result and the response:

```
RestaurantDiscoveryService::discover()   database · provider · cache
DiscoveryRefiner::refine()               pure computation
```

Everything else follows from that split. The refiner has no repository, no
query builder and no connection, so a filter cannot reach a restaurant
eligibility removed, a search string cannot become SQL, and changing a filter
cannot call a routing provider. None of those are rules anyone has to remember.

### Added

- **Search** over name, cuisine and city, with scored relevance tiers that feed
  the recommended ranking. Unicode-safe normalisation; apostrophes elided so
  `rajeshs` finds `Rajesh's Dhaba`. 350 ms debounce, generation-checked
  responses.
- **Filters** for cuisine, facilities, price level, availability, maximum
  detour and distance ahead. Slug-based, validated, bounded. OR within cuisine
  and price, **AND** within facilities, AND across groups.
- **Sorts**: recommended (default), lowest detour, soonest along route, price
  low to high. `highest_rated` exists and is advertised as unavailable with a
  reason.
- **Facets** — the filter options this route can actually satisfy, with counts,
  in the discovery response. No hard-coded cuisine list in the client.
- **Pagination** with `total`, `eligible_total`, `filtered_empty`, `has_more`,
  and a reset to page 1 on any query change.
- **Ranking weights** in `config/foodonthego.php`, five env-overridable keys.
- Client: search field, filter sheet with draft state, removable chips, a
  counted badge, sort sheet, live result count, and three distinct empty
  screens.
- `mobile/tool/discovery_filters_smoke.dart` — 28 checks against a live server.
- 106 new backend test methods, 90 new Flutter test cases.

### Changed — and one of these changes Module 07's behaviour

- **`RestaurantDiscoveryService::discover()` no longer truncates.** The result
  limit moved from discovery to pagination, so filters see the whole eligible
  set. Without this, a "Parking" filter over the top 25 by relevance would
  silently hide the 26th restaurant on the route.
- **The default order is now `recommended`, not journey order.** An unfiltered
  discovery call returns restaurants ranked by availability and route
  convenience. Journey order is still available and unchanged, by name, as
  `sort=soonest_along_route`. The eligible universe is identical either way.
  `tool/discovery_smoke.dart` was updated to ask for journey order explicitly
  rather than assuming it is the default.
- `DiscoveryRankingService` takes its weights as a constructor argument instead
  of holding constants.
- `restaurant_cuisines` and `restaurant_facilities` gained stored generated
  `slug` columns and indexes; `restaurants` gained a `name` index.

### Fixed

Five defects, none left open, none Critical. The interesting one: the ranking
terms were written as an array keyed by weight, PHP cast the float keys to
`int`, they all collapsed to key `0`, and **every restaurant scored zero**. See
M08-B01 in `13-known-issues.md`.

### One housekeeping change outside the module

`dart format` under Dart 3.13.2 reformats 21 files written under an earlier SDK
— whitespace only, no behaviour, and it puts `dart format
--set-exit-if-changed` back to clean. Twelve of them are Module 10 and Module 11
sources; the rest are their tests and the smoke drivers.

### Not done, and said plainly

- **Rating filter and highest-rated sort are deferred.** No reviews module
  exists, so no restaurant has a rating. The client renders no rating control;
  the sort is refused with a reason. Nothing is fabricated to make either look
  functional.
- **Android and iOS runtime verification are pending** — no Android SDK
  (KI-001), no macOS host (KI-002). Verification was done against a release web
  build of the same Flutter code.
- **The detour filter's runtime exclusion is not applicable** under
  `ROUTE_PROVIDER=development` (KI-012): with a straight-line road network no
  in-corridor stop can exceed any ceiling the filter can set. The comparison is
  tested with controlled detours.
- **The distance-ahead filter has no control in the sheet.** The backend is
  complete and tested; the UI would be a sixth near-duplicate distance control
  in an MVP sheet that already has five groups.

---

## Module 09 — Restaurant Details, Facilities, Availability & Customer Preview

A restaurant's page, on the route the customer is actually driving.

### The shape of it

`RestaurantDetailService` asks Module 07 what is on the route and looks for the
requested restaurant in the answer:

```php
$result = $this->discovery->discover($trip, $now);       // cached, and the only
foreach ($result->restaurants as $found) {               // thing that can reach
    if ($found->restaurant->uuid === $uuid) return $found; // a provider
}
```

Eligibility cannot be bypassed, the route figures cannot disagree with the card,
and no provider is called — none of which is a rule anybody has to remember.

### Added

- **`GET /customer/trips/{trip}/restaurants/{restaurant}`**, sharing discovery's
  throttle.
- **`RestaurantHoursService`** — today, the whole week including its shut days,
  the current window, and when a closed restaurant opens again. Overnight
  windows belong to the day they open, so a dhaba trading 18:00–02:00 is open at
  one in the morning.
- **`RestaurantOrderingState`** — five cases rolling up business status and
  availability. `availability` keeps Module 07's meaning; this is the derived
  one, and a response carries both.
- **`restaurant_media`**, plus `description` and `public_phone`. `is_active`
  defaults to false and the relation filters on it, so an unmoderated image is
  unreachable rather than merely unrequested.
- **The detail screen**: hero gallery with a branded fallback, header,
  availability chip and banner, the route card, description, facilities, hours,
  location, and a sticky button whose state is the ordering state and nothing
  else.
- Three fixtures whose whole purpose is this screen: an overnight kitchen, a
  split service with a day off, and one with no optional metadata at all.
- `tool/restaurant_detail_smoke.dart` — 25 checks against a live server.
- 60 new backend test methods, 74 new Flutter test cases.

### Changed

- `DiscoveredRestaurant` gained `withRestaurant()` and `withAvailability()`, so
  the detail screen can describe the same place on the route with a freshly read
  row. The route geometry is kept: where a restaurant sits does not change
  because somebody paused their kitchen.
- The discovery card's **View** button became its own semantics node, named with
  its restaurant. It previously had no node at all — see M09-B01.
- The discovery card's `excludeSemantics` became `explicitChildNodes` plus an
  inner `ExcludeSemantics`, preserving the one-sentence label.
- Module 08's integration run now expects eight eligible restaurants rather than
  five, because Module 09's fixtures are on the same road.

### Fixed

One defect, High, none left open: a screen-reader user could not open a
restaurant's page at all.

### Not done, and said plainly

- **Ratings are absent, not zero.** No reviews module exists, so `rating` is
  null and the screen shows **New**. The parser, the widget and the filter are
  all tested against controlled data and switch themselves on the day a rating
  is written.
- **Android and iOS runtime verification are pending** — no Android SDK
  (KI-001), no macOS host (KI-002). Verification was done against a release web
  build of the same Flutter code.
- **The location section is not a map.** It shows the address, the published
  phone where there is one, and a control that returns to the discovery map,
  which already draws this restaurant against the route. A second full map here
  would be the same screen twice, and FoodOnTheGo is not a navigation app.
- **Detour magnitude is not meaningful** under `ROUTE_PROVIDER=development`
  (KI-012). What this module establishes is that the page shows the same figure
  the card did, without calling a provider again.

---

## Module 10 — Menu, categories and menu item browsing

### Added

- **`Money`, twice.** A readonly PHP value object and a Dart class, both holding
  an integer count of minor units and a currency, and neither with a
  `toDouble()`. This is the project's first money convention and every later
  module inherits it.
- **`menu_categories` and `menu_items`.** Money as `unsignedInteger
  base_price_minor` — unsigned so a negative price cannot be stored at all.
- **A composite foreign key** on `menu_items(menu_category_id, restaurant_id)`
  referencing `menu_categories(id, restaurant_id)`, with the redundant-looking
  `UNIQUE(id, restaurant_id)` that makes it possible. An item belonging to one
  restaurant cannot be filed under another's category, by any route including a
  direct `INSERT`.
- **`GET …/restaurants/{restaurant}/menu`** and
  **`GET …/menu/items/{item}`**. Both go through Module 09's eligibility, so a
  menu cannot be opened for a restaurant whose page could not be.
- **`CustomerMenuService`**, two queries whatever the size of the menu.
- **`MenuSearch`**, in memory over items already fetched — so a search cannot
  reach an item the visibility rules excluded, and a term never becomes SQL.
- **The Flutter menu screen**: pinned section selector that leads *and* follows,
  debounced search, sold-out treatment, two distinct empty states, and a
  read-only item sheet.
- **`MenuTestDataSeeder`**, development-only and `[TEST]`-marked, with fixtures
  for every edge the module names: nothing-optional, sold out, withdrawn item,
  withdrawn category with a live item inside, time-limited section, ₹0, ₹12,999,
  a 60-character name, and a restaurant with no menu at all.

### Changed

- **`RestaurantDetailService` gained `orderingContext()`**, the eligibility half
  without the profile. `detail()` now builds on it, so the two screens cannot
  drift on who may see what — and the menu no longer loads photographs,
  cuisines, facilities and a fortnight of opening hours it never renders.
  Twenty queries a menu open, down to seventeen.
- **`MenuItem::toCustomerArray()` takes its category as an argument.** Reading
  the inverse relation would be one query per item; requiring the argument makes
  that impossible rather than merely absent.
- `intl` added to the Flutter app, for locale-driven currency formatting.

### Fixed

Two defects, both found by running the thing rather than by reading it, neither
left open — see [13-known-issues.md](13-known-issues.md):

- **M10-B01 (High).** The client's dietary-type wire strings were `VEG` and
  `NON_VEG`; the server sends `VEGETARIAN` and `NON_VEGETARIAN`. Every diet
  badge would have been silently absent in production — and every widget test
  passed, because the fixtures built domain objects directly and never crossed
  the JSON boundary. A test now asserts the four strings literally.
- **M10-B02 (Low).** A punctuation-only search (`%%`, `--`, `...`) normalised to
  nothing, matched every item, and came back as *the whole menu labelled the
  result for `%%`*. Such a term is now discarded, so the menu is returned
  honestly unfiltered.

### Not done, and said plainly

- **No allergen information exists**, so none is shown. There is no allergen
  column, no allergen UI and no allergen string on the wire; the integration run
  asserts the word does not appear. When operator-declared allergens exist they
  will be shown like every other optional field — present when published, absent
  when not.
- **Nothing can be ordered.** No cart, no variants, no add-ons, no quantity
  stepper — and no disabled "Add" button either, because a dead button promises
  a cart that does not exist. `is_orderable` drives what the screen *says*.
- **Android and iOS runtime verification are pending** — no Android SDK
  (KI-001), no macOS host (KI-002). Verification was against a release web build
  of the same Flutter code, driven through its real semantics tree.
- **Only English ships.** `Money.format` is asserted against `en_IN` and `en_US`
  so the mechanism is proved locale-driven rather than hard-coded, but no
  non-English locale exists to exercise.
- **The suspended-versus-missing distinction is inherited.** Both answer 404;
  the error *codes* differ, which is Module 09's documented trade-off. Recorded
  in [25-customer-menu-browsing.md](25-customer-menu-browsing.md) rather than
  silently changed here.

---

## Module 11 — Menu item details, variants, add-ons, customization and Add to Cart

### Added

- **`menu_item_variants`.** Sizes, with an **absolute** price — "Large ₹329" is
  what the dish costs, not what it costs extra.
- **`menu_modifier_groups`, `menu_modifier_options`, and the item pivot.** The
  questions a kitchen asks and their answers, with the rule stored as two
  numbers (`min_select`, `max_select`) rather than a flag.
- **`carts`, `cart_items`, `cart_item_modifiers`.** The minimum that makes Add
  to Cart mean something. No cart screen.
- **`CustomizationSelection`** — a value object with no price, no total and no
  discount, so there is nothing in an add-to-cart request to tamper with.
- **`CustomizationValidator`** — ownership, then availability, then the rules,
  all against rows read in the request that writes.
- **`MenuItemPricingService`** — the only thing in the application that decides
  what a configuration costs.
- **`CartService`** — one active cart per customer per journey, one restaurant
  per cart, one transaction per line.
- **The Flutter item detail screen**, its controller, and the components behind
  it: variant selector, modifier sections, quantity stepper, note field, sticky
  bar with the running total.
- **Six more composite foreign keys**, so a size cannot belong to another
  restaurant's dish and a cart line cannot claim "Spice level: Extra Cheese".
- **`cart.max_quantity_per_line` (20), `max_special_instructions` (300),
  `max_lines` (50), `ttl_seconds` (7 days)** in config — nothing compares
  against a literal.

### Changed

- The item detail response gained a `customization` block carrying sizes,
  groups, rules and **the server's own limits**, so the stepper and the note
  counter cannot drift from what the server accepts.
- `menu_items` gained `UNIQUE(id, restaurant_id)`, so variants can reference it
  compositely.
- `ApiClient.post` can carry an `Idempotency-Key`. It cannot overwrite
  `Authorization`, `Accept` or `Content-Type` — a caller cannot accidentally
  send a request unauthenticated.
- `MenuTestDataSeeder` gained sizes and questions, deliberately uneven.

### Removed

- **Module 10's read-only item sheet.** The configurable screen replaced it
  entirely; leaving a placeholder no route reaches is dead code the next reader
  has to work out is dead.

### Fixed

Four defects, none left open — see
[13-known-issues.md](13-known-issues.md). All four came from running the thing:

- **M11-B01/B02/B03 (Medium).** Three layout overflows at 320 dp — a group
  heading beside its rule, a field label beside "Optional", and a caveat beside
  a counter. All fitted at 390 dp, which is what the tests had been running at.
- **M11-B04 (Medium).** The disabled quantity button had no accessible name. A
  tooltip becomes a name only on an *enabled* control, so at quantity one a
  screen-reader user met an anonymous disabled thing at exactly the moment they
  needed to know what it was.

### Not done, and said plainly

- **Nothing can be ordered.** No cart screen, no editing a line, no promo codes,
  no taxes, no fees, no pickup time, no payment, no order. Module 12.
- **No cart cleanup runs.** `expires_at` is written and nothing deletes on it. A
  scheduled job that silently empties carts before the screen explaining it
  exists would ship the consequence without the explanation.
- **Add-ons are modifier groups.** There is no separate addon model, deliberately
  — one customization system rather than two doing the same job. Per-add-on
  quantities are the one thing that would justify a second model, and no real
  configuration here needs them.
- **A note is not an allergen control.** The caption says the kitchen will do
  what they can. When structured allergen data exists it will be a field with a
  schema, not a sentence somebody typed.
- **Android and iOS runtime verification are pending** — no Android SDK
  (KI-001), no macOS host (KI-002). Verification was against a release web build
  of the same Flutter code.
- **The suspended-versus-missing distinction is still inherited** from Module 09
  and still documented rather than silently changed.

---

## After Module 11: an on-device driver

Module 11's runtime rows (M11-050 Android, M11-051 iOS) are **PENDING** because
this environment has no Android SDK and no macOS host, and they stay PENDING.
What changed is what happens when a device does appear.

**Added.** `mobile/integration_test/module_11_add_to_cart_test.dart` — six tests
that build the shipping app, install it on a handset, tap the real controls and
check the row the server writes. `mobile/integration_test/support/` holds the
two things a device makes awkward: obtaining a session, and launching the app at
the screen under test. `mobile/tool/issue_token.dart` signs a persona in on the
host, because a handset cannot read the server's OTP log — and there is
deliberately no endpoint that would let it.

**Added.** `mobile/test_driver/integration_test.dart`, so the same target can be
run through `flutter drive` where a browser or device is available.

**Corrected.** An earlier entry here said that target "has been run green that
way, which proves the driver and the flow". **That was wrong.** `flutter drive`
on this machine exits 0 and reports "All tests passed." when the test body never
executes; two negative controls that had to fail both reported success. The
driver has **never been run**. KI-013 records the false pass and the rule taken
from it: a green result is worth nothing until a negative control has been seen
to fail.

**Changed.** `integration_test` added to `dev_dependencies`.

The setup guide gains the two commands and the three traps that otherwise cost
an afternoon: quote the token (it contains a `|`), give the device an address it
can actually reach, and match chromedriver's major version to the browser's.

---

## A 24-hour restaurant announced "Closing soon" every night

**Fixed.** `RestaurantAvailabilityService::closesWithin` asked whether the
window the restaurant is *in* ends within thirty minutes. That is not the same
question as whether the restaurant will be **shut** in thirty minutes, and for
the case this product exists for — a highway dhaba open around the clock — the
two answers differ. A restaurant open `00:00:00`–`23:59:59` every day read
`CLOSING_SOON` from 23:30 until midnight and then reopened one second later. A
driver reading that at 23:40 would have gone somewhere else for no reason.

It now returns false when any window still covers the moment thirty minutes
hence, so a window that hands straight over to another one is not closing.
Back-to-back sittings (09:00–14:00 then 14:00–23:00) get the same correction.

**Found by CI, on a commit that changed only documentation.** The Module 09 API
test asserting `OPEN` went red at 18:02 UTC — 23:32 in Asia/Kolkata, 27.8
minutes before the fixture's close. Every run earlier that day had passed. The
test fixture's own comment promised "a test never fails on the clock" and had
been wrong for half an hour a night since it was written.

**Tests.** Two added, both pinned to explicit instants: the exact moment that
turned CI red, and a pair of back-to-back windows. The genuine closing-soon case
— one window, nothing after it — still reads `CLOSING_SOON`, unchanged. Backend
suite 959 passed, 3980 assertions.

---

## Module 12 — cart management, price revalidation and the order summary

A customer could fill a cart and do nothing else with it. Now they can read it,
correct it, empty it, and see what it will cost — and reach it at all, which
Module 11 left them no way to do.

### Backend

Four endpoints, none nested under a restaurant, because a cart already knows
which kitchen it belongs to and naming a second one is a chance for the two to
disagree:

```
GET    /trips/{trip}/cart               lines, options, order summary
GET    /trips/{trip}/cart/revalidate    the same, plus whether it still holds
PATCH  /trips/{trip}/cart/items/{item}  quantity, 1..CART_MAX_QUANTITY_PER_LINE
DELETE /trips/{trip}/cart/items/{item}  remove a line
DELETE /trips/{trip}/cart               empty it
```

`GET /cart` is Module 11's badge endpoint extended, not replaced — every field
it carried is still in the same place, and a test says so by name.

**No request carries a price and no handler reads one.** A quantity change is
re-priced from live menu rows through `CartLineRepricer`, which turns the stored
line back into the selection that produced it and hands that to Module 11's
validator and pricing service unchanged. A dish that has gone up is refused with
`PRICE_UPDATED` and both figures; one that has gone down is applied.

**Quantity zero is refused, not read as removal.** Overloading nought as
deletion makes an off-by-one in a stepper destroy a customer's selection and
leaves the server unable to tell a mistake from an intention.

**`CLOSED` is written for the first time.** Removing the last line, emptying,
discarding the journey and resolving a conflict all close the cart rather than
deleting it: the rows are the history Module 13's orders will point at. An empty
`ACTIVE` cart would still occupy the one-active-cart-per-journey slot and block
every other journey — KI-014 by a different route.

**The order summary** is computed in one place, in integer minor units. Tax on
the subtotal once and rounded half up, not per line: twenty lines rounded
individually drift by paise the customer cannot account for. Rates are
configuration and data, and **every default is nought** — see below.

**Revalidation is a `GET` and writes nothing.** Per line it reports
`PRICE_INCREASED` / `PRICE_DECREASED` with both figures, or `ITEM_`, `VARIANT_`
or `MODIFIER_UNAVAILABLE`; per cart, whether the kitchen is still taking orders.
`totals_if_accepted` is null the moment a line cannot be priced, because a total
worked out around a missing dish describes a cart nobody has.

### Mobile

A cart screen, reachable from the app bar of every screen a dish can be added
from. Nothing on it is calculated on the device: every figure came from the
server in the response to the request that changed it.

Edits are not optimistic — the line being changed disables its own controls; the
rest of the cart stays usable. Every unsafe request carries an
`Idempotency-Key` kept across a retry.

One banner at most, ranked: a closed kitchen outranks a blocked line, which
outranks a price change. A blocked line is never removed for the customer.

Cart conflicts get the other half of Module 11's refusal: **two choices and no
third**. "Keep my cart" abandons the add; "Start a new cart" is confirmed with a
dialogue naming what will be lost. Two requests rather than a flag on the add —
a `replace_existing_cart` field would be a way to destroy a cart hidden inside a
request about a dish.

### Rates and fees default to nothing, deliberately

| Input | Where | Default |
| --- | --- | --- |
| Tax rate | `restaurants.tax_rate_bps`, falling back to `foodonthego.cart.tax_rate_bps` | **0** |
| Packaging fee | `restaurants.packaging_fee_minor` | **0** |
| Platform fee | `foodonthego.cart.platform_fee_minor` | **0** |

A plausible-looking 5% that nobody chose is worse than a visible zero: it reads
as correct, survives review because it is the figure everyone expects, and ships
as a real charge on a real customer. The mechanism is built and tested with
non-zero values in fixtures. **The business must set these before commercial
launch.**

`restaurants.tax_rate_bps` is nullable rather than zero-defaulted, because null
and zero mean different things: null is "unconfigured, use the platform
default", zero is "deliberately not taxed". Collapsing them would make an
unconfigured restaurant indistinguishable from a tax-exempt one.

### Two tests that had been green for the wrong reason

**A `<script>` in a customer's note reached the wire as markup.** Module 11
asserted it never could, and the assertion had never been exercised: the only
cart endpoint returned a badge with no free-form text in it. `ApiResponse` now
hex-escapes `<`, `>`, `&`, `'` and `"` in every body — lossless, and covering
every field of every endpoint rather than the ones somebody remembered.

**A cart-conflict fixture described no server**, putting the restaurant's name
in the refusal's message where the real server puts a generic sentence and the
name in `details`. The screen passed by echoing the message, so one that ignored
`details` entirely would have passed too.

### And three availability tests that assumed the clock

`TripRestaurantApiTest` went red on a Flutter-and-docs commit, expecting
`CLOSED` and getting `OPENING_SOON` — the service was right, the run simply
started 27 minutes before the fixture's opening. Two more shared the fixture and
were latent failures for a different hour. All three now pin the clock, and the
instant that broke the first is kept as coverage.

The second time this has happened. The first was `CLOSING_SOON`, where the
service *was* wrong. An availability assertion that does not pin the clock is a
scheduled failure.

---

## Module 13 — Pickup Time Selection, Arrival Window & Pre-Checkout Validation

### Added

**Backend**
- `carts.version`, `pickup_selection_status`, `requested_pickup_start_at`,
  `requested_pickup_end_at`, `pickup_timezone`, `pickup_selected_at`,
  `pickup_planning_fingerprint`; `restaurants.operational_buffer_minutes`
- `PickupSelectionStatus` (`NONE`, `SELECTED`, `STALE`, `INVALID`) — deliberately not order statuses
- `ArrivalEstimate`, `ArrivalEstimateProvider`, `PlannedRouteArrivalEstimateProvider` — the ETA boundary as a code seam
- `PreparationEstimate`, `PreparationEstimateService` — maximum of the lines, never the sum
- `PickupWindow`, `PickupWindowGenerator` — timezone-aware, overnight-aware, de-duplicating
- `PickupPlan`, `PickupPlanningService` — the one place the arithmetic lives
- `PlanningFingerprint` — cart version, route uuid and `calculated_at`, restaurant uuid, accepting-orders, status, hours, config version
- `PickupOptionStore`, `PickupOptionRecord`, `PickupOptionSelectionService` — opaque single-use ids, keyed per customer
- `PickupSelectionEvaluator` — derives `STALE` and `INVALID` rather than storing them
- `PreCheckoutIssue`, `PreCheckoutValidation`, `PreCheckoutValidationService`
- `PickupController`; `POST .../pickup-options`, `PUT .../pickup-selection`, `POST .../pre-checkout-validate`
- `PickupServiceProvider`
- `foodonthego.pickup` configuration block, every value an env override

**Mobile**
- `PickupSelectionStatus`, `PickupOption`, `PickupSelection`, `PickupPlan`, `PickupView`
- `PreCheckoutIssueCode`, `PreCheckoutIssue`, `PreCheckoutResult`
- `PickupRepository`, `ApiPickupRepository`; `ApiClient.put`
- `PickupController` / `PickupState`, `pickupControllerProvider`
- `PickupTimeScreen`, `PickupTimeChip`, `PickupExplanationCard`
- `Routes.tripPickup`, and the way in from the cart
- Ten pickup error codes on `ApiErrorCode`

**Tests**
- `PickupWindowGeneratorTest` (9), `PickupPlanningServiceTest` (22)
- `PickupTimeApiTest` (18), `PreCheckoutValidationApiTest` (14)
- `pickup_models_test.dart` (14), `pickup_time_screen_test.dart` (22)
- `integration_test/module_13_pickup_test.dart` (7, on device)
- `CartFixtures`, `FakePickupRepository`

### Changed

- `carts.version` now increments atomically on every **contents** change, and
  deliberately not on a price change
- `Cart::touchActivity()` became `Cart::recordContentChange()` — one name for
  what it actually does
- `PickupController::selectionArray` expresses the stored instants on the
  restaurant's clock, matching the options beside them

### Removed

Three error codes, each before anything raised it:

- `PREPARATION_DATA_UNAVAILABLE` — preparation always falls through to a
  platform default, so it could never honestly be returned
- `PICKUP_OPTION_NOT_FOUND` — expired, forged and stolen must not be
  distinguishable
- `CART_VERSION_CONFLICT` — the cart's version is one of the facts the planning
  fingerprint covers, so that condition already comes back as
  `PICKUP_OPTION_STALE`

A code the API documents and never returns is a promise nothing keeps.

### Still outstanding for the business

**The tax rate and both fees remain nought.** Unchanged from Module 12, and
still a business input rather than a code decision. They must be set before
commercial launch.

## Module 14 — Checkout, Final Order Review, Commercial Calculation & Payment Readiness

### Added

**Backend**
- `checkout_quotes` migration — integer minor units, `*_configured` companions,
  `ACTIVE`/`STALE`/`EXPIRED`/`CONSUMED`, composite FK tying a quote to one
  customer's cart
- migration making `restaurants.packaging_fee_minor` nullable, so "not
  configured" is expressible
- `CommercialCalculationService` — wraps Module 12's totals, duplicates no
  arithmetic, reports configured-ness per component
- `CommercialBreakdown` — only configured components reach the wire
- `CheckoutFingerprint`, `CheckoutQuote`, `CheckoutPreparationService`
- `CheckoutController` — `prepare` and `validate`; no money read from any request
- `config('foodonthego.checkout')` — TTL, rule version, quotes per cart
- `CommercialCalculationServiceTest` (14), `CheckoutApiTest` (23)

**Mobile**
- `domain/models/checkout.dart`, `domain/repositories/checkout_repository.dart`,
  `data/repositories/api_checkout_repository.dart` — no parameter takes an
  amount, and the requests carry no body
- `shared/state/checkout_controller.dart`
- `features/checkout/checkout_screen.dart` and `widgets/commercial_summary_card.dart`
- route `\/trips\/:tripId\/cart\/pickup\/checkout`, reached from Module 13's
  **Continue to checkout**
- `checkout_models_test.dart` (21), `checkout_controller_test.dart` (17),
  `checkout_screen_test.dart` (30), `module_14_checkout_test.dart` (5, on device)

**CI**
- `review-build` job — release APK and app bundle with a `BUILD-INFO.txt`
  recording version, branch head commit, run URL, toolchain, API address and
  SHA-256; uploaded as an artefact

**Docs**
- `29-checkout-and-payment-readiness.md`, `30-client-review-package.md`
- twelve screenshots in `evidence/module-14/`

### Fixed

- **Every instant but two went out on the wrong clock** (M14-B01). Module 13's
  rule is now an invariant over the whole response body in both the pickup and
  checkout APIs, pinned by tests that name no fields.
- **"Change pickup time" was painted as "Change pick…"** on a 393dp phone
  (M14-B02). Found by looking at a screenshot; the widget test for that row was
  green, because an ellipsis does not change what `find.text` matches.
- **`packaging_fee_minor` made every restaurant read as configured** (M14-B04).

### Changed

- `PickupPlan::toApiArray`, `ArrivalEstimate::toApiArray` and
  `Cart::toCustomerArray` render instants on the restaurant's clock
- `wallClockOf` promoted out of `PickupOption` — every instant a customer reads
  needs it, and Module 14's quote expiry is the second caller
- the checkout's edit controls are stacked rather than side by side

### Not done, deliberately

No payment, no order, no Razorpay object, no reservation of inventory, and no
commercial rule invented. All are named in
[30-client-review-package.md](30-client-review-package.md).

## Module 14T — Multi-Tenancy, Tenant Assignment & Cross-Tenant Isolation

Inserted between Modules 14 and 15 at the client's direction.

### Added

**Backend**
- `App\Enums\TenantRole` — capability inside one restaurant, ordered owner ⊇
  manager ⊇ staff, deliberately separate from `Role`
- `restaurant_user` migration — one assignment per person per restaurant, unique
  in the database, revoked by status rather than deleted
- `platform_tenant_grants` migration — a super administrator's breadth as a row;
  with none, nothing
- `RestaurantMembership`, `PlatformTenantGrant` models
- `App\Services\Tenancy\TenantAccessService` — the only implementation of
  reachability; default deny, surface and assignment both checked, scoping done
  in the query
- `App\Policies\RestaurantPolicy` — view/update/manageMenu/manageStaff/
  viewFinancials, and **no `before()` hook**
- `App\Models\Concerns\BelongsToTenant` — closes the indirect path
- `Restaurant::scopeReachableBy`, `Restaurant::memberships`,
  `User::restaurantMemberships`, `User::platformTenantGrants`
- Guarded routes: `/restaurant/restaurants`, `/restaurant/restaurants/{id}`
  (read and PATCH), `/restaurant/restaurants/{id}/menu/items`,
  `/restaurant/menu/items/{item}`, `/admin/restaurants`
- `TenantIsolationTest` — 22 cross-tenant tests over HTTP; `TenancyFixtures`

**Docs**
- `33-multi-tenancy-and-tenant-isolation.md`; `07-security.md` gains the
  constraint and its current state

### Fixed

- **`accountUsable()` denied every account that had not round-tripped.** It read
  `is_active === true`; the column defaults to true, so a freshly created model
  held NULL and was read as disabled. That made every "reaches nothing"
  assertion pass whether the boundary worked or not — the one bug a tenancy
  suite must never have. Only an explicit `false` denies now.

### Changed

- `MenuItem` and `MenuCategory` use `BelongsToTenant`

### Not done, deliberately

No login for the six operator roles, no staff-management endpoints, and no
tenant scoping for orders, payments or settlements — none of which exist yet.

## Module 15 — orders, payment, webhooks and reconciliation

A quote becomes an order; an order gets paid for. Nothing a client says about
money is believed at any point.

**No Razorpay credentials exist and none were invented.** The gateway that ships
is the one that refuses; staging and production decline to boot without keys.

### Added

- `orders`, `order_items`, `order_item_modifiers`, `payments`, `payment_events`.
- `PaymentGateway` with a Razorpay adapter, an unconfigured default and a
  deterministic double under `tests/`.
- `RazorpaySignature`, deliberately outside the gateway interface.
- `PaymentService`, `WebhookService`, `ReconciliationService`,
  `OrderPlacementService`, and `payments:reconcile`.
- Customer order and payment endpoints, tenant-scoped operator order endpoints,
  and the public webhook endpoint.
- Flutter: `PlacedOrder`, `PaymentIntent`, `OrderRepository`, `OrderController`,
  the payment screen, and a payment handoff seam bound to the implementation
  that reports it cannot open a checkout.

### Changed

- The checkout screen's Proceed button now validates and then goes to payment.
- Three older tests asserting that no orders table exists now assert that no row
  was written — the guarantee they were protecting, kept.
- The Module 14 device test moved with the boundary: one order, awaiting
  payment, `paid_at` null.

### Fixed

- A navigation guard that sent a customer to payment on a validation the server
  had refused, because the controller keeps the last good quote in state and the
  readiness flags still read true. Caught by a test.

## Module 16 — order creation, confirmation, order number and secure pickup code

**One captured payment produces at most one order**, and the thing that
guarantees it is a unique index rather than any check in application code.

This module deviates from its specification's table layout, deliberately and in
writing: rather than adding a `payment_intents` table and rewriting four
modules of tested payment code, the `orders` table now holds two kinds of row —
a payment target before capture, an order after. The migration is named
`place_orders_only_on_captured_payment` so the deviation is visible in the
migration list.

### Added

- `PickupCredentialService` — pickup code and QR token derived by HMAC from the
  order uuid, the restaurant id and a credential version, with only keyed
  digests stored. No plaintext credential is written anywhere.
- `OrderNumberGenerator` — `FOTG-YYMMDD-XXXXXXXXXX` from `random_int`, over an
  alphabet without I, L, O or U, with the unique index as the guarantee and a
  retry for the collision that will not happen.
- `CreateOrderFromCapturedPayment` — the single idempotent creation path, shared
  by the client callback, the webhook and the recovery sweep.
- `OrderStateMachine`, `OrderCreationState`, `OrderRecoveryService`.
- `outbox_events`, written inside the creation transaction, payloads carrying
  identifiers only.
- `orders:recover-captured`, `orders:check-integrity`, `outbox:publish`, all
  scheduled.
- `GET /customer/orders/{order}/status` and
  `GET /customer/orders/{order}/pickup-credential`, the latter answering
  `no-store, private, max-age=0`.
- Party and address snapshots on `orders`.
- Flutter: `PickupCredential`, `OrderStatusReport`,
  `OrderConfirmationController`, and the confirmation screen.

### Changed

- `OrderStatus` rewritten. `AWAITING_PAYMENT` is documented as *not an order* —
  a payment target. `Placed` replaces `Paid`; `Order::isPaid()` became
  `Order::isPlaced()`.
- `OrderPlacementService` no longer writes `order_number` or `placed_at` at
  checkout; `paid_at` now comes from `payments.verified_at`.
- The customer Orders list is `whereNotNull('placed_at')`, so a payment target
  never appears in it.
- `orders.order_number` widened to `varchar(24)` rather than the suffix being
  shortened — the column was the wrong thing to spend entropy on.
- The Orders tab header rows became `Wrap` with a `Flexible` status.
- `PlacedOrder.orderNumber` is now nullable.

### Fixed

- **A `FormatException` on the payment screen for every customer.**
  `PlacedOrder.orderNumber` was non-nullable, and the API returns null before
  placement. Every widget test passed, because the fake repository always
  supplied a number. Found by reading the code, not by running it.
- **Two different pickup credentials for one order.**
  `pickup_credential_version` has a database default of 1, but Eloquent does not
  read defaults back after an insert, so an un-reloaded model held NULL and
  `(int) null` is a perfectly usable HMAC input. Now
  `PickupCredentialVersionMissing`. Second time this pattern has shipped a bug
  here; Module 14T's `accountUsable` was the first.
- **`customer_phone_snapshot` written as NULL.** The code read `users.phone`, a
  legacy column that is not populated; the real one is `phone_e164`. Caught by
  a guard asserting the fixture was non-empty *before* the snapshot assertion.
- **A QR-payload test that could pass vacuously.** It matched a substring, which
  an empty field also satisfies; rewritten as equality against `prefix + token`.
- **A 44px overflow in the Orders tab** at 320px width with 2× text, in two
  separate rows.
- **`pickup_token_expires_at` missing its datetime cast**, which made
  `toIso8601String()` fatal.

### Recorded, not fixed

- KI-024 — no attempt limit on a pickup code, because there is no redemption
  endpoint to limit yet.
- KI-025 — `payments:reconcile` is not scheduled. Module 15's operational
  behaviour; noticed here, deliberately not changed here.
- KI-026 — the captured-payment path has never run against live Razorpay.
- KI-027 — an order cannot move past `PLACED`, and the state machine's empty
  arrays say so honestly.

## Module 17 — customer order tracking, status timeline and order state presentation

**An order's status stopped being a value and became a history**, and the
customer app got a screen that reads it without ever deciding it.

### Added

- `order_status_history` — append-only, unique on `(order_id, to_status)`,
  carrying from/to, source category, actor, internal reason code, a separate
  customer-safe note, correlation id, and `occurred_at` kept apart from
  `created_at`.
- Milestone timestamps `accepted_at`, `rejected_at`, `cooking_started_at`,
  `ready_at`, `picked_up_at`; `order_version`; `customer_safe_reason`.
- `OrderTransitionService` — lock, re-read under the lock, early return on a
  duplicate, edge validation, tenant check, milestone, version bump, history
  append, outbox event, commit.
- `OrderTransitionActor` with named factories only, so a source cannot arrive
  from a request body.
- `OrderTimelineService`, `OrderStatusCopy`, `OrderTimelineStepState`,
  `OrderTransitionSource`.
- Domain events `OrderAccepted`, `OrderRejected`, `OrderCookingStarted`,
  `OrderReady`, `OrderPickedUp`, `OrderCancelled`, on Module 16's outbox.
- `dev:order-transition` — console only, refuses outside local and testing,
  records `TEST_HARNESS`.
- Flutter: `TrackedOrder`, `OrderTimelineStep`, `OrderTrackingController`,
  `OrderTimelineView`, `OrderTrackingScreen`, `TrackingConfig`, and the
  `/orders/:orderId/track` route.

### Changed

- `OrderStateMachine` gained the fulfilment edges by extending its existing
  table. Cancellation is permitted from `PLACED` and `ACCEPTED` only.
- `GET /customer/orders` now returns `active` and `past` alongside the original
  flat `orders`, which is kept so an older review build does not start showing
  an empty list.
- `GET /customer/orders/{order}` is the tracking response: timeline,
  `order_version`, `status_updated_at`, `is_active`, `server_time`,
  `customer_safe_reason`, and `pickup_credential.available`.
- Order placement now writes the first history row.
- `PlacedOrder` carries `statusTitle`/`statusSubtitle`; `statusLabel` prefers
  the server's wording and falls back to the local label.
- `OrderPresenter::zone()` and `local()` are public, so one clock rule serves
  every producer of instants in an order response.
- The Orders tab card gained a *Track order* button.

### Fixed

- **Three new fields shipped on the wrong clock.** The timeline, the credential
  expiry and `server_time` were UTC while every other instant in the response
  was on the restaurant's clock. Caught by Module 13's "every instant in one
  order response is on one clock" invariant.
- **The status hero and the timeline disagreed.** One rendered the client's
  label, the other the server's, so a screen could show "Being prepared" above
  "Your food is being prepared".
- **An ordering test that could not fail.** Active orders sorted by soonest
  pickup, but the test created them so that id order and pickup order agreed —
  every plausible sort passed it.
- **A history assertion that proved its own fixture.** "Placement writes the
  first history entry" ran against a helper that wrote the row itself.
- **A negative-control harness that inserted code at position 0** when reverting
  a control whose mutation was an empty string, silently breaking eight
  subsequent controls. See 09-testing-strategy.md.
- **The tracking call unwrapped the response envelope twice**, so every request
  against a real server threw and the screen honestly said it could not load
  the order. Found on a device, because all 962 widget tests then in the suite drive a fake
  repository and the code that turns an HTTP body into a model had never once
  run. `mobile/test/order_repository_wire_test.dart` is the missing layer.
- **A restaurant seeded "open all week" was shut for one second every night**
  (KI-033). `alwaysOpen` wrote `00:00:00 – 23:59:59`, and `covers()` asks
  `$time < closes_at`, so a device job that ran through 23:59:59 IST had a
  checkout refused `RESTAURANT_NOT_ACCEPTING_ORDERS` — correctly. Both the
  seeder and the test fixture now write an overnight `00:00:00 – 00:00:00`,
  which is what "open twenty-four hours" already means in this schema.
- **The device CI backend answered one request at a time** (KI-032).
  `scripts/ci-backend-up.sh` ran `php artisan serve` with its default single
  worker, so the nine requests an app fires when a screen opens cold queued
  behind each other until one passed the client's ten-second timeout. It now
  runs eight workers, and warns loudly if Laravel ever declines them.

### Recorded, not fixed

- KI-028 — no restaurant UI, so in production every order would sit at PLACED.
- KI-029 — concurrency is tested sequentially with stale models, not under true
  parallelism.
- KI-030 — no cancellation policy, so no cancel button.
- KI-031 — **now fixed**, after the module closed: the screen says how old the
  read is, and past the polling budget it stops showing a status at all rather
  than presenting a day-old "Your food is being prepared" as the answer. What
  does not go stale — the pickup window, the restaurant, the items, the amount
  paid — stays on screen.
- KI-032 — recorded as FIXED, because the diagnosis is worth more than the
  one-line change: the failure looked platform-specific and looked like a flake,
  and was neither.
- KI-033 — likewise, and it is the second time the same fixture has failed on
  the clock for the same reason. `23:59:59` was standing in for midnight.
- KI-035 — **new, and recorded rather than fixed.** A real customer's home
  screen shows no journey and no active order, and the code comment explaining
  why names a module that shipped. Both APIs now exist; what does not exist is
  a decision about which order, which journey, and whether the card may show a
  countdown before Module 18 builds an ETA.
- KI-020 — **re-measured, not fixed.** The iOS stall has not recurred in six
  completed runs, all of which printed their tests. Left OPEN because nothing
  was diagnosed, only bounded — and with the number that matters recorded: the
  slowest completed step used 79% of its 30-minute budget, so a slower runner
  would produce this issue's exact signature while being nothing but slow.
- KI-021 — **now fixed**. The speculative Module 02 `OrderStatus` is deleted;
  Module 17 specified the fulfilment workflow that entry was waiting for, so
  `PlacedOrderStatus` is now the app's only order vocabulary. A latent bug came
  out with it: the progress track named `cancelled` as the one way off the path
  and would have drawn a rejected order with four steps still to come.
- KI-034 — **new and fixed**. A test slept 20 ms instead of waiting for a
  condition, and failed once under load. Not a flake — a race, with a control
  that proves the replacement still catches a broken retry.
- KI-025 — **now fixed**, on its own rather than under cover of another
  module's work: `payments:reconcile` is scheduled every fifteen minutes, the
  interval derived from the grace period the command already insists on. The
  schedule now has a test, because it had none — a deleted `Schedule::command`
  line was invisible to the whole suite, which is why this one went unnoticed
  through two modules.
- KI-008 — **mostly fixed**, and found by an adversarial security pass over the
  branch rather than by anything routine. A suspended account kept working for
  up to 30 days, because nothing re-checked its standing once a token existed.
  `EnsureRole` now refuses on every authenticated request, on every surface.

  Two things are worth more than the fix. First, **the entry had gone stale in
  the direction that matters**: it was recorded when the customer surface
  returned a profile, and it described "`/customer/me`". One middleware group
  covers the whole customer surface, so by Module 16 the same gap meant a
  suspended customer could place an order and pay for it — and nothing prompts
  a known issue to be re-read when the surface it describes grows underneath
  it. Second, **the cost it was waiting on did not exist**: measured at two
  queries with the check and two without, because Sanctum has already loaded
  the user row to resolve the token. The decision the entry deferred was a
  decision about nothing.

  The tenancy suite made the same point from the other side. Two tests there
  asserted a 404 for a suspended operator and now get a 403 from the earlier
  gate; accepting the new code and moving on would have left both green with
  `TenantAccessService::accountUsable()` deleted, because the request no longer
  reaches it. They now assert both layers, and a mutation confirms the inner
  one still fails when broken.
- KI-003 — **now fixed**, sixteen modules after it was recorded, and the entry
  was wrong about why it was blocked. It blamed the network egress policy;
  the proxy reported no failures at all, and the 403 came from this
  development session's repository scoping — a restriction CI has never had,
  which is where the analysis needed to run in the first place. **The entry
  blamed the component that reports failures rather than the one causing
  them**, and nobody re-read it for sixteen modules. Second time in two days
  a stale known-issue entry has turned out to be the actual obstacle.

  PHPStan 2.2.13 + Larastan 3.12.0 now gate the backend CI job at level 3,
  clean. The measured ladder to KI-003's stated level 6 is 45 / 50 / 133
  errors at levels 4 / 5 / 6 — written down rather than baselined, because a
  baseline records "already broken" and then never runs out.

  It found four defects in code 1,301 tests had passed over, the largest
  being that **the API request log had never recorded an actor at all**:
  `LogApiRequests` is prepended to the `api` group while `auth:sanctum` is
  applied per route, so `$request->user()` fell through to the default `web`
  session guard and returned null on every stateless request. `setActor()`
  was never called once. A dead `is_string()` test on a backed enum was what
  static analysis actually flagged; the dead branch turned out to live inside
  a block that was itself dead.

  All four are invisible to a test suite by construction rather than by
  oversight — a test exercises code that runs, and none of this ran. More
  tests would never have found them.

  The adoption also repeated this project's most-learned lesson in a new
  costume: the first config change moved the error count from 434 to exactly
  434. The schema was only half of what the analyser was missing.
- KI-029 — **now fixed**, and it closed the way the entry asked: "a test harness
  that can run parallel PHP processes against one database". Eight separate PHP
  processes, one order, one start instant, each spinning until that instant so
  what races is the transition rather than PHP's startup.

  The control is the point and it is asserted rather than assumed: every race
  also runs through a deliberately naive read-decide-write, which **must**
  corrupt the order — because processes that fail to overlap pass every
  assertion in the safe run. It corrupts it thoroughly. All eight read PLACED
  before any wrote, so all eight updated the row and `order_version` reached 8
  instead of 2; seven were stopped only by the unique index on
  `(order_id, to_status)`.

  **That is the finding: the unique index protects the history, and nothing but
  the row lock protects the order.** A design leaning on the index alone would
  have produced an order written eight times, under a timeline that looked
  perfectly coherent.

  The cost was instructive too. This test must commit, so it cannot use the
  transaction every other test rolls back — and `DatabaseTruncation` only cleans
  up *before* each test that uses it. The first full run produced 132 failures
  from a committed fixture that outlived its test. The test worked and broke the
  suite around it; it now empties the tables on the way out.
- **The iOS build job now retries, and only the part that touches the network.**
  `flutter build ios` runs `pod install`, which fetches the CocoaPods spec repo;
  on 2026-09-10 it failed with `Could not resolve host: cdn.cocoapods.org` on a
  commit that changed two markdown files and nothing else, minutes after the
  identical build passed. DNS on the runner, not the app.

  Re-running the job was not available — the API answered 403 — so the step was
  made robust instead of the failure being waited out. Three bounded attempts,
  each announcing itself in the log.

  **It cannot hide a broken build**, and that was tested rather than asserted: a
  command that always fails still fails all three attempts and exits 1; one that
  fails twice then succeeds passes; one that succeeds first time runs once. A
  compile error is deterministic and a retry does nothing for it.

  The iOS *simulator* job runs `pod install` too and shares the exposure. It is
  deliberately left alone: it did not fail, and widening a fix past the thing
  that broke is how a small change becomes an unreviewable one.
- **Level 4 static analysis was examined and declined, which is the finding.**
  KI-003 left "raise it to 6" as the follow-up and assumed the cost was writing
  the missing annotations. Working level 4 showed that assumption to be wrong in
  a way that would have done damage.

  35 of its 45 findings rest on Larastan taking an Eloquent attribute's type
  from the migration. `carts.status` is NOT NULL, so `$this->status?->value`
  reads as an unnecessary nullsafe — but an Eloquent attribute is *absent*, not
  defaulted, until something loads it. `new Cart` has `status` NULL, and
  `->value` on it raises *Attempt to read property "value" on null*. Taking that
  advice inside `Cart::toCustomerArray()`, an API serialiser, is a 500.

  Proved rather than argued: the probe and its output are in
  `docs/evidence/module-17/ki-003-why-not-level-4.txt`.

  The codebase already knew — `PickupCredentialService::version()` guards exactly
  this and is covered by a test named after the bug it prevents. Level 4 asks
  twice for that guard's deletion.

  So the gate stays at 3, and the reason is written down where the next person
  to see "0 errors at level 3" and reach for a bigger number will find it.
- **KI-001, KI-002 and KI-004 were re-read and found stale — all three understated
  what had been verified.** This is the same failure as KI-008 and KI-003 earlier,
  pointing the other way.

  KI-001 declared *ANDROID BUILD = PENDING. ANDROID DEVICE TEST = PENDING* and, in
  its own words, *"It has never been executed."* CI builds the review APK and AAB,
  downloads that artefact, installs it on a Pixel 6 / API 34 emulator and runs 29
  integration tests against a real Laravel server. It cited 19 widget tests; there
  are 986.

  KI-002 declared *IOS BUILD = PENDING. IOS DEVICE TEST = PENDING*, and its own
  "to clear" asked for exactly what CI already does — `flutter build ios
  --no-codesign` on a macOS runner, then the simulator, 29 tests green.

  KI-004 said *"this repository has had no CI execution yet"*. It was closed by the
  first CI run at Module 01 and stayed open here for sixteen modules.

  What is genuinely left is narrower and now stated as such: the **development
  container** cannot build either platform locally (no SDK, no `/dev/kvm`, no
  macOS), no **physical handset** has run the app on either platform, the iOS
  **simulator matrix** is one device rather than three, and there is still no
  signed IPA.

  Both entries described a *development container* while stating their verdict
  about the *product*. Then CI grew the capability and nothing prompted a re-read,
  because nothing ever does. Four stale entries in two days is enough to state the
  rule outright: **a known issue records the system as it was on the day it was
  written, and both its severity and its verdict decay.** Entries that name an
  environment decay fastest, because environments change without anyone revisiting
  the prose.
- **The traceability matrix carried the same stale verdict, 37 times.** Android and
  iOS rows across Modules 02–06 read `⛔ BLOCKED — environment unavailable`, citing
  KI-001 and KI-002. This is the document the pull request calls the fastest way
  into the project.

  The correction is more interesting than a status flip. Those rows are **right that
  the requirements are unverified on a handset and wrong about why**. The on-device
  suite covers Modules 11–14 plus the Module 16 confirmation and Module 17 tracking
  screens; it does not exercise the navigation shell, OTP sign-in, profile, the trip
  planner or the map layer. So the blocker changed from *"there is no environment"*
  to *"no device test has been written for this module"* — which changes what
  somebody would do about it: write the tests, rather than wait for a runner that
  has existed for modules.

  A banner at the top of the document says so. The 37 rows are deliberately **not**
  rewritten in bulk: they carry about twenty different phrasings, and a botched
  sweep through a traceability matrix would be worse than the staleness it fixed.

  One thing the first draft of that banner got wrong, caught on re-reading it: it
  said the "environment unavailable" reasons *below* were stale, full stop. The
  live-provider rows — Places, the Maps SDK render, the Routes API — say the same
  words and are **genuinely** environment-limited, because no API keys exist for
  this project and none were invented. The banner now names them as excluded. A
  correction that over-reaches is just a new inaccuracy.
- **The shell device test ran, and the count is how we know.** Its first CI run took
  the iOS simulator from 29 tests to **31** — the number is the evidence that the
  new file executed rather than being silently collected and skipped, which a green
  suite alone would not have distinguished.

  M02-017 and M02-018 are verified on device as a result: the five destinations
  render and each is reachable by tapping, on a real simulator and emulator.

  **One thing deliberately not claimed.** The Android job passed the identical
  `flutter test integration_test/` invocation, but its log tail kept landing past
  the test summary and the count was never actually read. It is recorded as green
  on the same suite rather than as "31 per platform". Assuming symmetry would have
  been reasonable and would still have been a number nobody checked.
- **A customer-reachable navigation defect, found because a device test failed.**
  The Module 04 device test deep-linked to `/profile/edit` and timed out on a form
  that never appeared; the screen underneath said `GoException: no routes for
  location: /profile/edit`. The harness was wrong — the profile sub-screens are
  pushed over the Profile branch with a plain `Navigator` push and have no
  registered paths — but the same wrong assumption was **shipped in production
  code**: the trip planner's location picker offers a *"Manage saved addresses"*
  link that pushed `/profile/addresses` and landed the customer on **Page Not
  Found**, with the journey they were part-way through planning behind it.

  Nothing caught it. No test touched that link, so the reproduction was written
  first and watched fail for the right reason — `Found 1 widget with text "Page
  Not Found"` — before anything was changed. It also asserts that **back returns
  to the planner**: `SavedAddressesScreen`'s back button asks GoRouter whether
  anything can be popped and falls back to `go('/profile')` when the answer is no,
  so pushing onto the wrong navigator would have silently moved the customer to
  the profile tab. That assertion passes, which is how the navigator choice is
  known to be right rather than assumed.

  `Routes.profileEditPath`, `savedAddressesPath` and `addressFormPath` are deleted
  along with the three relative names beside them. All six were unused once the
  link was fixed, and **none was ever registered with the router**. They read
  exactly like routes that exist, and twice they were used as if they did — once
  in shipped code, once in a test written sixteen modules later by someone reading
  the same file. A constant naming a path nobody registered is not documentation;
  it is a trap with a doc comment on it.

  The device test now opens the editor the way a customer does, by tapping
  *"Personal information"*. Its saved-addresses sibling was re-examined in the same
  pass and turned out to be **passing for no reason**: it asserted `find.text('Saved
  addresses')`, and the profile row behind the pushed route carries those exact
  words, so it would have passed whether or not anything opened. It now asserts the
  screen by widget type.

  **A guard came out of it**, because the interesting question was not "what
  broke" but "why could nothing have caught it". Nothing in the suite had ever
  asked the router whether it knew a path before something navigated to one.
  `mobile/test/routes_are_registered_test.dart` now does, in two checks: a named
  list of every path `Routes` can build, and a scan of `routes.dart` itself so a
  constant added next year is checked without anyone choosing to check it. It
  tests matching, not screens — no widget is built, no repository is called — so
  a path stays covered whether or not its screen can be pumped in a harness.

  Its controls include the one that actually settles the question: a bogus
  constant was added to the real `routes.dart`, the suite re-run, and the scan
  named it — `Actual: ['/profile/addresses']` — before the constant was
  reverted. An in-test fixture would have proved the regex worked; only this
  proves the scan reads the file it claims to read. Flutter: **1,016 passing**.
