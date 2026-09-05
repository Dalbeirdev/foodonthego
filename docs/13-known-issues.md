# 13 — Known issues

## Open — environment blockers

### KI-001 · Android build cannot be validated

**Severity:** High (blocks a Module 01 acceptance item)

`flutter build apk` requires the Android SDK, downloaded from `dl.google.com`. In the build
environment used for Module 01 that host is denied by the network egress policy:

```
curl: (56) CONNECT tunnel failed, response 403
proxy: dl.google.com:443 | gateway answered 403 to CONNECT (policy denial)
```

`flutter doctor` accordingly reports `✗ Android toolchain — Unable to locate Android SDK`.

**What was verified instead:** `flutter analyze` (clean), 19 widget tests, and the real widget tree
rendered and screenshotted at four phone sizes plus dark mode.

**ANDROID BUILD = PENDING. ANDROID DEVICE TEST = PENDING.** Not claimed as passed.

**To clear:** allow `dl.google.com` for the CI runner, install `cmdline-tools`, accept licences, run
`flutter build apk --debug`, then run the widget tests on an emulator.

---

### KI-002 · iOS build and device test cannot be performed

**Severity:** High (blocks a Module 01 acceptance item)

Building or simulating iOS requires macOS with Xcode. The environment is Linux; `xcodebuild` does
not exist and cannot.

**IOS BUILD = PENDING. IOS DEVICE TEST = PENDING.** Not claimed as passed.

Safe-area handling, Dynamic Island clearance, keyboard behaviour, bottom-sheet layout, navigation
gestures and orientation are **unverified on iOS**. The code uses `SafeArea` rather than hard-coded
insets, and the platform font resolves to San Francisco, but that is design intent, not evidence.

**To clear:** run on a macOS runner — `flutter build ios --no-codesign`, then the simulator matrix
(iPhone SE, a standard iPhone, a Pro Max).

---

### KI-003 · No PHP static analysis

**Severity:** Medium

PHPStan/Larastan could not be installed: Composer resolves dist archives to GitHub zipball URLs, and
the environment's egress policy rejects them with *"Could not authenticate against github.com"*.
Packagist metadata itself is reachable — only the archive download fails.

**Mitigation in place:** Laravel Pint runs in CI (style, `declare(strict_types=1)`, import order),
all code is written with explicit types, and 67 tests cover behaviour.

**To clear:** allow GitHub archive downloads, or vendor PHPStan into an internal mirror, then add
`vendor/bin/phpstan analyse` at level 6 to CI.

---

### KI-004 · CI mobile jobs are unexercised

**Severity:** Medium

`.github/workflows/ci.yml` defines the Flutter analyze/test job and an Android build job, but they
have never run — this repository has had no CI execution yet, and the Android job will fail until
KI-001 is cleared. The iOS job is written but gated behind a macOS runner.

**To clear:** first push to GitHub; fix whatever the first run surfaces.

---

### KI-010 · Live Google Places verification cannot be performed

**Severity:** Medium

This environment has no Google Places credentials, and `places.googleapis.com`
answers 403 without a key. OpenStreetMap's Nominatim, the obvious substitute, is
blocked by the egress policy entirely.

So `GooglePlacesProvider` is verified against a **stubbed HTTP transport**
(`PlaceProviderTest`, 18 assertions): what is established is that the adapter
sends the right request — key and field mask in headers, session token and region
bias in the body — and reads the documented response shapes. Whether Google's
live responses match those shapes is not established here.

Development and automated verification run against `DevelopmentGazetteerProvider`
— a dozen real places with their real published coordinates and `dev:`-namespaced
ids, which refuses to be constructed in production.

**This is reported as PENDING, not as PASS.** See M05-037.

**To clear:** configure `GOOGLE_PLACES_API_KEY` with the restrictions documented
in [20-trip-planner.md](20-trip-planner.md) and re-run the integration script
with `PLACES_PROVIDER=google`.

### KI-011 · Live map SDK render cannot be performed

**Severity:** Medium

Drawing a real map needs a Maps SDK key and a device or emulator. This
environment has neither: no key is configured, `dl.google.com` is blocked so
there is no Android SDK (KI-001), and there is no macOS host (KI-002). The web
harness used for live verification deliberately carries no Maps key either —
putting one in a page served from a static directory would publish it.

So every live screenshot in `docs/evidence/module-06/` shows the documented
**map-unavailable** state, which is a designed state in its own right and not a
failure: the two place names, the distance, the travel time and the age of the
calculation are all present. What is *not* established here is that tiles load,
that the camera frames the route, that the markers land in the right places, and
that a tap on an alternative polyline selects it.

**This is reported as PENDING, not as PASS.** See M06-053 and M07-057.

Module 07 inherits it: the discovery map, its restaurant markers, marker
selection and the camera behaviour are all unverified against real tiles, and
every discovery screenshot shows the map-unavailable state — which still names
both ends of the journey and how many stops were found.

**To clear:** build with `--dart-define=FOTG_MAPS_API_KEY=…` on an Android
emulator or an iOS simulator and re-run the route screen.

---

### KI-012 · Live routing provider verification cannot be performed

**Severity:** High

No Google Routes API key is configured here, and `routes.googleapis.com` refuses
without one. Every alternative that could have stood in — OSRM, Valhalla,
OpenRouteService, Mapbox, GraphHopper, TomTom — is refused by this environment's
egress policy.

`GoogleRouteProvider` is therefore verified against a **stubbed HTTP transport**
(`RouteProviderTest`, 28 assertions): what is established is that the adapter
sends the right request — key in the `X-Goog-Api-Key` header, the six-field mask,
travel mode, traffic preference, alternatives flag — and reads the documented
response shapes, including the `staticDuration`/`duration` traffic mapping and
the `"16200s"` duration format. Whether Google's live responses match those
shapes is not established here.

Local work and automated verification run against `DevelopmentRouteProvider`,
which draws a straight line between the two points. It **refuses to be
constructed in production**, labels itself `development` in the stored row, in
the API response and in a banner on the screen, and never invents a traffic
figure or a second route. It is a stand-in, not a fallback: it is never selected
automatically, and no code path falls back to it when a real provider fails.

The consequence is worth stating plainly: **this module's Definition of Done
asks for a real route result from a real provider, and that cannot be satisfied
in this environment.** Everything around it — persistence, validation,
invalidation, selection, ownership, cost control, the screen — is verified; the
one live call is not.

