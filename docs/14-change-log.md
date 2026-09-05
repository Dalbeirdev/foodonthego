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