**This is reported as PENDING, not as PASS.** See M06-051 and M07-055.

Module 07 inherits it in a specific and worth-stating way. Its *detour* figures
are differences between two provider answers, so with a straight-line road
network every in-corridor stop costs almost nothing to reach — the largest
detour the live run produced for a stop ahead was **4 seconds**. The consequence
is that the detour **threshold** cannot exclude anything at runtime here, and the
run says so rather than passing quietly. The threshold rule itself is exercised
by `RestaurantDiscoveryServiceTest` against a provider the test controls, where a
restaurant 400 m from the road with an eighteen-minute detour is correctly
excluded.

**To clear:** configure `GOOGLE_ROUTES_API_KEY` with the restrictions documented
in [21-maps-and-routing.md](21-maps-and-routing.md), set `ROUTE_PROVIDER=google`,
and re-run `mobile/tool/route_smoke.dart`. The run prints what the provider
actually returned, so the evidence updates itself.

---

## Open — product gaps (by design, scheduled)

### KI-005 · No authentication ~~open~~ → **partially resolved in Module 03**

Module 01 had no login at all. Module 03 closed it for the **customer** surface: phone + OTP
sign-in, Sanctum sessions, and `role`/`abilities` gates on every protected route
(see [18-customer-authentication.md](18-customer-authentication.md)).

Still open for the **restaurant and admin** surfaces: both web shells continue to render a
clearly-labelled development persona and their account menus stay disabled. The middleware those
surfaces will use (`role:`, `abilities:`) exists and is tested — `AuthorizationBoundaryTest` proves
a customer token is refused by routes shaped like theirs — but no restaurant or admin sign-in is
built yet.

**Every API endpoint that will need authorisation must gain it in the module that introduces it.**

### KI-006 · The schema covers only what the built modules need

Deliberate: creating thirty half-designed tables now would fix decisions before the features that
depend on them are understood. Module-specific migrations arrive with their modules.

As of Module 03 the schema is `users` (extended with customer identity, status and last-login),
`otp_challenges`, and `personal_access_tokens`. Restaurants, menus, journeys, orders and payments
arrive with Modules 04–11.

---

### KI-007 · The home screen still invents nothing for orders

**Status:** narrowed by Module 05. **Owner:** Module 08.

The journey half of this is **closed**: the home screen reads the customer's real
next journey from `/customer/trips/next`, and Module 02's fixture-shaped
`ActiveTripSummary` was removed rather than left beside it.

What remains is orders. `UnconfiguredHomeRepository` still returns no active
order for every customer in production, because the module that creates one does
not exist. That is the truthful answer rather than a gap: inventing an order
would be a lie told to a real customer about food somebody is supposedly cooking.

**To clear:** Module 08 supplies an order-backed implementation.

### KI-008 · Suspending an account does not revoke its live tokens

**Severity:** Medium — a real gap, not a design choice.

Sanctum access tokens are bearer credentials, and `/customer/me` does not re-check
`users.status` on every request. So an account suspended while a customer's phone is in their
pocket keeps working until the token expires (30 days) or somebody deletes the row.

`CustomerAuthService::issueSession()` **does** refuse a suspended or disabled account, so the
account cannot obtain a *new* session — the gap is only about sessions that already exist.

It is not closed here because the tooling that suspends an account is the admin module, which does
not exist yet; the correct fix belongs with it (`$user->tokens()->delete()` on suspension, plus a
periodic status check for long-lived sessions). The current behaviour is pinned by a test that
documents it honestly rather than pretending otherwise:
`CustomerSessionTest::test_an_account_suspended_after_sign_in_keeps_its_token_until_it_is_revoked`.

**To clear:** revoke tokens in the admin suspension path (Module 13), and decide whether a
per-request status check is worth its cost.

---

### KI-009 · Erasing a customer requires deleting their addresses first

**Severity:** Low — a documented consequence of a deliberate trade, not a defect.

`customer_addresses.customer_id` is `ON DELETE RESTRICT` rather than `CASCADE`,
because MySQL refuses a cascading foreign key on a column that a stored generated
column depends on (error 1215) — and that generated column is what makes "at most
one default address per customer" impossible to violate. See
[19-customer-profile-and-addresses.md](19-customer-profile-and-addresses.md).

So a hard delete of a customer who has saved addresses fails loudly. That is the
better failure: it cannot silently destroy data, and the account-erasure path
needs an explicit audit trail anyway.

**To clear:** the erasure feature (Module 17) deletes addresses explicitly before
the account, inside one transaction.

---

## Bug register — Module 07

All found during Module 07, all fixed and retested. Environment: PHP 8.4.19 /
Laravel 12.69.1 / MySQL 8.0.46 / Flutter 3.47.2 on Ubuntu 24.04; live-view render
in Chromium at 320–430dp.

| ID | Requirement | Description | Severity | Reproduction | Expected | Actual | Root Cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M07-B01 | M07-018 | A stop behind the origin was offered as the traveller's *next* stop | **High** | Discover along a route with a restaurant sited before the origin | Listed last, if at all | Listed **first** | Journey order sorts by distance-along-route, and a restaurant behind the origin projects to zero — so pure journey order put "turn round and drive back" at the top of the list. The relevance score already halved it; the score decides what makes the list, not where it sits in it | Ordering is `(requiresBacktracking, alongRouteMetres)`: backtracking stops go last, still offered because the customer may be standing beside one | `RestaurantDiscoveryServiceTest`; integration run asserts it is last; `state-11` | **Fixed** |
| M07-B02 | M07-061 | A screen reader was told "0 m ahead" about a restaurant the screen labelled "Behind you" | **High** | Inspect the semantics label of a backtracking card | The two agree | The visible chip said "Behind you", the spoken label said "0 m ahead" | The chip and the label computed the same fact separately, and only the chip knew about backtracking. Found by driving the built app through the semantics tree — no screenshot could show it | One string, used by both | `discovery_screen_test.dart`: the label matches "Behind you" and never "0 m ahead" | **Fixed** |
| M07-B03 | M07-031 | Price level was conveyed by rupee symbols alone | Medium | Inspect a card's semantics label | The price is announced | "₹₹" only, which a screen reader announces as nothing useful — and which a font without the glyph draws as two empty boxes, as the live harness did | The card had a `priceLevelLabel` string written for exactly this and never used it | The word — "Moderate" — is in the semantics label beside the cuisines | `discovery_screen_test.dart` | **Fixed** |
| M07-B04 | M07-059 | A single route fact overflowed the card at 320dp | Medium | Open discovery at 320×568 | Facts wrap | `RenderFlex overflowed by 69 pixels on the right` — "1.8 km off your route" is wider than a 320dp card | The fact's `Row` had an unconstrained `Text` | The text is `Flexible` and wraps; the `Wrap` above it already handled facts that would not sit side by side | `discovery_screen_test.dart` at 320dp; `state-18` | **Fixed** |
| M07-B05 | M07-027 | The map/list toggle overflowed the header at 320dp | Medium | Open discovery at 320×568 | The toggle fits | 69px overflow: with both labels the control wants about 250dp | Two labelled segments plus the result count do not fit on a 320dp row | Below 300dp the segments drop to icons and keep a tooltip, which is also their accessible name | `discovery_screen_test.dart` asserts the tooltip is still findable at 320dp | **Fixed** |
| M07-B06 | M07-048 | Every derived figure in the integration fixture came from a duration the fixture never set | Medium | Assert time-ahead against a fixture route's own duration | 7 000 s at the halfway point | 8 550 s | The `TripRoute` factory defaults `traffic_duration_seconds` to 17 100, and the fixture set only `duration_seconds` — so time-ahead and the detour baseline were both computed from a leftover | The fixture sets all three explicitly. **A factory default is not a neutral value**: anything derived from it is derived from a number nobody in the test chose | `RestaurantDiscoveryServiceTest` | **Fixed** |
| M07-B07 | M07-018 | The backtracking fixture was never actually tested | Medium | Seed a fixture 30 km behind the origin and discover | It is a candidate, flagged as backtracking | It was rejected by the bounding box, so the rule it existed to prove never ran | A fixture behind the origin must still be inside the corridor to reach the geometry stage; 30 km is not | The fixture sits at fraction −0.012 — genuinely before the route, comfortably inside the corridor. **A fixture that cannot reach the code under test is worse than no fixture**: it passes | Integration run and live view both exercise it | **Fixed** |

| M07-B08 | M07-051 | **A customer's phone number was being written to the application log** | **High** | Cause any unique-constraint violation on `users.users_phone_e164_unique`, then read the log | The constraint name, and nothing about anybody | `Duplicate entry '+919999900101' for key 'users.users_phone_e164_unique'` — 38 times in one day's log, by two independent reporting paths | Two mechanisms, and the first fix only caught one. A PDO driver names the offending value in its message, and Laravel **also** appends the whole statement with its bindings inlined and unquoted, to *every* `QueryException`. Separately, a throwable in log context is serialised through its **public** properties, and `PDOException::$errorInfo` is public. The redaction layer matched by key and only descended into arrays, so an object walked straight past it | Redaction happens in `StructuredFormatter`, where this project already puts it: a throwable in context is reduced to class, file and line; the `(Connection: …)` tail is dropped entirely, which is the only reliable rule because the bindings are positional and unquoted; and the driver's own "Duplicate entry '…'" is scrubbed. **The constraint name survives** — the operationally useful half, which says nothing about anybody | Two unit tests, plus a live probe that provokes a real duplicate key and greps the resulting lines | **Fixed** |

No Module 07 issue was left open.

**B08 is not a Module 07 defect.** It has been present since Module 03 gave
customers a phone number, and four modules of privacy sweeps did not find it —
because each one grepped for *that module's* test data, and this leak only
appears when a constraint is actually violated. It was found here by sweeping a
real application log for a value that had no business being in it, rather than by
sweeping for values the module had put there. That is the lesson worth keeping:
**sweep the log for what it contains, not for what you expect it to contain.**

### Also found here — a verification-harness gap

The live driver's `expectStatuses` for console errors was a single global list,
so a page that deliberately provokes a 409 or a 500 could only be accommodated by
loosening the check for **every** page — including the ones where an unexpected
500 is exactly what the run exists to catch. It is now a per-page option: the
default set covers what every driver provokes, and a page that provokes another
status names it.

And a second, of the same family as Module 06's: an assertion about the *last*
restaurant in the list reported "not found" whether the app was right or wrong,
because a `ListView.builder` never builds a card below the fold and an unbuilt
card has no semantics node. The driver scrolls now. Module 06 recorded the same
trap about route alternatives, which is a fair sign it is worth a helper rather
than a comment.

## Bug register — Module 06

All found during Module 06, all fixed and retested. Environment: PHP 8.4.19 /
Laravel 12.69.1 / MySQL 8.0.46 / Flutter 3.47.2 on Ubuntu 24.04; live-view render
in Chromium at 320–430dp.

| ID | Requirement | Description | Severity | Reproduction | Expected | Actual | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M06-B01 | M06-041 | A test proving recovery after a provider failure could not fail | Medium | Swap the bound `RouteProvider` between two requests in one test process | The second request uses the new provider | The first provider answered both | `Route::getController()` caches the resolved controller on the `Route` object, which outlives a request inside one test process — so `$app->instance()` changed what `make()` returned and not what the controller already held | The double is mutable (`failWith`, `findsNothing`) rather than replaced. **A container rebind mid-test does not reach an already-constructed controller** | `RouteCalculationServiceTest` (23) | **Fixed** |
| M06-B02 | M06-050 | A successful calculation could be reported as a failure | Medium | Calculate a route while the trips list endpoint is failing | The route is shown | The whole operation reported an error | After a successful calculation the controller re-reads the surfaces that carry a route summary; an error from *those* reads propagated as though the calculation itself had failed | The refresh is best-effort, in a `try`/`catch`, and documented as such | `route_controller_test.dart` (16) | **Fixed** |
| M06-B03 | M06-006 | Restoring a session threw whenever a scope was torn down mid-restore | **High** | Dispose the container while `AuthController.restore()` is between its two awaits | The restore is abandoned quietly | `Bad state: Tried to use … after dispose` | A Module 03 defect this module's tests exposed: `state` was written after two async gaps with no disposal check | A `_disposed` flag and a `_set()` used at every post-await write, matching the pattern M05-B07 established | Auth controller tests | **Fixed** |
| M06-B04 | M06-033 | The map-unavailable state overflowed the smallest supported screen | Medium | Open the route screen at 320×568 with no Maps key | The state fits or scrolls | `RenderFlex overflowed by 132 pixels` | The icon, title, body and both place names are taller than the ~180dp a short phone leaves for the map area | A `SingleChildScrollView` with a smaller icon and tighter spacing | `route_screen_test.dart` at 320dp | **Fixed** |
| M06-B05 | M06-024 | An alternative's chips overflowed at 390dp | Low | Show a route with both a traffic chip and a comparison chip | Both chips fit or wrap | `RenderFlex overflowed by 4.6 pixels` | The chips were in a `Row` | A `Wrap` | `route_screen_test.dart` | **Fixed** |
| M06-B06 | M06-046 | An unauthenticated request without `Accept: application/json` was answered 500 | **High** | `curl -H 'Accept: text/html' /api/v1/customer/trips` | 401 with the documented error shape | 500, and `Route [login] not defined` in the log | Laravel's default guest redirect points at a `login` route. This API has none, so the redirect threw *before* the `AuthenticationException` the renderer knows how to turn into a 401. Every JSON client was fine, which is why four modules of tests never saw it | `redirectGuestsTo` returns null, so the authentication exception survives to the renderer | `ErrorContractTest`: "a guest is told 401 even without an accept header" | **Fixed** |
| M06-B07 | M06-033 | The recentre button was offered where there was no map to recentre | Medium | Open the route screen in a build with no Maps key | No recentre control | The control was there and did nothing when tapped | The action was gated on "there are routes", not on "there is a map" | Gated on `MapsConfig.canRenderMap`, which gained a `@visibleForTesting` override so both halves can be tested | Two tests: offered with a map, absent without | **Fixed** |
| M06-B08 | M06-033 | The development-provider banner covered the map-unavailable text at 320dp | Medium | Open the route screen at 320×568 with `ROUTE_PROVIDER=development` | The notice and the place names are both readable | The banner sat squarely on top of "New Delhi → Jaipur International Airport" | The banner is `Positioned` over the map area, which is right over tiles and wrong over the fallback, whose whole content is the words the customer is there to read | Overlaid only where a map renders; in flow beneath the fallback otherwise | `route_screen_test.dart` asserts the two rects do not overlap; `state-17-320-route.png` | **Fixed** |

No Module 06 issue was left open.

### Also found here — two defects in the verification harness itself

Neither is a product defect, and both are worth recording because they made the
live run lie in opposite directions.

`Playwright`'s `hasText` matches **case-insensitively**, so the assertion "the
route screen never says ETA" was matching the word "route d**eta**ils" and
reporting a failure that did not exist. And Flutter renders a semantic heading as
an `<h2>` element rather than an `<flt-semantics>` one, so the assertion "home
shows *Your journey*" could never have passed however correct the app was. An
assertion that cannot fail for the right reason is worse than no assertion; both
now walk the whole semantics host and match case.

## Bug register — Module 05

All found during Module 05, all fixed and retested. Environment: PHP 8.4.19 /
Laravel 12.69.1 / MySQL 8.0.46 / Flutter 3.47.2 on Ubuntu 24.04; live-view render
in Chromium at 320–430dp.

B01–B05 were found during the module's first pass, which built a journey planner
from the project roadmap rather than from the specification. That pass was
replaced, and the code some of these fixes lived in went with it — they are kept
here because the register is a record of what was found, not of what survived.
Where the lesson still applies to the current code it is said in the row.

| ID | Requirement | Description | Severity | Reproduction | Expected | Actual | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M05-B01 | M05-012 | A journey could be created in the past | **High** | Call `TripService::create()` with a departure behind the clock | Refused | Accepted and stored | `update()` checked the departure and `create()` did not — it leaned on the form request, so any caller reaching the service another way could write a journey into the past | The service checks its own boundary rather than trusting the request. The rule survives the rework as a principle: **the service validates, the request only filters** | `TripServiceTest` | **Fixed (superseded)** |
| M05-B02 | M05-020 | Cancelling threw an assertion in debug and could crash the screen | **High** | Open the cancel dialog, confirm it | The dialog closes cleanly | `A TextEditingController was used after being disposed` | The controller was created beside `showDialog` and disposed as soon as the future completed — while the dialog's exit animation was still building its `TextField` | The dialog became a `StatefulWidget` owning its controller. The rework removed the reason field entirely, so the current discard dialog has no controller at all | `trips_screen_test.dart` | **Fixed (superseded)** |
| M05-B03 | M05-019 | The Trips empty state's only action was unreachable on the smallest supported screen | **High** | Open Trips with no journeys at 320×568 | "Plan your first journey" is on screen | Measured at y=580 on a 568px display — below the fold | The 116px motif plus a headline, a paragraph and padding is taller than the space a short phone leaves under an app bar, a segmented control and the navigation bar | The shared `EmptyStateView` shrinks its motif and tightens its spacing below 420px of height; the action never moves | `trips_screen_test.dart` at 320dp; `state-24-320-planner.png` | **Fixed** |
| M05-B04 | M05-015 | A partial update silently reset the traveller count | **High** | Plan a journey for three, then edit only its note | Three travellers | One | `TripDraft.travellerCount` defaulted to 1, so every partial update sent a value for a field the customer had not touched — invisible to the API assertions, which only checked the update that set it | The default removed: null means "the request said nothing". Found by reading MySQL, not by reading a response, which is why the integration run still re-reads the database | Model test; integration run | **Fixed (superseded)** |
| M05-B05 | M05-003 | The planner's rows were unlabelled to a screen reader | Medium | Inspect the planner's semantics | Each row names itself and what it holds | A tappable region with no accessible name at all | An `InkWell` around an `InputDecorator` produces a gesture target, not a labelled control | Wrapped in `Semantics(button: true, label: …)` carrying the field and its value | Semantics inspected in the live run | **Fixed** — and see B08, which this fix caused |
| M05-B06 | M05-030 | Two unrelated places compared equal | Medium | `TripLocation.isSamePlaceAs` on two endpoints that both have an empty `place_id` | Compared by distance | Judged the same place, so a valid journey was refused | The identity check was `placeId != null && placeId == other.placeId`; an empty string is not null, and `'' == ''` | Both identity checks require a non-empty value on this side before comparing | `trip_models_test.dart`: "Delhi and Jaipur are not the same place" | **Fixed** |
| M05-B07 | M05-014 | An `autoDispose` controller reached for `ref` after its provider was gone | Medium | Close the picker sheet while a search is in flight | The answer is discarded | `Cannot use the Ref of … after it has been disposed` | The controllers read their repositories lazily through `ref` and wrote `state` after an await, both of which throw once the sheet has closed | Dependencies captured at build time; a disposal flag checked before every state write; the planner takes the list notifiers *before* awaiting so a refresh still works if the customer navigates away | `place_search_test.dart` drives the full lifecycle | **Fixed** |
| M05-B08 | M05-003 | Labelled rows announced themselves as buttons and could not be pressed | **High** | Drive the built app and click the picker's "Use my current location" row through the semantics tree | The sheet acts on it | Nothing happens; assistive technology has no way to activate the row | B05's fix used `Semantics(excludeSemantics: true)` to give each row one sensible label, which also **removes the child `InkWell`'s tap action** from the semantics tree. Every row fixed by B05 had the defect, plus the Home planner card and the quick-action tiles | The tap action is declared on the node that carries the label, in all four places | Two tests assert `SemanticsAction.tap` on the labelled nodes; the live run now drives every row by name | **Fixed** |
| M05-B09 | M05-041 | "Finding you…" never resolved | **High** | Open the picker in a browser that leaves the permission prompt pending; tap "Use my current location" | A refusal or a timeout within seconds | The spinner ran for 25 s and was still running when the probe gave up | `LocationSettings.timeLimit` is advisory: `geolocator_web` does not honour it, and an unanswered prompt leaves the underlying future pending forever. This is exactly the "do not trap the customer" case | A Dart-side deadline on the position fetch, and a 25 s backstop in the controller so it holds for **any** `LocationService` implementation | `location_permission_test.dart`: "a device that never answers resolves anyway"; re-driven live, now settles into "We could not find you" | **Fixed** |
| M05-B10 | M05-019 | Every list filter was ignored, so discarded trips sat in the open list | **High** | `GET /customer/trips` from the app after discarding a trip | Only open trips | Every trip, discarded ones included | The client sent `?scope=open`; the server filters on `?status=`. An unknown query parameter is **ignored**, not refused — so the request looked healthy and every widget test against a fake repository, which did its own filtering, still passed | `TripScope` now carries the server's own `TripStatus` values, and asks for no filter at all rather than a word the server would ignore | A unit test pins the vocabulary against `TripStatus`; the integration run asserts it against a real server | **Fixed** |
| M05-B11 | M05-008 | Every journey started from a place called "Use my current location" | Low | Create a trip from the device's position, then read the `trips` row | A place name | The row's action label, stored as the origin's name | The current-location endpoint used the picker row's label as its display name; the reverse-geocoded name was fetched and then only used for the city | The reverse-geocoded name supplies the display name when there is one; the neutral "Current location" is the fallback for a point that cannot be named | `trip_models_test.dart`; MySQL now reads `New Delhi → Jaipur International Airport` | **Fixed** |

No Module 05 issue was left open.

### Also fixed here — a Module 01 defect this module exposed

`EnforceIdempotency` derived its actor from `$request->user()`, which middleware
reads **before authentication has run**. Two retries of the same request could
therefore land on different cache keys and both execute. It now fingerprints the
`Authorization` header. Module 04's idempotency tests passed against the bug by
coincidence; Module 05's did not.

### Also closed here — a Module 04 gap

The address API accepted `latitude`/`longitude` but the Flutter `AddressDraft`
never sent any, so **no saved address could ever be used as one end of a
journey**. The address form now offers "Find this address", which resolves a real
place through the same server-mediated search. Nothing geocodes the typed lines.

### Noted, not a defect

Flutter web does not place the bottom `NavigationBar` in the DOM semantics tree,
so the live-view driver reaches it by geometry. The bar is a standard Material
`NavigationBar` with a label and a tooltip on every destination, and it is
exposed correctly on Android and iOS; this is a Flutter web rendering limitation,
not a gap in the app.

Two more for the next driver: a `Semantics` node that carries its own `label`
exposes that text as an `aria-label` rather than as child text, so a driver
matching on text content alone will miss it; and popup menu items are not in the
semantics tree at all, so they have to be tapped by geometry from the anchor's
position taken *before* the menu opens.

The application log records the actor's uuid in the event context but leaves the
envelope's own `actor_id` null on these routes. The information is present and
correctly scoped; the duplication is cosmetic and is left for the module that
next touches `StructuredLogger`.

---

## Bug register — Module 04

All found during Module 04, all fixed and retested. Environment: PHP 8.4.19 /
Laravel 12.69.1 / MySQL 8.0.46 / Flutter 3.47.2 on Ubuntu 24.04; live-view render
in Chromium at 320–768dp.

| ID | Requirement | Description | Severity | Reproduction | Expected | Actual | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M04-B01 | M04-017 | The migration would not run | **High** | `php artisan migrate` | Table created | `1215 Cannot add foreign key constraint` | MySQL refuses `ON DELETE CASCADE` on a column a stored generated column depends on, and `default_for_customer` depends on `customer_id` | `RESTRICT` instead, with the consequence documented as KI-009 — the generated column is worth more than the cascade | Migration runs; `SHOW CREATE TABLE` in the evidence file | **Fixed** |
| M04-B02 | M04-015 | Every row would have collided on the one-default index | **High** | Insert any second address | Non-default rows do not collide | Laravel appends `NOT NULL` to a `rawColumn`, so the generated column could never be NULL | `->nullable()`, which is load-bearing rather than decoration | Two addresses save; the DB still rejects a second default | **Fixed** |
| M04-B03 | M04-010 | A form could be saved with fields nothing had validated | **Critical** | Open Add address on a phone, tap Save with the lower fields off screen | Validation errors on every empty required field | The request went through with an empty city | `ListView` builds lazily, so an off-screen `TextFormField` is not in the tree and is never registered with the `Form` — `validate()` silently skipped it | Both forms rebuilt on a non-lazy scrolling `Column` | Widget tests assert every required field errors | **Fixed** |
| M04-B04 | M04-010 | The Save button was off screen and unreachable | **High** | Open Add address at 393×852 | Save is reachable | The tap landed on the bottom navigation instead | A seven-field form is taller than a phone, and the action sat at the end of the scroll | Pinned to the bottom of both forms, above the keyboard | `state-06`, `variant-320-add-form` | **Fixed** |
| M04-B05 | M04-013 | Type labels wrapped mid-word at 320dp | Medium | Render Add address at 320×640 | "Home / Work / Other" | "Hom e" and "Othe r" | An icon plus a label in each of three segments does not fit 288dp, and Material wraps rather than shrinks | Icons dropped below 320dp of usable width; the label carries the meaning | `variant-320-add-form.png`; a test asserts it at 320dp | **Fixed** |
| M04-B06 | M04-026 | Three identical row buttons were indistinguishable to a screen reader | Medium | Inspect the semantics of a populated list | Each names its own row | All three were labelled "Edit" | The `PopupMenuButton` tooltip named one of its actions rather than the row | `Options for {label}` | Semantics inspected in the live run | **Fixed** |
| M04-B07 | M04-002 | The create response disagreed with a later read of the same address | Low | Save an address with coordinates, then fetch it | Identical values | `28.5602` then `28.5602000` | The response was built from the un-persisted model; a decimal column round-trips to a fixed scale | `refresh()` after save, so the response is what the database holds | `AddressApiTest` asserts the stored scale | **Fixed** |
| M04-B08 | M04-031 | The Module 03 integration script crashed after enough runs | Medium | Run it once the OTP log has grown | The code is read | `RangeError: Not in inclusive range 0..5560: 5740` | A byte offset was used as a string index, and the log's mask characters are three bytes but one UTF-16 unit — the drift grew with every masked number written | Slice the bytes, then decode | The script runs repeatedly | **Fixed** |

No Module 04 issue was left open.

---

## Bug register — Module 03

Thirteen, all found during Module 03, all fixed and retested. Environment: PHP 8.4.19 / Laravel 12.69.1 /
MySQL 8.0.46 / Flutter 3.47.2 on Ubuntu 24.04; live-view render in Chromium at 320–768dp.

| ID | Description | Severity | Reproduction | Cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M03-B01 | Every OTP challenge stored the hash of an empty string, so no code could ever verify | **Critical** | Request a code, submit it | `DB::transaction(function () use ($phone, $requestIp))` did not capture `$code`, so `$this->hash($code)` hashed an undefined variable | Added `$code` to the closure's `use` list | `OtpChallengeServiceTest` — 15 tests, full issue/verify round trip | **Fixed** |
| M03-B02 | Every international number failed with a `TypeError` | **High** | `PhoneNormalizer::normalize('+919876543210')` | PHP silently casts numeric string array keys to int, so `array_keys(COUNTRIES)` returned `[91, 971, 44, 1]` as integers and `str_starts_with()` rejected them | Cast to string once, with a comment naming the footgun | `PhoneNormalizerTest` — 27 tests including every calling code | **Fixed** |
| M03-B03 | `supportedCountries()` returned `{"code": 91}` — a number — so a client comparing against `"91"` never matched | Medium | Call the helper, inspect the type | Same integer-key coercion | `(string) $code` in the projection | Type asserted in `PhoneNormalizerTest` | **Fixed** |
| M03-B04 | `User::createToken()` did not exist | **High** | Issue a session | `Laravel\Sanctum\HasApiTokens` was imported but never `use`d in the class body | Trait added, with a comment saying why it is the whole credential mechanism | `CustomerAuthServiceTest` — 12 tests | **Fixed** |
| M03-B05 | `OtpVerifyRequest` could not extend `OtpRequestRequest` — the app would not boot | **High** | Any request to the API | Both classes were `final`; one extended the other | Shared rules extracted to an abstract `PhoneFormRequest`; both leaves stay `final` | 197 backend tests | **Fixed** |
| M03-B06 | The welcome screen threw on layout | **High** | Open the app signed out | `Spacer` inside a `SingleChildScrollView`: `minHeight` does not bound a column, and a flex child in an unbounded column is an assertion failure | Copy scrolls inside an `Expanded`; the CTA is pinned. Better at a 1.4× text scale too | `state-01-welcome.png` at 320/393/768dp | **Fixed** |
| M03-B07 | The typed phone number was invisible and the dial code drifted right | **Critical** | Type a number on the phone screen | The country picker was a `prefixIcon` built from a `Container` with an `alignment`, which expands to every pixel its constraints allow — swallowing the whole field | Rewritten as `prefix` (inside the input row, on the text baseline) around a shrink-wrapping `Padding` | `state-04-phone-valid.png`; `variant-320-phone.png` | **Fixed** |
| M03-B08 | The client masked `+919876543210` as `+••••••••3210` while the server produced `+91 ••••••3210` | Medium | Compare the OTP screen with the profile | Two independent masking implementations | `maskE164()` mirrors `PhoneNumber::masked()` using the shared country table | `auth_models_test.dart`; `state-11-profile-identity.png` | **Fixed** |
| M03-B09 | Blank optional fields were sent as `""` rather than absent | Medium | Register with no surname | The screen passed the controller's raw text | Blank → `null` in the screen, with the repository normalising defensively too | `auth_flow_test.dart` asserts `last_name` is null | **Fixed** |
| M03-B10 | `users.status` was `varchar(20)` where `users.role` is a MySQL `ENUM` | Medium | `SHOW COLUMNS FROM users` | The migration used `->string()` against the Module 01 convention | `->enum('status', AccountStatus::values())`; the database now refuses a status the application has no case for | `SHOW COLUMNS` after `migrate:fresh`; 197 tests | **Fixed** |
| M03-B11 | "Change number" rendered centred under left-aligned copy, reading as a heading | Low | Open the OTP screen | The column stretches its children, so the link's text centred | Wrapped in `Align(centerLeft)` | `state-05-otp-empty.png` | **Fixed** |
| M03-B13 | The OTP countdowns stopped while the app was backgrounded | Medium | Background the app on the code screen, return after 25 s | The countdowns decremented a counter on a `Timer.periodic`, and both platforms suspend timers for a backgrounded app — so the one thing a customer does on this screen (switch to their SMS app) froze the clock they were watching | Countdowns derived from absolute deadlines read through `package:clock`; the timer only repaints | A test moves the clock 25 s with no ticks and asserts the display caught up | **Fixed** |
| M03-B12 | A revoked token kept working within a feature test | Low | Log out, then call `/customer/me` in the same test | Test-harness artefact: the app object is reused across calls and Sanctum's `RequestGuard` memoises the resolved user. Production forks a process per request | `forgetGuards()` between requests, with a comment explaining the test measures the API rather than the harness | `CustomerSessionTest` — 11 tests | **Fixed** |

No Module 03 issue was left open.

---

## Bug register — Module 02

All found during Module 02, all fixed and retested. Environment: Flutter 3.47.2 on Ubuntu 24.04,
Chromium render at 320–768dp.

| ID | Description | Severity | Reproduction | Cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M02-B01 | The home screen re-requested data 11 times after one failure | **High** | Force a repository failure; count calls | Riverpod 3 retries failed providers automatically with backoff. On a highway that is a silent loop burning battery and data, and it makes *Try again* meaningless | `retry: (_, __) => null` on `homeDashboardProvider`; recovery is an explicit user action | Retry test asserts exactly 2 loads after one tap | **Fixed** |
| M02-B02 | Greeting read "Good afternoon" at 04:00 | Medium | `greetingFor(DateTime(…, 4))` | The morning test was ordered before a bare `hour < 17`, so pre-dawn fell through to afternoon | Check the small hours first. Matters here: pre-dawn starts are exactly when people open this app | Unit test at 04:00, 08:00, 14:00, 21:00 | **Fixed** |
| M02-B03 | At 320dp the greeting truncated to "Good evening, R…" | **High** | Render Home at 320×640 | 34sp display type against ~210dp of available width once the avatar is placed | Greeting steps down to 28sp below 360dp and 24sp below 300dp | Re-rendered at 320dp — full name visible | **Fixed** |
| M02-B04 | Every button stretched full width; `expand: false` did nothing | Medium | `PrimaryButton(expand: false)` | The theme used `Size.fromHeight(h)`, whose **width is `double.infinity`** | `Size(0, h)` in the theme; width is the caller's decision. The one control that wants full width now says so | Error view's *Try again* is content-width | **Fixed** |
| M02-B05 | The development harness crashed the app on launch | **High** | Run the app in development | The harness is installed via `MaterialApp.builder`, which is **above** the Navigator, so the FAB's `Tooltip` found no `Overlay` ancestor | Handle rebuilt from `Material` + `InkWell`; sitting above the Navigator is deliberate so the handle survives a pushed route | Full app boots; 82 tests pass | **Fixed** |
| M02-B06 | The development handle obscured the order countdown | Low | Open Home with the active-order persona | A solid floating control over scrolling content | Reduced to 55% opacity and moved clear of the primary CTA | Re-rendered; content legible beneath | **Fixed** |
| M02-B07 | `StateProvider` did not compile | Low | `flutter analyze` | Riverpod 3 removed it | Rewritten as `Notifier` + `NotifierProvider` | Analyzer clean | **Fixed** |
| M02-B08 | Module 01's shell tests referenced a deleted class | Low | `flutter analyze` | `FotgAppShell` was replaced by the go_router shell | Tests rewritten against the new architecture; coverage grew from 19 to 82 | 82 pass | **Fixed** |

No Module 02 issue was left open.

---

## Resolved during Module 01

| ID | Problem | Root cause | Fix |
| --- | --- | --- | --- |
| R-01 | CORS blocked every browser request | `config/cors.php` called `config('foodonthego.frontend_urls')`; Laravel loads config files in one pass, so it silently got the default `[]` | Parse `FRONTEND_URLS` from `env()` in `cors.php`, with a comment explaining why |
| R-02 | 405 impossible; test routes shadowed | `Route::any('{any}')->where('any','.*')` matched every method and every path registered after it | Replaced with `Route::fallback()`, consulted only when nothing else matched |
| R-03 | Log writes crashed | `StructuredLogger::__invoke` typed its argument as `array`; Laravel passes the `Logger` | Corrected the signature; tests now write and parse a real log line |
| R-04 | Health endpoints were rate-limited | `throttleApi()` applied globally | Throttle applied per route group; health left exempt, asserted by test |
| R-05 | Topbar overflowed at 768/1024 | Flex children had no `min-width: 0`, and the account name/role never truncated. The overflow appeared **only when the API was down**, because "API unreachable" is longer than "API local" | `min-width: 0` throughout, `max-width` + ellipsis on the account block, health pill collapses to a dot below 900px. Verified with the API forced down |
| R-06 | Mobile ✕ and ☰ visible on desktop | `.fotg-icon-button { display: inline-flex }` is declared after `.fotg-sidebar__close { display: none }` at equal specificity, so it won | Raised specificity to `.fotg-icon-button.fotg-sidebar__close` |
| R-07 | Responsive rule for the health pill did nothing | The rule targeted `.fotg-health > :not(.dot)`, but the label was a bare text node, which CSS cannot select | Wrapped the label in a `<span>` |
| R-08 | **White on primary-600 was 3.31:1 — below WCAG AA** | The brand mid-tone is too light to carry white text | Introduced `--color-primary-interactive` (`primary-700`, 4.88:1) for text-bearing surfaces, in **both** the web and Flutter systems. A contrast test now fails if it regresses |
| R-09 | Sidebar landmark was not labelled | `aria-label` was on `<aside>`, whose implicit role is `complementary`, not `navigation` | Moved the label to the inner `<nav>` |
| R-10 | Disabled button label was invisible | Material's default disabled state is onSurface at 38% over a 12% fill | Explicit `disabledForegroundColor`/`disabledBackgroundColor` at ~6:1 |
| R-11 | `fontFamily: 'Roboto'` named but not bundled | Roboto is a system font on Android but **not** on iOS, so iOS fell back silently; on web the engine fetched it from a CDN | Use the platform font (`null`), documented; component themes now derive from the themed `TextTheme` so a future bundled font actually applies |
| R-12 | Favicon 404 in both shells | No favicon asset | Added an SVG favicon to each app |
| R-13 | Flutter web fetched CanvasKit from `gstatic.com` | Default loader behaviour | Custom `web/flutter_bootstrap.js` points at the locally-emitted `canvaskit/`. Better practice regardless: no third-party CDN at runtime |

---

## Bug register — Module 08

All found during Module 08, all fixed and retested. Environment: PHP 8.4.19 /
Laravel 12.69.1 / MySQL 8.0.46 / Redis 7.0.15 / Flutter 3.47.2, Ubuntu 24.04.

| ID | Requirement | Description | Severity | Steps | Expected | Actual | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M08-B01 | M08-035 | **Every restaurant scored 0.0000** — the recommended ranking was returning the same score for everything | **High** | Rank any set of restaurants and read the scores | Distinct scores reflecting detour, availability, proximity and rating | Every score `0.0000`; the order was decided entirely by tie-breakers, which put "Behind You Diner" first | The four ranking terms were written as a map **keyed by weight**: `[$weights['detour'] => …, 0.30 => …]`. PHP casts float array keys to `int`, so `0.45`, `0.30`, `0.15` and `0.10` all became key `0`. Three terms were silently discarded, the weight sum became `0`, and the division produced `0` for every restaurant | The terms are a **list of `[weight, value]` pairs**, iterated with a destructuring `foreach`. There is no key to collapse | `test_every_weight_actually_reaches_the_score` varies each factor in isolation and asserts the score moves; 14 ranking tests | **Fixed** |
| M08-B02 | M08-024, M08-050 | **A screen reader heard a bare "Filters" over a filtered list** — the active-filter count was not in the button's accessible name | Medium | Apply two filters, then read the live semantics tree | A button named "Filter these stops, 2 filters" | Two separate nodes: a non-focusable one labelled "Filter these stops" and a button whose only text was "Filters". The count reached nobody using a screen reader | A `Tooltip` wrapped around a **labelled** button does not become that button's name — it lands in the tree as a sibling node. It does work for an `IconButton`, whose `tooltip:` parameter *is* its semantic label, which is why the compact variant was correct and the wide one was not | The wide variant is wrapped in `Semantics(button: true, label: …, excludeSemantics: true, onTap: …)`, so one node carries the name, the role and the action. The compact variant keeps `IconButton(tooltip:)` | `test_a_screen_reader_hears_the_count_not_a_bare_Filters` asserts `find.bySemanticsLabel('Filter these stops, 2 filters')`; re-verified in the live tree | **Fixed** |
| M08-B03 | M08-011, M08-021 | **One filter, two names** — the sheet called it "Accepting orders" and the chip called it "Taking orders" | Low | Open the filter sheet, select the availability option, apply, read the chip | One name for one thing | The sheet rendered the **server's** label and the chip rendered the app's. A customer picking "Accepting orders" got a chip saying "Taking orders" and could reasonably read it as a second filter | The sheet passed `option.label` straight through for availability, while every other user-facing string in the module is owned by `AppStrings`. The server's label is meant as a fallback, not as the wording | The sheet maps the availability **value** to the app's own string, with the server's label as the fallback for a case this build has never heard of | `test_the_sheet_and_the_chip_call_an_availability_filter_the_same_thing`; live run asserts "Taking orders (3)" | **Fixed** |
| M08-B04 | M08-030, M08-034 | **A stop behind the customer sorted first** under a price sort | Medium | Sort by price when every restaurant declares the same level | The backtracking stop anywhere but the top | It was first. With no difference in the primary key, the order was decided entirely by whatever came next | The comparators carried `requiresBacktracking` only in journey order, not in the sorts a customer selects. This is M07-B01 arriving through a different door: any sort whose primary key ties degenerates to its tie-breakers | **Every** comparator now carries `requiresBacktracking` immediately after its primary key, then `alongRouteMetres`, then the uuid — so the order is total and no tie can promote a stop behind the driver | `test_a_stop_behind_the_customer_is_never_first` walks all four sorts; the integration run does the same against the real route | **Fixed** |
| M08-B05 | M08-021, M08-029 | **Chips claimed a filter the server never applied** when the request failing was the one that would have applied it | Medium | With results on screen, go offline, then apply a facility filter | The chips describe what is actually on screen | The chip said "Parking" over the previous, unfiltered results, under an offline banner. A customer would read that as "the server checked, and these are the ones with parking" | The applied query was written into state *before* the request, and nothing put it back when the request failed. The state had one field for two different things: what the customer asked for, and what the visible results represent | The controller keeps `_appliedQuery` — the query the current results actually came from — and reverts the chips to it when a refine fails with results on screen. The typed search text is deliberately **not** reverted: pulling text out from under somebody mid-search is worse than the disagreement it resolves | Three tests: the chips snap back, the search survives, and a first load with nothing to snap back to does not misbehave | **Fixed** |

No Module 08 issue was left open. No Critical defect was found.

**Four of the five could only be found by running the thing.** B01 presented
as a plausible-looking list in the wrong order — every unit test on the
comparators passed, because the comparators were correct and their input was
zero. B02 required reading the semantics tree of a rendered build, not the
widget code. B03 required the sheet and the chip to be on screen in the same
session. B05 required an offline device with results already on it.

### Two problems in the test surface, fixed alongside

Neither is a product defect, but both would have let a real one through.

- `SearchMatcher::normalise()` used `iconv('UTF-8', 'ASCII//TRANSLIT')`, which
  turns `शर्मा ढाबा` into `????? ?????` — every Devanagari restaurant name
  collapsing to the same string of question marks, and matching each other.
  Replaced with `Normalizer::FORM_D` plus removal of combining marks, which
  handles `Café` → `cafe` without destroying non-Latin scripts.

- `FakeDiscoveryRepository::$nextError` fires for whichever request resolves
  first, which is the *wrong* request when the test's whole point is that an
  earlier, slower one failed. An `errorFor(query)` callback was added so the
  stale-failure test actually tests what it claims to.

### A measurement recorded so it is not repeated

A composite index `(status, verification_status, is_discoverable, latitude)` was
added to serve the corridor query, measured, and **removed**. Against 5 008
restaurants spread realistically across India it read 554 rows; the existing
`restaurants_position_index` read 585 for the same query. That is not a
difference worth an index's write cost.

An earlier measurement that appeared to show a 5 006-row table scan was an
artefact of unrealistic test data — every synthetic restaurant placed along the
one corridor, which makes a latitude range non-selective by construction. The
plans for both data shapes are in
`docs/evidence/module-08-verification-run.txt`.
