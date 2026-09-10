# 13 — Known issues

## Open — environment blockers

*Entries keep their number and their position when they close, and carry their status in the
heading, so a reference to KI-001 from another document still lands on the right thing. Read the
headings, not the section title: several of the entries below are resolved.*


### KI-001 · Android build cannot be validated — **RESOLVED in CI; the dev container is the residue**

**Severity when recorded:** High. It is no longer a High-severity product issue, and leaving it
looking like one was itself the problem — see the note at the end.

**The verdict this entry carried was wrong by Module 14.** It said, in bold,
*ANDROID BUILD = PENDING. ANDROID DEVICE TEST = PENDING*, and further down
*"It has never been executed."* CI does all of it, and has for several modules:

| CI job | What it actually does |
| --- | --- |
| `Mobile — Android review build` | builds the review APK and AAB, uploads them as an artefact |
| `Mobile — Android emulator` | **downloads that artefact**, installs it on an emulator — `api-level: 34`, `target: google_apis`, `arch: x86_64`, `profile: pixel_6` — launches it and runs `flutter test integration_test/` against a real Laravel server and a real MySQL |

**29 integration tests pass on the emulator**, against the app a client would be handed rather
than a rebuild that happens to share its source. Alongside them: 986 Flutter widget tests, not
the 19 this entry still cited.

**What is genuinely still true, and it is about the development container, not the product:**

| | |
| --- | --- |
| `dl.google.com` | 403 from this container's egress policy — so no local Android SDK |
| Ubuntu's `android-sdk` packages | still a dead end (API 23 only; the installers fetch from `dl.google.com` anyway) |
| `/dev/kvm` | absent here, so no local emulator |
| USB passthrough | none, so no physical handset from here |

None of that reaches CI, which has the SDK, KVM and an emulator. It means **a developer working
in this container cannot build or run Android locally** — a real constraint on the workflow, and
a different claim entirely from "the Android build is unvalidated".

**Since corrected:** the Module 02 shell now has a device test of its own
(`integration_test/module_02_shell_test.dart`), which is what M02-017 and M02-018 actually
asked for. Its first run took the iOS simulator from 29 tests to **31**, which is how the
file is known to have executed rather than been skipped.

**Still genuinely unverified:** a **physical Android handset**. Everything above is an emulator.
Emulators do not catch vendor skins, real GPS drift, battery-saver throttling of background
timers, or an OEM's notification policy.

**To clear the remainder:** run `integration_test/` on real hardware.

---

### KI-002 · iOS build and device test cannot be performed — **RESOLVED in CI; signing is the residue**

**Severity when recorded:** High. Same correction as KI-001, and the same reason.

This entry's own **To clear** read: *"run on a macOS runner — `flutter build ios --no-codesign`,
then the simulator matrix"*. CI has been doing the first two parts of that for several modules:

| CI job | What it actually does |
| --- | --- |
| `Mobile — iOS build` | `macos-latest`, `flutter build ios --no-codesign --debug`, green |
| `Mobile — iOS simulator` | `macos-latest`, boots the first available iPhone simulator by udid, runs `integration_test/` — **29 tests pass** |

So *IOS BUILD = PENDING* and *IOS DEVICE TEST = PENDING* were both false. The safe-area,
keyboard, bottom-sheet and navigation behaviour this entry listed as "unverified on iOS" is
exercised by those 29 tests on a booted simulator.

**What is genuinely still open:**

- **The simulator *matrix*.** One iPhone, chosen as "first available by udid" — deliberately, so
  a hard-coded model name cannot rot when the runner's Xcode changes. The iPhone SE / standard /
  Pro Max spread this entry asked for has **not** been run, so the smallest and largest screens
  are unproven. That is the real remainder and it is narrower than "iOS is unverified".
- **A signed build.** `iOS REVIEW BUILD = PENDING — APPLE SIGNING/TESTFLIGHT ENVIRONMENT
  UNAVAILABLE` still holds. There is no IPA and none was faked.
- **A physical iPhone.** As with Android, a simulator is not a handset.
- **KI-020**, the simulator job's stall, which is bounded rather than diagnosed.

**To clear the remainder:** add two more simulators to the matrix; obtain Apple signing for an
IPA; run once on real hardware.

---

### Both of the above — the reason they went wrong, which is the useful part

Neither entry was ever *dishonest*. Each was accurate the day it was written, and each described
a **development container** while stating its verdict about the **product**. Then CI grew the
capability the entry said was missing, and nothing prompted a re-read, because nothing ever does.

They failed in the opposite direction to KI-008, which quietly **understated a risk** while the
surface it described grew. These **understated the verification** — telling a reader of the
project's own honest-list document that the app had never been built or run on either platform,
when both had been running green in CI for modules.

That is the third and fourth entry in this file found stale in two days, after KI-008 and KI-003.
The pattern is now explicit enough to state as a rule: **a known issue records the system as it
was on the day it was written, and both its severity and its verdict decay.** An entry that names
an environment is especially prone to it, because environments are the thing most likely to change
without anyone revisiting the prose.

---

### KI-013 · `flutter drive` reports success when the target never runs

**Severity:** High (it produced a false verification claim)

**Status: still true of `flutter drive` on this machine; no longer blocking.**
The device tests now run on CI, where `flutter test integration_test/<file>` on
an emulator and a simulator reports per-test results directly and does not go
through the drive extension. Those runs satisfied the negative-control rule
below the hard way rather than by assertion: before passing 8 of 8 on
`c8c1161`, they failed at 6 of 8 and 7 of 8 across five heads, each time naming
the failing test, the line and the widget — a mangled invocation, a tap on a
control at y=977 in an 890-tall view, a `CART_TRIP_CONFLICT` the setup created
itself, and twice a button behind the confirmation snackbar. A harness that
reports that is a harness whose green means something.

`flutter drive` on the development machine is unchanged and should still not be
believed. The rest of this entry stands as the record of why.

`flutter drive --driver=test_driver/integration_test.dart --target=integration_test/...`
exits **0** and prints **"All tests passed."** on this machine even when the
test body never executes. Confirmed with two negative controls, both of which
must have failed and did not:

| Control | Expected | Actual |
| --- | --- | --- |
| A deliberately truncated session token | every test fails at `whoAmI` with a 401 | `All tests passed.` |
| **No** `FOTG_TEST_TOKEN` at all — `requireToken()` calls `fail()` in `setUpAll` | every test fails before its first line | `All tests passed.` |

Tried with `-d web-server --browser-name=chrome` and with `-d chrome`. Neither
reports per-test progress; `-d chrome` never gets past *"Waiting for connection
from debug service"* and then exits 0. The app is served, the browser never
drives it, and the driver treats "no failures reported" as success.

**What this cost.** Two runs were reported as green evidence that the Module 11
device driver worked. They were not evidence of anything. The claim has been
withdrawn from [15-test-evidence.md](15-test-evidence.md),
[14-change-log.md](14-change-log.md) and the traceability table.

**The rule taken from it, which applies to every harness in this repository:**
a green result is worth nothing until a **negative control** has been seen to
fail. Before believing a new runner, break it on purpose — remove a credential,
assert something false — and watch it go red. A harness that cannot fail cannot
pass.

**To clear:** run `integration_test/` on a real device or emulator, where
`flutter test integration_test/` reports per-test results directly and does not
depend on the drive extension. That needs KI-001 or KI-002 cleared first, or a
CI runner — see the `android-device` and `ios-device` jobs in
`.github/workflows/ci.yml`.

---

### KI-014 · A cancelled journey's cart blocks every future cart, permanently

> **RESOLVED in Module 12.** `TripService::discard` now closes the trip's active
> cart in the same transaction that cancels the trip, and `DELETE /trips/{trip}/cart`
> gives a customer a way to release one themselves. Regression tests:
> `CartLifecycleApiTest::test_a_customer_who_cancels_a_journey_can_still_use_a_cart_afterwards`
> reproduces the four requests below and expects a 201 on the last one, and the
> Module 12 device test empties a cart on a handset and then adds to the same
> journey again. The description below is kept as written, because a fixed
> issue that no longer says what it was is a fixed issue nobody can learn from.

**Severity:** High (a customer can reach it in two taps and cannot leave it)

**Found by:** the first on-device CI run that got as far as adding to a cart.
Reproduced against a local backend in three requests.

A cart belongs to a journey. Discarding the journey does not close the cart:
the trip becomes `CANCELLED` and the cart stays `ACTIVE`. Module 11 then
refuses every subsequent add, on every journey, because `CartService::cartFor`
finds an active cart on a different trip and — correctly, by the ONE TRIP
CONTEXT PER CART rule — will not reuse it:

```
POST /trips/{A}/restaurants/{R}/cart/items   200   cart created
POST /trips/{A}/discard                      200   trip CANCELLED
GET  /trips/{B}/cart                         200   {"cart": null}
POST /trips/{B}/restaurants/{R}/cart/items   409   CART_TRIP_CONFLICT
                                                   "You have items in a cart
                                                    for a different journey."
```

`GET /trips/{B}/cart` answers `null`, which is true of journey B and gives the
customer no hint that a cart on a journey they cancelled is what is blocking
them. The cart is on a cancelled trip, so there is no screen that reaches it.

**There is no way out.** `CartStatus::Closed` exists in the enum and nothing in
the codebase ever writes it; no endpoint empties a cart or removes a line.
Every path out of this state belongs to Module 12.

**Not a defect in the refusal.** Refusing to move a stop from one road to
another is the rule working. What is missing is the release: either discarding
a journey should close the cart that belongs to it — which is not "silently
deleting a cart", because the customer just explicitly cancelled its journey —
or cart management must offer a way to empty one.

**Effect on the device run.** The Module 11 device tests used to discard every
open journey and create a fresh one per test, which manufactured exactly this
state and then failed on it. They now share one journey and one cart, and
assert what each tap changed rather than what the cart contains. That works
around the issue for the tests; it does not fix it for customers.

**To clear:** Module 12 (cart management), which owns the cart's lifecycle.
Whichever way it goes, it needs a test that a customer who cancels a journey
holding a cart can still add to a cart afterwards.

**How it was cleared.** The first of the two options above, chosen because it
matches what the customer just did: they cancelled the journey, the cart
belonged to it, and leaving it active is what surprised them. The rows are not
deleted — only the status moves to `CLOSED`, which is what the enum's second
case has existed for since Module 11 and what Module 13's orders will point at.

The same release now happens on three other events, for the same reason the
index makes them necessary: removing a cart's last line, emptying it, and
resolving a conflict by starting a new cart. An empty `ACTIVE` cart still
occupies the one-active-cart-per-journey slot, so leaving one behind would
reproduce this issue by a different route — a cart containing nothing blocking
every other journey.

---
### KI-003 · No PHP static analysis — **FIXED after Module 17**

**Severity when open:** Medium, and correctly rated. It found four real defects on its
first run, one of which had been silently wrong since Module 01.

**The recorded diagnosis was wrong, and that is the more useful half of this entry.**
It said: "Composer resolves dist archives to GitHub zipball URLs, and the environment's
egress policy rejects them." Re-checked before working around it — the proxy's own
status endpoint reported no relay failures whatsoever, and the 403 body says something
different:

```
{"message":"GitHub access to this repository is not enabled for this session.
 Use add_repo to request access. ..."}
```

That is this *development session's* repository scoping, not an organisation egress
policy — and CI has never been subject to it at all, which is where the analysis
actually needed to run. Two of the three packages then installed from git source
first time; only `phpstan/phpstan` is published dist-only (no `source` entry in the
lock), so it alone had to be assembled by hand locally. **The entry blamed the
component that reports failures rather than the one causing them, and nobody re-read
it for sixteen modules.**

**Configured:** PHPStan 2.2.13 + Larastan 3.12.0, `backend/phpstan.neon`, wired into
the backend CI job before `migrate` (Larastan reads the schema from migration files,
so it needs no database and fails fast). `composer analyse` runs it locally.

**434 errors on the first run, 210 of which were not real.** Larastan could not see
the models' types, so every attribute was unknown and every comparison against a cast
enum reported "always false" against perfectly correct code. Two settings fix it and
**both** are required: `databaseMigrationsPath` says which columns exist,
`parseModelCastsMethod` says what they are cast to. Adding the first alone moved the
count from 434 to **exactly 434** — a control that stayed silent, which is how the
second was found. (This project declares casts in Laravel 11's `casts()` *method*,
which Larastan does not read unless asked.)

**The ladder, measured rather than intended:**

| Level | Errors |
| --- | --- |
| **3** | **0 — the CI gate** |
| 4 | 45 |
| 5 | 50 |
| 6 | 133 |

KI-003 named level 6. Level 3 is what the code passes today, and a gate is only a gate
if it is green — one set where the code does not pass is one somebody turns off in a
hurry. Levels 4–6 are almost entirely missing generics and array value types: real work,
and not work worth rushing to reach a number, since done carelessly it yields
`array<mixed, mixed>` everywhere and describes nothing. **No baseline file**, deliberately:
a baseline records "this was already broken" and then never runs out. The counts above
live here, where a person reads them, instead.

**Four real defects, none of which 1,301 tests could see:**

1. **The API request log had no actor. At all.** `LogApiRequests` read
   `is_string($user->role ?? null) ? $user->role : null` — true when `users.role` was a
   string column, permanently false once it became a backed enum. Fixing that exposed the
   larger fault: the whole block sat *above* `$next()`, while these middleware are
   prepended to the `api` **group** and `auth:sanctum` is applied per route group. At that
   point nothing had authenticated anybody, and `$request->user()` fell through to the
   default `web` session guard — which a stateless API request never satisfies. So
   `setActor()` was never called even once, and **every `api.request` line ever written
   carried no actor id and no actor role.** Now read after `$next()` and before the line
   is written. `tests/Feature/Logging/ActorContextTest.php` asserts both, with an
   anonymous-request control; its first assertion failed before the fix.
2. **An unreachable guard in the polyline decoder.** `if ($points === [])` after the decode
   loop could never fire — an empty string is refused at the top of the method, so the loop
   always runs at least once and its error message was unproducible. No test could find it:
   no input reaches an unreachable branch.
3. **Outbox timestamps cast mutable, written immutable.** `available_at` and `published_at`
   were cast `'datetime'` while every writer assigned a `CarbonImmutable`. Harmless until
   something mutates one in place.
4. **A docblock that lied about its own keys.** `PhoneNormalizer::COUNTRIES` was tagged
   `array<string, ...>`; PHP converts numeric string keys to int, so `'91'` has always been
   `91`. The code knew — it casts at `array_keys()` — and the tag did not.

Plus 14 sites assigning a mutable `Carbon` to an immutable-cast column, 10 Eloquent
relations with no generic annotation, and `Trip`, which needed `@property` annotations
because its migration declares the endpoint columns in a
`foreach (['origin','destination'] as $end)` loop as `"{$end}_latitude"` — the right way
to write the migration, and unreadable to anything parsing the file without executing it.

**Evidence:** `docs/evidence/module-17/ki-003-static-analysis-adoption.txt`.

**On raising the level — examined, and the answer is not yet, for a specific reason.**

Level 4 was worked through rather than deferred. **35 of its 45 findings rest on Larastan
believing it knows an Eloquent attribute's type**, which it takes from the migration:
`carts.status` is NOT NULL, so `$this->status?->value` reads as an unnecessary nullsafe.

That belief is wrong in a way that matters. An Eloquent attribute is *absent*, not
defaulted, until something loads it — a model newly constructed, saved but not refreshed,
or hydrated by a `select()` that omitted the column has nothing there:

```
$cart = new App\Models\Cart;
var_export($cart->status);   // NULL
$cart->status->value;        // Attempt to read property "value" on null
```

The schema says NOT NULL; the object in hand says null. Applying level 4's advice at
`Cart::toCustomerArray()` — an API serialiser — converts a cheap `?->` into a **500** for
any caller holding a partially hydrated cart.

**This codebase already knew.** `PickupCredentialService::version()` guards exactly that
case and says so — *"a model has not seen is not a rare edge; it is what every freshly
created record looks like"* — with a test named
`test_deriving_from_an_unreloaded_order_is_refused_rather_than_wrong`. Because
`orders.pickup_credential_version` is `unsignedInteger()->default(1)`, Larastan reports
that guard's `is_numeric()` as always true and the test's `assertNull()` as always false.
Level 4 asks, in two separate findings, for the deletion of a guard whose absence is a
mis-minted pickup credential.

So level 4 is **not refused for being strict**. It is refused because in this
configuration most of its findings are advice to delete correct defensive code, and a gate
whose every finding must be argued with is not a gate — it is a discussion that eventually
gets suppressed wholesale.

**What would actually change it** is not "writing the missing annotations", which is what
this entry originally assumed. It is `@property` blocks declaring the *in-memory* truth
(nullable until loaded) rather than the column truth, across every model — work that
changes what the analyser believes rather than what the code does, and worth doing
deliberately rather than as a step toward a number.

**Evidence:** `docs/evidence/module-17/ki-003-why-not-level-4.txt`.

---

### KI-004 · CI mobile jobs are unexercised — **RESOLVED long ago; the entry simply never said so**

**Severity when recorded:** Medium.

It read: *"they have never run — this repository has had no CI execution yet"*, and **To clear:
first push to GitHub**. That happened at Module 01. Since then every push has run CI, and the
pull-request runs execute all seven jobs — Backend, Web, Mobile Flutter, iOS build, iOS simulator,
Android review build, Android emulator — with the two device jobs gated to `pull_request` and
`main` because a macOS runner and an emulator boot are not worth spending on every push to a work
branch.

Nothing had to be done to close this. It was closed by the first CI run and stayed open in this
file for sixteen modules, which is the same failure as KI-001 and KI-002 above: the work moved and
the prose did not.

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

### KI-008 · A suspended account kept working until its token expired — **mostly FIXED after Module 17**

**Severity when open:** Medium as recorded. It should have been High by Module 16, and the
re-reading below is the more useful half of this entry.

**What was wrong.** A Sanctum access token is a bearer credential sitting on a handset. Nothing
can reach into the handset and take it back, so the only thing that ends a session is the server
declining to honour the token — and nothing declined it. `CustomerAuthService::issueSession()`
refuses to *mint* a token for a suspended account, which stops a suspended person signing in and
does nothing at all about the account suspended *after* signing in. That is the case suspension
exists for. The account kept full access for the token's remaining lifetime: up to **30 days**
(`foodonthego.auth.token_ttl_seconds`, `60 * 60 * 24 * 30`).

**How the entry went stale, which is the part worth reading.** As written it says
"`/customer/me` does not re-check `users.status`" — one endpoint, returning a profile. That was
true when it was recorded. It has not been true since Module 15. There is one middleware group
covering the whole customer surface (`routes/api.php`, `auth:sanctum` + `role:customer` +
`abilities:customer`), so the gap was never about one endpoint; it was about every endpoint behind
that group. By Module 16 those included placing an order and paying for it. A suspended customer
could still spend money.

Nothing changed in this entry while that happened, because nothing prompts a known issue to be
re-read when the surface it describes grows underneath it. Found by an adversarial pass over the
branch rather than by anything routine, which is the actual lesson: **a known issue records the
system as it was on the day it was written, and the severity it was given decays.**

**The cost argument was wrong too.** The old "to clear" asked somebody to "decide whether a
per-request status check is worth its cost". Measured rather than estimated
(`docs/evidence/module-17/ki-008-per-request-cost.txt`): a request carrying a bearer token runs
**two** queries with the check and **two** without it. Sanctum has already loaded the user row to
resolve the token, so `users.status` and `users.is_active` are in memory before any middleware
runs. The check costs nothing, so there was never a trade-off to decide — the decision the entry
was waiting on did not exist.

**What was done.** `EnsureRole` now refuses a request whose account cannot authenticate or whose
`is_active` is explicitly false, answering **403** with `ACCOUNT_SUSPENDED` or `ACCOUNT_DISABLED`
and the same sentence the sign-in path has always used. It went in `EnsureRole` rather than a new
middleware because every authenticated route group in `routes/api.php` already carries `role:`,
which makes it the one place every authenticated request passes through — a separate `active`
middleware would be a second thing to remember on the next route group somebody adds.

The rule is spelled exactly as `TenantAccessService::accountUsable()` spells it, including
`is_active !== false` rather than `=== true`, so there is one rule about whether an account is
usable rather than two that can drift.

**Controls.** The three refusal tests in `CustomerSessionTest` were written first and all three
were red against the old middleware (403 expected, 200 received). A fourth asserts an account in
good standing still reaches both `/customer/me` and `/customer/orders` — a gate that denied
everything would pass the other three.

A fifth control was written and **failed to write its own fixture**, which was more informative
than passing: it tried to store `is_active` NULL on the strength of `accountUsable()`'s note about
an unsaved model holding NULL. MySQL refused — `users.is_active` is `boolean NOT NULL default
true`, so a *stored* row cannot be NULL and a request, which always loads its user from the
database, can never carry one. The note is about an in-memory model and is correct about that; it
is not a statement about rows. Recorded in the test.

**A consequence in the tenancy suite, and the trap in it.** Two tests in `TenantIsolationTest`
asserted that a suspended or deactivated operator gets a 404 from a restaurant they are assigned
to. They now get a 403, because the surface gate refuses before the tenant layer is consulted.
Changing the expected status code and moving on would have been the wrong fix: the request no
longer reaches `TenantAccessService::accountUsable()` at all, so both tests would have stayed
green with that method deleted — a test reporting a boundary that is not there. Both now assert
the 403 *and* ask the service directly. Verified by mutation: replacing `accountUsable()`'s body
with `return true` turns both red.

On the status code itself: the 404 in that suite exists so a caller cannot tell "not yours" from
"not real" about somebody else's restaurant. This tells them nothing about a restaurant — it tells
them about their own account, which they already know, and which the sign-in path has always told
them in these words. Nothing leaks, and a suspended operator gets an answer they can act on
instead of a restaurant that appears to have vanished.

**Still open — the half that is genuinely somebody else's:** revoking an account's tokens when it
is suspended (`$user->tokens()->delete()`). This stops a suspended account being *served*; token
revocation is what stops the credential existing. It needs the admin tooling that performs a
suspension, which does not exist yet. The old entry pointed at "Module 13" for that; Module 13
turned out to be pickup time planning, and the admin module is not yet numbered in the current
plan.

**To clear the remainder:** revoke tokens in the admin suspension path, whenever that module
arrives.

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

---

## Bug register — Module 09

Environment: PHP 8.4.19 / Laravel 12.69.1 / MySQL 8.0.46 / Redis 7.0.15 /
Flutter 3.47.2, Ubuntu 24.04.

| ID | Requirement | Description | Severity | Steps | Expected | Actual | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M09-B01 | M09-001, M09-046 | **A screen-reader user could not open a restaurant's page at all** | **High** | Turn on a screen reader, open discovery, try to reach a restaurant's detail | A "View Highway Spice Kitchen" button, focusable and activatable | The card was a single merged node whose only action selected it. The View button had **no semantics node whatsoever** — nothing to focus, nothing to activate | Module 07's card wraps everything in `Semantics(..., excludeSemantics: true)`, which was right when the card's only job was to be read as one sentence. Module 09 made opening the page the primary action, and `excludeSemantics` was swallowing the control that does it | `explicitChildNodes: true` on the card, with `ExcludeSemantics` around the descriptive column only. The card keeps its one-sentence label; the button keeps its own node, named with the restaurant — a row of twelve buttons all called "View" is a list nobody can navigate | Two widget tests (`the View button has a name of its own`, `the card still reads as one sentence`); re-verified in the live semantics tree | **Fixed** |

No Module 09 issue was left open. No Critical defect was found.

**It could only have been found by reading the running app's semantics tree.**
Every widget test passed, the button was on screen and worked under a finger,
and a screenshot showed nothing wrong. What the live driver could not do was
tap it — which is exactly what a customer using a screen reader could not do
either.

### Two things the live driver got wrong, and what they taught

Neither is a product defect; both are recorded because the next person writing
one of these will hit them.

- The driver asserted on the gallery counter "1 / 3" and could not find it. The
  counter is **deliberately** excluded from the semantics tree, so a screen
  reader hears the position once — on the image, as "photograph 1 of 3" — rather
  than twice in two different forms. The assertion moved to the photograph's own
  accessible name.

- The driver asserted the **About** section was absent on a restaurant with no
  description, and saw it. The route card says "About 2 hr ahead", and the
  driver reads the semantics tree by substring. The section's absence is
  asserted where a heading can be told from a sentence: the widget tests and the
  integration run.

---

## Module 10 — menu, categories and item browsing

### M10-B01 — every dietary badge was silently absent — **High** — FIXED

The Flutter enum's wire strings were `VEG` and `NON_VEG`. The server's
`App\Enums\MenuItemDietaryType` sends `VEGETARIAN` and `NON_VEGETARIAN`.
`MenuItemDietaryType.fromWire` therefore matched nothing, returned `unknown` for
every dish, and `MenuItemBadges` drew nothing at all.

The failure mode is the bad one: no error, no exception, no visible breakage —
just a menu on which no dish is ever marked vegetarian. On a food app in India
that is not cosmetic.

**Why the whole test suite passed.** The widget tests build `MenuItem` objects
directly through `sampleMenuItem(dietary: MenuItemDietaryType.vegetarian)`. They
never cross the JSON boundary, so they could not see a wire string that did not
match. Only the integration run, which reads real rows over real HTTP, could.

Fixed by spelling the server's values in the Dart enum, and by adding a test
that asserts the four strings **literally** rather than deriving them — a
derived assertion would have agreed with whatever was written.

### M10-B02 — a punctuation-only search returned the whole menu as its result — **Low** — FIXED

`MenuSearch::normalise` folds punctuation away, so `%%`, `--` and `...`
normalise to the empty string. `matching()` treats an empty needle as "no
filter" and returns every item — which is the right *content*, but the response
still reported `applied.search: "%%"` and the screen still showed the menu as
the result for that term. A customer reads that as "these all match".

Found by the integration run's injection probes, which expected zero results for
every probe and got the whole menu for the wildcard ones.

Fixed in `MenuQuery::fromRequest`: a term that normalises to nothing is
discarded, so `applied.search` is null and the menu is returned honestly
unfiltered. Two regression tests cover it — one for the punctuation terms, one
proving a wildcard mixed with a letter (`%k`) is still an ordinary search that
excludes non-matching dishes.

### M10-B03 — a screen-reader user could not hear which dishes were vegetarian — **Medium** — FIXED

`MenuItemCard` merges its children into one semantics node — which is right, or
a menu of thirty dishes would be a hundred and twenty separate stops — and the
merged sentence was *"Paneer Tikka. 249 rupees"*.

Everything visible on the card that was not in that sentence was therefore
invisible to a screen reader, and the dietary badge was the important one. On a
food app in India, "is this vegetarian" is not a secondary attribute; it is
often the first question, and a blind customer had no way to ask it short of
opening every dish in turn.

Found by the live driver, which reads the same semantics tree a screen reader
does and could not find "Veg" anywhere on a menu that plainly showed it.

Fixed by putting the diet — and the declared spice level — into the card's
sentence: *"Paneer Tikka. Veg. 249 rupees"*, and *"Chicken Seekh Kebab.
Non-veg. 329 rupees. Spice level: Medium"*. Order matters: the diet is heard
second, because it decides whether the dish is a candidate at all. A dish whose
diet nobody declared goes straight from name to price and claims nothing.

Three widget tests cover it, including one asserting Dal Makhani — vegetarian to
a reader, undeclared in the data — is announced without a diet.

No Module 10 issue was left open. No Critical defect was found.

### Three things the harness got wrong, and what they taught

**Screenshots in this environment carry no text.** Flutter web paints glyphs to
a canvas that headless Chromium does not capture, so every screenshot from
Module 09 onwards shows layout, colour, icons and structure — and no words. The
screenshots are structural evidence; **text is verified through the semantics
tree**, which is real DOM, and through the widget tests, which can read a
rendered string. Three of the live driver's misses were assertions on rendered
glyphs (`₹249`, `₹12,999`, `15 min to cook`) that were never going to be
visible to it; they now read the spoken forms, which is what a screen reader
gets and what actually has to be right.

**Running the regression smokes concurrently with the live run wiped the
menus.** `restaurant_detail_smoke` re-seeds `DiscoveryTestRestaurantSeeder`,
which recreates the restaurant rows — and `menu_items` cascade-delete with their
restaurant. The dark-mode and large-text states consequently found an empty menu
and were re-run afterwards. An operational error, not a product one, and worth
writing down: **the live run and the smoke suite share a database and must not
overlap.**

**An assertion on a dish below the fold passes for the wrong reason.** The menu
is a `ListView.builder`; "Masala Chai is hidden while searching for paneer"
passed because it was never built, and the matching "it comes back when the
search is cleared" then failed for the same reason. Both now use a dish near the
top of the list, which the builder has actually made.

### One thing the test suite got wrong, and what it taught

Not a product defect, and worth recording: three of the first widget-test
failures were the test's fault, not the app's — a chip clipped at the right edge
of a 390 pt phone so `tester.tap` landed on nothing, a lazy selector whose
fourteenth chip had never been built, and a `find.text('Starters')` that matched
both the chip and the heading.

But the fourth was real. Tapping a section chip for a heading the
`ListView.builder` had not built did nothing at all, because `ensureVisible`
needs a `BuildContext` and an unbuilt row has none. A section selector that
works only for the sections already on screen is useless on precisely the menus
it exists for. `_jumpTo` now steps towards the target a screen at a time until
the builder has made the heading.

---

## Module 11 — item customization and the cart

### M11-B01, B02, B03 — three layout overflows at 320 dp — **Medium** — FIXED

Three `Row`s that fitted at 390 dp and did not at 320:

| Where | The two things sharing a line |
| --- | --- |
| `variant_selector.dart` — `GroupHeading` | A group name and its rule chip ("Spice level" + "Required · Choose 1 to 3") |
| `special_instructions_field.dart` — the label | "Special instructions" + "Optional" |
| `special_instructions_field.dart` — the footer | The caveat sentence + the character counter |

Each threw a `RenderFlex overflowed` assertion and clipped text mid-word. All
three are now `Wrap`s.

**Why they were not found earlier.** The widget tests ran at 390 dp, which is a
recent iPhone. A 320 dp test was added, and it asserts
`tester.takeException()` is null rather than only that some text is present — an
overflow *is* an exception, and a test that merely looks for text sails straight
past one.

The general rule taken from it is in
[08-design-system.md](08-design-system.md): when a line holds two independent
pieces of text and either can grow, it is a `Wrap`.

### M11-B04 — a disabled quantity button had no accessible name — **Medium** — FIXED

`IconButton(tooltip: 'Remove one')` becomes an accessible name only when the
button is **enabled**. At quantity one the minus button is disabled — which is
precisely the moment a screen-reader user needs to hear what it is and why
nothing happened. They met an anonymous disabled control instead.

Found by a widget test that could not tap `find.bySemanticsLabel('Remove one')`,
which is the same thing a screen reader could not do.

Fixed with an explicit `Semantics(button:, enabled:, label:)` around each step
button. The general form — **if a control can be disabled, name it explicitly
rather than relying on a tooltip** — is recorded in the design-system doc.

No Module 11 issue was left open. No Critical defect was found.

### Three things the harness got wrong, and what they taught

**Eight widget assertions were wrong about the app, not the other way round.**
The button correctly says "Choose required options" while a required group is
unanswered, so every test that expected "Add to cart · ₹249" without answering
one was asserting a state that should not exist. `₹249` also legitimately appears
twice — the dish's base price and the Regular variant's own price. Both were
tightened rather than loosened: the tests now answer the group first, and assert
the exact count.

**The live driver assumed the seeded data was less complete than it is.** Its
first run expected Paneer Tikka to open with an unanswered required group; the
seeder marks "Mild" as a configured free default, so the dish opens ready to
add. That is the behaviour the default feature exists for. The driver now uses
Masala Chai — two sizes, no default — to reach the "Choose required options"
state, which is the honest way to see it.

**MySQL output needs its encoding stated.** A stored note holding Devanagari and
an emoji came back through `Process.run('mysql', …)` as a `FormatException:
Unexpected extension byte`, because the platform default decoder is not UTF-8.
The row was correct; the read was not. `stdoutEncoding: utf8` and
`--default-character-set=utf8mb4` fixed it. Worth knowing for any future driver
that reads text back out of the database.

### Four more things the live-view harness got wrong

These cost most of a day and none of them was a product defect, so they are
written down rather than repeated.

**A driver that reads the semantics tree must query every element, not just
`flt-semantics`.** Flutter web renders a control's name as an `aria-label` on an
`<flt-semantics>` element, but renders a *plain piece of text* — a group's
description, a stepper's "Quantity, 1", a section's caption — as a bare `<span>`
with no label of its own. A query written against the semantics tag alone cannot
see those at all, and reports them missing from a screen that is showing them.
Three states were "failing" for an hour on that basis. The fix is one character:
query `*` inside `flt-semantics-host` and filter to leaves and labelled nodes.

**Presence is not position.** Flutter copies every heading onto the *screen's*
group label, so "Choose a size" is in the semantics tree at any scroll offset.
A helper that scrolled until a string appeared therefore never scrolled, and the
screenshots for four consecutive states were the same picture of the top of the
page. Scrolling has to be steered by an element's `getBoundingClientRect()`, and
a match taller than the viewport has to be discarded as a container — steering
by the container's box walks the page back to the top one notch at a time.

**Clicking a disabled control through the DOM does not stay put.** Dispatching
`element.click()` at a *disabled* semantics node — it has no handler of its own —
was observed opening the discovery screen's filter sheet on top of the dish. A
real `page.mouse.click()` at the control's real coordinates cannot do that, and
is also closer to what the state claims to be testing.

**A focused text field eats the first tap — on the web.** With the note field
focused, Flutter web holds a real `<textarea>` over the canvas, and the first
click outside it is spent taking focus away, so the Add button needs a second
tap. On a phone the field is a canvas widget and the tap lands on the button.
This is a browser artefact of the harness rather than a defect, but it is the
kind of thing that reads like one at 2am, so: the driver blurs first and
verifies the consequence before believing a tap landed.

### The regression suite needs its base URL stated

`dart run tool/<driver>.dart` with no `--define` uses the app's compiled-in
default, `http://10.0.2.2:8000` — the Android emulator's alias for the host. On
this machine that is not routable and every driver fails at sign-in with
`ApiException(NETWORK)`, which looks exactly like a broken backend. Every smoke
run needs `--define=FOTG_API_BASE_URL=http://127.0.0.1:8000`, as the header
comment in each driver says.

---

## Module 12 — cart management, revalidation and the order summary

### M12-B01 — customer text reached the wire as markup — **Medium** — FIXED

Module 11 asserted that a stored `<script>` never comes back as markup. The
assertion was real; it had simply never been exercised, because the only cart
endpoint at the time returned a badge — a count and a subtotal — and no
free-form text. The cart read is the first endpoint to quote a customer's own
note back, and the moment it did, the test failed.

`ApiResponse` now encodes every body with `JSON_HEX_TAG`, `JSON_HEX_AMP`,
`JSON_HEX_APOS` and `JSON_HEX_QUOT`. Lossless — any parser decodes the same
characters, so a note reading "sauce < 1 spoon" still says that — and it applies
to every field of every endpoint rather than the ones somebody remembered.

**What it taught.** A test can be green because the code is right or because the
code never runs. This one had been the second kind since Module 11, and nothing
distinguishes the two from the outside. See also M12-B04.

### M12-B02 — three availability tests assumed the clock — **Medium** — FIXED

`TripRestaurantApiTest` expected `CLOSED` and got `OPENING_SOON`, on a commit
that touched no backend code. **The service was right**: the run started at
20:02 UTC, which is 01:32 in Asia/Kolkata, 27 minutes before the fixture's 02:00
opening, and a restaurant half an hour from opening is `OPENING_SOON`.

Two further tests shared the fixture and were latent failures for a different
hour — between 20:30 and 21:30 UTC the restaurant is genuinely open and both
would have asserted `CLOSED` against `OPEN_ACCEPTING`. Demonstrated by pinning
20:45 UTC and watching both fail. They had survived only because
`OPENING_SOON` happens to map to a `CLOSED` ordering state.

All three now pin the clock, and the instant that broke the first is kept as a
test asserting `OPENING_SOON`, so the case is covered rather than avoided.

This is the **second** time a clock-dependent fixture has turned CI red on a
commit that touched no backend code. The first was `CLOSING_SOON`, where the
*service* was wrong and a twenty-four-hour dhaba announced "closing soon" for
the last half hour of every night. An availability assertion that does not pin
the clock is a scheduled failure.

### M12-B06 — a fourth clock-dependent test, and the end of the class — **Medium** — FIXED

`TripRestaurantFilterApiTest::test_open_now_and_accepting_orders_are_different_questions`
went red on a **documentation-only** commit, at 20:38 UTC — 02:08 in
Asia/Kolkata, inside the fixture's 02:00–03:00 window. "Midnight Dosa Point" was
genuinely open, so it genuinely appeared under `open_now`. The service was right
for the third time running.

This one had survived three separate greps for the pattern, and the reason is
worth recording: **the assertions do not look alike.** M12-B02's compared an
availability string; another compared an ordering state; this one compared a
*list of restaurant names* with no time anywhere in it. Nothing textual connects
them. What connects them is that a fixture seeded opening hours and an assertion
about something else — cuisines, facilities, filter semantics — silently
depended on a restaurant being shut.

**Fixed at the root.** `Tests\TestCase::setUp` now freezes the clock at
2026-09-07 06:30 UTC — noon in Kolkata, on a Monday, nowhere near an opening
time, a closing time, a midnight rollover or either thirty-minute threshold. A
test needing a different moment calls `Carbon::setTestNow()` itself and says
why. All 1,018 tests pass frozen, with no other change.

**Three controls, because this one is easy to get wrong:**

| Control | Result |
| --- | --- |
| Freeze the suite at 20:38 UTC instead | The test fails — the freeze's *value* is doing real work |
| Remove the freeze entirely | The test fails on the wall clock, reproducing CI locally |
| Reintroduce the `CLOSING_SOON` and `OPENING_SOON` service bugs, suite frozen | **Four pinned tests still catch them** |

The third is the one that matters. Freezing the clock could have bought
determinism by destroying the coverage that found the twenty-four-hour dhaba
bug, and it did not: the boundary tests set their own instants and still fail
when the service is wrong.

**The trade, stated plainly.** The `CLOSING_SOON` bug was found because CI
happened to run at 23:32 local. That is a lottery — the right test in the right
half hour — and its price here was three red builds and several hours. The
replacement is deliberate: tests pinned to the exact instants that matter,
including both that broke this suite, running on **every** build rather than one
in forty-eight. A boundary worth checking is worth checking every time.

### M12-B03 — a suspicion that was not a bug

While investigating M12-B02 the day-of-week filter in `opensWithin` looked as
though it would miss a restaurant opening just after midnight: at 23:45 on
Monday, a 00:15 window belongs to Tuesday and the filter skips it.

Probed with a throwaway test at exactly that moment. It answers `OPENING_SOON`
correctly, because the fixture seeds a window for every weekday and
`nextOccurrence` rolls today's past time forward to tomorrow.

Recorded because "I thought there was a bug and there was not" is worth writing
down once, so the next reader does not spend the same half hour on it.

### M12-B04 — a test that could not fail — **Medium** — FIXED

The negative control for "Keep my cart abandons the add and touches nothing"
did not fire: the code was changed to empty the cart quietly and the test still
passed.

The test was at fault. Its `FakeCartRepository` was constructed and never passed
to the harness, so `emptyCalls` could not move whatever the code did. Every
assertion about it was vacuous.

**What it taught.** This is exactly what negative controls are for, and it is the
argument for running them on assertions that look obviously correct: an
assertion that cannot fail looks identical to one that passes.

### M12-B05 — a fixture that described no server — **Low** — FIXED

Module 11's cart-conflict widget test put the restaurant's name in the refusal's
`message`. The server puts a generic sentence there and the name in
`details.restaurant_name`. The assertion passed because the screen echoed the
message back, not because anything read the name — so a screen that ignored
`details` entirely would have passed it too.

The fixture now matches what the server sends, and the screen reads the name
from `details`.

No Module 12 issue was left open. No Critical defect was found.

---

## Module 13 — pickup time, arrival windows and pre-checkout validation

Five defects, all found and fixed inside the module. Three of them were found by
tests that had to be written or strengthened first, which is the interesting
part of each entry.

### M13-B01 — every restaurant's schedule was shifted by a day — **High** — FIXED

`PickupWindowGenerator` read `day_of_week` with Carbon's convention, where
Sunday is 0. **The column is 0 for MONDAY**, as `RestaurantAvailabilityService`
and `RestaurantHoursService` both already had it and as the model's own docblock
states. The same row therefore said "open Monday" to pickup planning and "open
Tuesday" to discovery.

The unit test was green, and that is the part worth reading. It asserted only
that a *closed* day offered nothing — which is exactly what the wrong convention
produced, because under it the open day looked closed. The test agreed with the
mistake.

It now pins both directions: day 0 is open on a Monday **and** shut on a
Tuesday. Shift the reading either way and one of the two assertions fails.

**What it taught.** A test that only ever asks "is this empty?" cannot tell a
correct emptiness from an incorrect one. Asserting the negative case alone is
half a test.

### M13-B02 — overlapping opening rows offered every window twice — **Medium** — FIXED

An operator who adds a second window rather than editing the first — 09:00–14:00
and then 12:00–22:00 — produced two identical windows for every hour the two
share. A customer offered "1:00 PM" twice in a list of eight has a shorter list
than it looks, from a cause they could never guess.

Windows are now collapsed by start-and-end instant. Found while diagnosing a
different failure: the fixture helper `nearRoute` already opens a restaurant all
week, and a test that added a second schedule on top of it produced exactly this
state by accident.

### M13-B03 — a pickup time stored five and a half hours out — **High** — FIXED

The pickup window is carried in the restaurant's own timezone, because that is
the clock the counter runs on. **Eloquent writes a zoned date-time by formatting
it, not by converting it** — so a 1:40 PM Kolkata window went into the UTC
column as `13:40 UTC`, which is 7:10 PM in Kolkata.

In the one column this module exists to get right.

Converted explicitly at the write, with the zone kept beside the instants in
`pickup_timezone` rather than baked into them. Caught by an API test comparing
the stored instant against the offered one — a comparison that only works
because it compares *instants* and not their rendering.

### M13-B04 — the app would have rendered a Delhi pickup on the phone's clock — **High** — FIXED

The client half of the same split. `DateTime.parse` discards the offset: given
`2026-09-07T13:40:00+05:30` it returns the right instant flagged UTC, so the
only things a screen can do with it are render UTC or convert to the device's
zone. A Delhi pickup read on a phone set to London would have said 8:10 am when
the door says 1:40 pm.

The models now keep the counter's clock face beside each instant — one for
arithmetic, one for reading. Found by a model test written specifically because
the widget fakes built objects directly and left every line of JSON parsing
uncovered.

**What it taught.** The screen's comment claimed this was handled while the code
did the opposite. A comment is not a test.

### M13-B05 — the same moment reported on two different clocks — **High** — FIXED

The chosen window came back in UTC while the options beside it came back in the
restaurant's zone. On a real device that rendered as "Collecting between
12:50 am – 1:00 am" above a list beginning "6:20 am – 6:30 am": the same moment,
twice, five and a half hours apart, with nothing to tell a customer which one
the restaurant means.

Each half was individually correct — the column holds UTC as every timestamp in
this schema does, and the planner emits zone-aware instants — and the response as
a whole was not. **No unit test could have caught it**, because there was
nothing wrong with either side on its own.

It took the first screen that renders both halves together, which is precisely
what an on-device run is for. Found by the Android emulator job on the first
run of `module_13_pickup_test.dart`.

### Not a defect: `INVALID` is narrow in production

With the shipped fifteen-minute route freshness, a chosen window almost always
ages the route out before it passes, so `ROUTE_STALE` fires first. That is the
right precedence and the more actionable message. The test isolates `INVALID` by
holding the route fresh and says why; the status is not dead, it is simply rare
until something refreshes routes in the background.

### Not a defect: two assertions that cannot currently fail

`PickupPlanningServiceTest::test_no_offered_window_starts_before_the_food_is_ready`
is guarded at two independent points and no single-point mutation reaches it.
This is recorded **in the test itself** rather than left to look load-bearing.
The two points that do the guarding have controls of their own that fire.

---

## Module 14 defects

### M14-B01 — every instant but two went out on the wrong clock — **High** — FIXED

A checkout response carried five instants in UTC — `pickup.server_now`, the
travel estimate's `estimated_arrival_at` and `calculated_at`,
`earliest_ready_at`, and the quote's `expires_at` — beside two at `+05:30`. The
pickup response had the same split.

Rendered, that is a quote **"held until 6:40 am" underneath a 1:10 pm
collection**: an expiry seven hours in the customer's past, on the screen where
they agree to pay.

**How it survived Module 13.** M13-B05 was the same defect, found on a device,
and the fix corrected the field that had been looked at — `selectionArray` —
rather than the rule. `PickupPlan::toApiArray` kept serialising the planner's
own instants as stored, and nothing tested the response as a whole.

**Fixed** by routing every instant in both bodies through the restaurant's zone:
`PickupPlan::local`, `ArrivalEstimate::toApiArray($timezone)`,
`Cart::localIso`, and `$plan->local()` in the checkout controller.

**The test is the interesting part.** It does not name fields. It walks the whole
response, collects every ISO-8601 string, and fails if more than one offset
appears — so a field added next year is covered by a test written before it
existed. It also asserts the single offset is `+05:30`, because a body that had
become self-consistent by sending everything in UTC would pass a sameness check
and still be wrong. Written first; it failed naming all five wrong fields.

### M14-B02 — "Change pickup time" was painted as "Change pick…" — **Medium** — FIXED

Side by side with **Edit cart** on a 393dp phone, the second button's label was
ellipsised. A control whose name a customer cannot read, on the screen where they
decide whether to change something before paying.

**No test caught it, and the widget test for that row was green** — `find.text`
matches the `Text` widget by its label, which the ellipsis does not change. What
changes is how much of it is painted.

Found by looking at a screenshot.

**Fixed** by stacking the two buttons full width, which also survives 200% text
where half a screen width never could. Pinned by a test that compares the
paragraph's painted width against the width the label needs; it failed at 126.7
against 135.4 before the fix.

### M14-B03 — the first six screenshots had no text in them at all — **Low** — FIXED

Not a product defect: a defect in the evidence, recorded because of what it says
about the assertions beside it.

Flutter web fetches its default font from a CDN this build environment blocks, so
the first screenshot run produced six images of a correctly laid out app with
**no glyphs anywhere**. Every assertion in that run passed, because they read
Flutter's semantics tree — which carries the text whether or not a single pixel
of it is painted.

**A green result about one thing is not a green result about another.** The
assertions were true and the deliverable was worthless.

**Fixed** by temporarily bundling a stand-in font with the rupee sign in it —
DejaVu Sans; Liberation Sans has no `U+20B9` and rendered every price as a tofu
box — and reverting it immediately. The committed app is unchanged.

### M14-B04 — `packaging_fee_minor` made every restaurant look configured — **Medium** — FIXED

The column was `NOT NULL DEFAULT 0`, so "no packaging fee has been configured"
and "the packaging fee is set to nothing" were the same value. Every restaurant
on the platform read as having configured a fee of zero, which is a commercial
statement nobody had made.

**Fixed** by a migration making the column nullable and moving existing zeroes to
`NULL`. `configured` is now `packaging_fee_minor !== null`.

### M14-B05 — the review build ran twice per commit and collided with itself — **Medium** — FIXED

The `review-build` job carried no event guard, so every commit ran it twice:
once for the `push` event and once for the `pull_request` event. Both produced an
82 MB artefact with the **same name**, and both finalised at roughly the same
moment.

On `f1845d4` the artifact service answered the second one with:

```
Failed to FinalizeArtifact: Received non-retryable error:
Failed request: (403) Forbidden: Error from intermediary with HTTP status code 403
```

The binaries themselves were fine — 82,337,899 bytes uploaded, digest computed.
It was the collision that failed, and it had succeeded on the previous commit
only by luck of timing.

**Worth naming as a defect rather than waving through as a flake.** The commit it
appeared on was backend-only and touched no Flutter code, which is exactly the
shape that invites "not mine, re-run it". It was mine: the job's missing
condition came in with Module 14, and a re-run would have had the same race.

**Fixed** by giving `review-build` the same event guard the device jobs already
have, which removes the duplicate run entirely, and by dropping pull-request
retention to a day — on a PR the artefact exists so the emulator job can install
it, not so it can be kept for a month.

### KI-020 — the iOS simulator job hangs before any test runs — **Medium, environment** — OPEN

**Seen twice, on consecutive commits.** It is not a flake.

| Commit | Build finished | Cancelled | Silence | Tests run |
| --- | --- | --- | --- | --- |
| `fd2e136` | `Xcode build done. 132.3s` | job timeout | 53 min | none |
| `8253730` | `Xcode build done. 148.4s` | job timeout | 50 min 41 s | none |

The distinguishing signature is silence *after* `Xcode build done`. A genuine
test failure prints test names and an assertion; this prints nothing at all
between the build finishing and the runner killing the job. On `8253730` the
whole of the step's output was:

```
17:46:45  Running Xcode build...
17:46:45  Xcode build done.        148.4s
18:37:26  ##[error]The operation was canceled.
```

Both times the orphan-process sweep at cleanup listed `dartvm` and `simctl` as
still alive. The application builds and launches; the test harness never hears
from it. That points at the VM-service attach, not at the tests.

**Not the diff's doing, either time.** `fd2e136` changed only CI configuration
and `8253730` only a Markdown file — neither touched Flutter code. The identical
suite passed on the Android emulator on both commits, minutes apart, and the
same iOS suite completed in ~14 minutes on the commit before the first
occurrence.

**What changed in response.** Not a retry — a re-run is what turned the first
occurrence green, and doing that again is precisely how a permanent problem
becomes a green tick nobody looks at. Instead:

- The test step now carries `timeout-minutes: 30`, well under the job's 60. The
  stall is bounded, and it now ends as a *step failure* rather than a *job
  cancellation*.
- That distinction mattered more than it looks. The diagnostic step was guarded
  by `if: failure()`, and a cancelled job does not satisfy `failure()` — so on
  both occurrences the one step that exists to explain a bad run was skipped.
  Both device jobs now use `if: ${{ failure() || cancelled() }}`.
- The test run was made `--verbose`, then made plain again. The defining
  property of this hang is that it produces no evidence, so the daemon
  handshake was exactly what needed showing. In practice `--verbose` produced a
  45,213-line log, and that volume is what buried an *unrelated* device failure
  for five runs (KI-023). The trade was not worth it: verbosity that hides a
  real failure to catch a hypothetical one is a net loss. Removed in `573d0d0`.
  If this stall recurs, turn it back on **for that investigation only**.
- A new step dumps the simulator's own log for the `Runner` process when the
  step does not finish normally.

**Since the fix — re-measured after Module 17, because "seen twice" with no
follow-up reads as though it is still happening.** Every completed run of this
job on this branch, with the duration of the test step against its 30-minute
limit:

| Run | Test step | Result |
| --- | --- | --- |
| 168 | 18.7 min | success (29/29) |
| 164 | 20.4 min | success (29/29) |
| 162 | 11.3 min | success (29/29) |
| 160 | 10.7 min | success (29/29) |
| 158 | 23.8 min | **failure — with test names and assertions** |
| 146 | 22.6 min | success |

Runs cancelled by a subsequent push are excluded; they prove nothing either way.

**The stall has not recurred in six completed runs.** Every one of them printed
its tests, including the failure: run 158's two failures were a real defect and
a real timeout, both with output, which is the opposite of this issue's
signature. The bound works, and iOS device results have been dependable enough
this module to have found a genuine defect nothing else could reach.

**It is still OPEN, and the reason is not superstition.** The cause — the VM
service attach, on the evidence of `dartvm` and `simctl` surviving cleanup —
was never diagnosed. The stall was intermittent when it happened (twice on
consecutive commits, then never), so six clean runs is weak evidence of absence.
Nothing was fixed; something was bounded.

**The number to watch is 23.8 against 30.** That is 79% of the step budget on
the slowest completed run. A runner a quarter slower than that one would trip
the timeout and produce *exactly this issue's signature* — a killed step — while
being nothing but a slow machine. If this recurs, the first question is no
longer "did it hang" but "how far had it got", and the answer is in the log the
diagnostic step now always prints.

**Module 17's backend-concurrency fix did not measurably change this.** Runs
162 onwards use an eight-worker `php artisan serve` (KI-032); the step times
either side of that change are 11.3 / 20.4 / 18.7 versus 10.7 / 23.8 / 22.6.
Three runs each and a variance dominated by which runner GitHub allocated — the
sample cannot support a claim in either direction, and the iOS job is dominated
by Xcode rebuilds between test files rather than by API latency. Recorded
because it would have been easy, and wrong, to attribute the faster runs to
that fix.

**What this costs, stated plainly.** iOS on-device verification is **more
reliable than this entry used to say, and still not proven**. It has now passed
29 tests on five separate commits, and those passes were real. It cannot be
depended on per-commit until the stall is understood, and no iOS on-device claim
should be made from a run that did not actually print its tests.

### KI-021 — two order-status vocabularies — **Low, design debt** — FIXED after Module 17

The Flutter app carried an `OrderStatus` declared speculatively in Module 02
with `placed`, `accepted`, `cooking`, `ready`, `pickedUp` and `cancelled` — a
fulfilment workflow nobody had specified and the API did not send — alongside
`PlacedOrderStatus`, which carries the states the server actually produces.

This entry set its own condition for closing: *"When a fulfilment workflow is
specified, one of the two goes."* **Module 17 specified it.** `PlacedOrderStatus`
now covers the whole lifecycle, is wire-backed, and is separate from payment
state exactly as this entry asked — "has the customer paid" is read from the
payment, "has the kitchen finished" from the order.

So the speculative enum is deleted and its six states are gone. Everything that
used it — the status chip, the progress track, the palette, the home dashboard's
active-order card, the persona fixtures — now takes `PlacedOrderStatus`.

**Where the copy differed, Module 17's wording won.** The home card now says
"Being prepared" rather than "Cooking", because the tracking timeline says "Your
food is being prepared" and two parts of one app must not describe the same
state differently. That is the same class of defect Module 17 found between its
own status hero and timeline.

**A latent bug came out with it.** `OrderStatusTrack` asked
`status == cancelled` to decide whether to draw a progress track, which was
right for the six states the old enum knew. `PlacedOrderStatus` has **five** ways
off the fulfilment path — awaiting payment, payment failed, cancelled, rejected,
refunded — so a rejected order would have been drawn with four steps still to
come, the exact lie the widget's own docstring forbade. It now asks
`status.isOnFulfilmentPath`, so the next state added cannot reintroduce it.

**Deliberately not added: `isActive`.** The old enum had one. The server sends
`is_active` on the tracking response and `OrderStateMachine::activeStatuses()`
decides it; a second opinion compiled into the app is one that can disagree with
the first, and the app is the side that must not be believed.

### KI-022 — the Razorpay integration has never been executed — **Medium, environment** — OPEN

`RazorpayGateway` is written, reviewable, and has never made a request. No
credentials exist for this project and none were invented, so every deployment
binds `UnconfiguredPaymentGateway` and every call refuses.

What that means for the verification in this module: the three checks, the
idempotency, the webhook handling and the reconciliation are all tested against
a deterministic double and against real HMAC arithmetic. **None of it proves
Razorpay behaves the way its documentation says.** Field names, status strings,
the webhook envelope and the signature format are all taken from the docs and
are unverified against the live service.

The first run against real test-mode credentials should be treated as a
discovery exercise, not a smoke test.

### KI-023 — a device test failure went unread for five CI runs — **High, tooling** — RESOLVED

Not a product defect. A defect in the machinery that reports defects, which is
worse, because it corrupts every judgement made downstream of it.

**What happened.** A Module 15 device test failed with
`ApiException(UNAUTHENTICATED, status: 401)` — thrown loudly, on the first run,
with a full stack trace naming the file and line. Five runs and four commits
later that message reached a human for the first time. In between, two causes
were diagnosed and pushed, and both were wrong; one had already been stated as
fact.

**Three independent defects, each sufficient alone.**

| # | Defect | Why it hid the failure |
| --- | --- | --- |
| 1 | `set -e` | GitHub runs a `run:` block as `/bin/bash -e {0}`. In `flutter test … > log 2>&1; code=$?` / `cat log` / `exit $code`, the shell dies at the redirect the moment flutter exits non-zero — so `code=$?`, the `cat` and the `exit` are dead code **on exactly the path they were written for**. The step still reported the right status, because `set -e` propagates it. That is what made it look like it worked. |
| 2 | An unreachable fallback | `grep -nE '…' log 2>/dev/null \| tail -n 60 \|\| echo 'no markers'` binds `\|\|` to the *pipeline*, whose status is `tail`'s — always 0. A missing log, an empty log, and a log whose failure is not an assertion all printed the same thing: nothing. |
| 3 | `--verbose` | 45,213 lines. A job log is read as its tail; the one line that mattered was nowhere near it. |

**The reasoning error, which matters more than the bugs.** This repository
already carries the rule: *a green result is worth nothing until a negative
control has been seen to fail*, and its corollary, *a control that stays silent
has told you something — find out what*. The diagnostic step printed its own
header and nothing else, twice. That was read as "no assertion failed" when it
meant "nothing was ever printed". Those two readings are not close, and the
difference between them was the whole investigation. Four runs were spent
theorising about the tests instead of asking why a control that should have
spoken had not.

**Fixed, and the fixes exercised rather than assumed.**

- `set +e` around the test invocation, so the capture and the dump actually run.
- The report moved into the step that runs the tests, as the last thing it does
  (`scripts/ci-device-report.sh`), bounded to ~100 lines. Anything printed by a
  *later* step has repeatedly proved unreadable in practice.
- One script for both platforms; every divergence between the two hand-copied
  greps had been a bug. POSIX `sh`, verified under dash — the Android job runs
  its script through the emulator action's `sh -c`, and a bashism there had
  already killed a run in 98 seconds.
- Exercised against four cases before commit — no file, empty file, no markers,
  real assertion — and each produces distinguishable output. Under the previous
  command the first three were identical.
- `device-tests.log` is uploaded as an artifact on every run, pass or fail.

**Confirmed by** run 116 on `4c590e9`: seven jobs, zero failures, both device
jobs green, 27/27 device tests.

**The cost.** Five device runs at ~30 minutes each, four commits, and two
incorrect public diagnoses. All of it downstream of instrumentation nobody had
negative-controlled — including the instrumentation written specifically to
diagnose KI-020, which was itself never tested against a failing run.

### KI-024 — a pickup code can be guessed without limit — **High, incomplete feature** — OPEN

**What is missing.** The 8-character pickup code is one factor of two, and its
strength is 2^40. That is only a large number if guessing is expensive. There is
no redemption endpoint yet, so there is nothing to rate-limit — and therefore
nothing that will fail if the limit is forgotten when one is built.

**Why it is recorded now rather than when the endpoint exists.** A missing
control on a feature that does not exist is invisible. The module that builds
pickup verification will be thinking about scanning, counter flow and staff
UX; the attempt limit is the thing that will not be on that list unless it is
written down before the work starts.

**What the fix has to be.** Attempt-limited **per order**, not per IP and not
per session — the attacker is guessing one order's code and can come from
anywhere. A small number of attempts, then the code stops working and the
customer needs a staff-mediated path.

**Not a mitigation, but worth stating:** the QR path carries the 256-bit token
rather than the code, so the code is the path a human types, not the path the
scanner uses.

### KI-025 — `payments:reconcile` was not scheduled — **Medium, operational** — FIXED after Module 17

`ReconcilePaymentsCommand` existed, was tested, and is the third path to a
confirmed payment — the one that runs when both the client callback and the
webhook were lost. It was not registered in `routes/console.php`, so in a real
deployment it would never have run.

Module 16 registered its own three commands and noticed this one's absence while
doing so. It deliberately did **not** fix it there: it is Module 15's
operational behaviour, and quietly changing another module's scheduling under
cover of this one's work is how a schedule ends up with something nobody decided
to run. This is that decision taken on its own, which is how it was meant to
happen.

**Scheduled every fifteen minutes**, and the number is derived rather than
picked. The command's own `--minutes` default is a fifteen-minute grace period,
so an order is not examined until both other paths have had their chance;
sweeping more often just re-asks about the same orders, and sweeping less often
lengthens the window in which somebody has paid and has no order. It is also the
only scheduled sweep that talks to the payment provider — Module 16's three are
database-only — so the interval is a cost as well as a latency.

Module 15's reason for leaving it unscheduled was that a cadence looked like a
deployment decision. It turned out to be derivable from the command's own grace
period, which is a better answer than either scheduling it arbitrarily or
leaving it out.

**Safe with no gateway configured.** `UnconfiguredPaymentGateway` throws
`PaymentGatewayException`, `ReconciliationService` counts that as `unreachable`
and logs a warning, and the command still exits SUCCESS. A missing integration
stays loud in the log without turning the scheduler into a failing job every
quarter hour.

### And the reason it was invisible: the schedule had no test

KI-025 was found by a person reading `routes/console.php`. That is not a
control. Nothing failed when the line was missing, and nothing would have failed
if Module 16's three had been dropped as well.

Scheduling is the one part of this backend with **no caller**. No route reaches
it, no service depends on it, and every test that exercises these commands
invokes them directly — so a `Schedule::command` line deleted by accident is
invisible to the entire suite, and its consequence is silent: a sweep that
stands between a charge and a missing order simply stops happening.

`tests/Feature/Console/ScheduledCommandsTest.php` closes that. It asserts the
four money sweeps are scheduled, **at their cadences** — "it is scheduled" is
satisfied by `->yearly()`, and a yearly sweep over somebody's money is the same
defect wearing a different hat — and that every one of them carries
`withoutOverlapping()`, which is easy to leave off a line copied from one that
had it.

Three controls, one per way the schedule can rot: dropping
`payments:reconcile` again fails two tests; demoting `orders:recover-captured`
to daily fails the cadence assertion; removing `withoutOverlapping()` from
`outbox:publish` fails the stacking test.

### KI-026 — the captured-payment path has never run against live Razorpay — **Medium, environment** — OPEN

Extends KI-022 into Module 16. Everything downstream of a capture is proven
against the deterministic fake gateway: creation, idempotency, credential
minting, recovery, the outbox. **A capture produced by the real provider has
never reached it**, because this environment has no Razorpay credentials and no
public HTTPS endpoint a webhook could be delivered to.

What is unproven specifically is the *shape* of the real thing — the field
names, statuses and amount units Razorpay actually sends — not the logic that
consumes them. Supplying test credentials and a reachable webhook URL is what
closes this; both remain with the client.

### KI-027 — an order cannot move past PLACED — **Low, by design for now** — OPEN

Every onward transition in `OrderStateMachine::ALLOWED` for
`OrderStatus::Placed` is an empty array, and `Accepted`, `Rejected`, `Cooking`,
`Ready`, `PickedUp` and `Refunded` are declared but unreachable.

This is the current truth rather than an oversight, and the empty arrays are
deliberate: a state machine that permits transitions no code performs is a
state machine that lies. The restaurant-side workflow that fills them in is not
in any built module.

Related to KI-021, the two order-status vocabularies, which will have to be
reconciled at the same time.

### KI-028 — the restaurant cannot move an order — **High, incomplete feature** — OPEN

Module 17 built the service that changes an order's status, tested it, and gave
it no user. The only thing that can drive a real order through ACCEPTED,
COOKING, READY and PICKED_UP today is `dev:order-transition`, which refuses to
run outside local and testing.

**So in a production deployment every order would sit at PLACED forever.** The
customer app would faithfully report that, which is correct behaviour and no
comfort at all.

This is not a defect in Module 17 — the restaurant surface is explicitly a later
module — but it is the gap that makes the platform unusable end to end, and it
is recorded here rather than left implicit in a module boundary.

### KI-029 — status transitions were tested for concurrency, not under it — **FIXED after Module 17**

The entry named its own remedy: "closing this properly needs a test harness that can
run parallel PHP processes against one database". That harness now exists.

**`OrderTransitionParallelRaceTest` spawns eight separate PHP processes**, hands each
the same start instant, and has every one of them spin — not sleep — until that
instant before touching the database. Each worker boots Laravel, warms its container
and opens its connection *before* reaching the barrier, so what races is the
transition rather than PHP's startup.

**The control is the whole point, and it is asserted, not assumed.** A parallel test
that passes proves nothing on its own: processes that fail to overlap satisfy every
assertion. So each race runs twice — once through the real service, and once through a
deliberately naive read-decide-write in the worker — and **the naive run must corrupt
the order**. If it ever comes out clean, the harness is not producing collisions and
the safe run is meaningless.

**What the naive run actually does** (`docs/evidence/module-17/ki-029-parallel-race.txt`,
one observed run):

```
processes that believed they applied it : 1
processes that threw                    : 7
ACCEPTED rows in the audit trail        : 1
order_version after the race            : 8   (should be 2)
```

All eight read `PLACED` before any of them wrote, so all eight updated the `orders`
row — the version was incremented once per process. The audit trail survived *only*
because the unique index on `(order_id, to_status)` refused the duplicates, and the
seven it refused are the seven that threw.

**That distinction is the finding worth keeping: the unique index protects the
HISTORY, and nothing but the row lock protects the ORDER.** A design that leaned on
the index alone would still have produced an order written eight times by eight actors
each believing it was the only one — with a coherent-looking timeline on top.

Through the real service, same harness, same instant: one process applies, one
`ACCEPTED` row, one `OrderAccepted` outbox event, `order_version` = 2.

**A note on what it cost the suite.** This test must COMMIT — eight other processes
have to see the row — so it cannot use the transaction every other test rolls back.
`DatabaseTruncation` cleans up *before* each test that uses it, and this is the only
one that does, so nothing ever ran afterwards: the first full run with it in place
produced **132 failures**, every later test that built the same customer fixture
hitting the unique index on `users.email`. The test worked perfectly and broke the
suite around it. It now empties the tables on the way out.

**Verified:** 5/5 repeated runs of the race, full suite green twice at 1,305 tests.

---

### KI-030 — no cancellation policy, so no cancellation — **Medium, undecided commercial rule** — OPEN

`PLACED → CANCELLED` and `ACCEPTED → CANCELLED` exist in the transition table.
Nothing calls them, and the customer app has no cancel button.

That is deliberate. Whether a customer may cancel, until when, and who bears the
cost once a kitchen has started are commercial decisions nobody has taken, and
adding a button because other food apps have one would be inventing them.
`COOKING → CANCELLED` is asserted **absent** so that adding it later is a
decision somebody makes rather than a line somebody adds while fixing something
else.

### KI-031 — a stale tracking screen had no upper bound on how stale — **Low, design** — FIXED after Module 17

The tracking screen showed a cached order behind an advisory banner when it
could not reach the server. The banner said the status may have changed; it did
not say how long ago the order was read, and there was no point at which the
screen refused to show a cached order at all. Half an hour old and two days old
looked exactly the same.

Two things made this worse than it first sounds. The customer reads the
headline, not the banner underneath it — "Your food is being prepared" answers
their question confidently, and a day later it answers it wrongly. And
`orderTrackingUpdatedJustNow` and `orderTrackingUpdatedMinutesAgo` were already
in `AppStrings`, **used nowhere**: the vocabulary for saying how old a read was
had been written and never wired up.

**Fixed** in three parts.

*The age is now said out loud.* `OrderTrackingState.ageAt(now)` gives the age of
the read, and `AppStrings.orderTrackingUpdatedAgo(Duration)` turns it into one
phrase — "just now" under a minute, minutes, then hours, then "more than a day
ago". Coarse deliberately: "Updated 187 minutes ago" is arithmetic the reader
has to finish themselves. The offline banner carries the same phrase, so the
banner and the hero can never disagree about the age of the same number.

*There is now a point at which the app stops claiming.* Past
`TrackingConfig.vouchedFor` the status hero and the timeline come off the screen
and an explicit "we can't tell you where this order is right now" takes their
place, with the age and the order number. **What does not go stale stays**: the
requested pickup window, the restaurant, the items, the amount paid. None of
those change while nobody is looking; only the claim about where the order is
right now expires.

*The bound is the polling budget, not a new number.* Thirty minutes is already
how long this app is willing to keep a status fresh; past it the app has
stopped maintaining the read. Vouching for a status after deciding not to check
it would be the contradiction. A test asserts the two constants are equal, so
separating them has to be a decision somebody makes rather than a constant
somebody edits.

**Also fixed here, and it is the sort of thing that only shows up on a
screenshot:** a device clock that jumps backwards — a timezone change, a manual
edit, an NTP correction — would have produced a negative age, sailed past every
threshold and blanked a perfectly fresh screen. A backwards jump now reads as
"just now", which is the safe direction for a clock error to fall.

Seventeen tests, and three controls that fire: making the screen always vouch
fails two; removing the backwards-clock guard fails one; reporting hours as raw
minutes fails one. Screenshot: `evidence/module-17/screenshots/tracking-status-unknown.png`.

### KI-032 — the device jobs ran the API on a one-request-at-a-time server — **Medium, tooling** — FIXED at Module 17

CI run 158 failed two on-device tests on the iOS simulator. One was a real
application defect and is fixed separately (the tracking double-unwrap). The
other, `module_11`'s *a dish with no default size asks before it prices*, was
this — and it is worth writing down, because the honest first reading was
"iOS-only, passed on Android, probably a flake", and that reading was wrong.

**What the screen said.** `We couldn't load this item | Please try again in a
moment.` The app was not confused; it had asked for a menu item, been given
nothing within `ApiConfig.requestTimeout` (ten seconds), and said so.

**What the server said.** From the same job's `serve.log`, during that test:

```
17:52:56 .../cart                     ~ 7s
17:52:57 .../routes                   ~ 7s
17:53:03 .../restaurants              ~ 3s
17:53:04 .../restaurants/{id}         ~ 4s
17:53:07 .../menu                     ~ 3s
17:53:09 .../menu/items/29ebfe51-...  ~ 5s
```

Every one of those endpoints answers in **0.04 ms** elsewhere in the same log,
when nothing else is in flight. So this is not slow code and not a slow
machine. It is a queue.

**Why.** `php artisan serve` is PHP's built-in development server, and by
default it is a single worker: it accepts connections and answers them strictly
one at a time. Opening a screen cold asks the session, the trip, the route, the
restaurant, the menu and the item all at once — around nine requests — so the
ninth waits for the sum of the eight ahead of it. `ServeCommand` starts its
timer at the `Accepted` line, not when PHP begins the work, so the durations it
prints *include* that wait. The `~ 5s` above is almost all queue.

**Measured, rather than argued.** Nine concurrent authenticated requests
against the real script-started server on a four-core box, sorted:

```
one worker    0.015 0.030 0.046 0.062 0.076 0.091 0.105 0.120 0.136
eight workers 0.018 0.020 0.026 0.032 0.046 0.061 0.075 0.091 0.106
```

The one-worker row is a 15 ms staircase with no step out of place, which is the
signature of a queue rather than of load; the eight-worker row starts with a
cluster that finished together. Worst case roughly halves here. In CI, where
the requests cost hundreds of milliseconds rather than fifteen, the same queue
is the difference between 0.04 ms and five seconds.

**Why iOS and not Android.** Nothing about iOS. Both jobs ran the same
single-worker server; the iOS job's launches happened to overlap enough to push
one request past ten seconds and the Android job's did not. The same test would
fail on Android on a different day, which is exactly why "it passed on the other
platform" was not a diagnosis.

**Fixed** in `scripts/ci-backend-up.sh`, which both device jobs use:
`PHP_CLI_SERVER_WORKERS=8` and `--no-reload`. The second flag is not optional —
Laravel refuses the worker count without it and prints `Unable to respect the
PHP_CLI_SERVER_WORKERS environment variable`, then carries on with one server.
That warning cost an hour here, so the script now greps its own log for it and
says loudly that it is single-worker rather than letting a future Laravel
version quietly undo this.

**Not fixed, and deliberately:** the ten-second client timeout stands, and the
item and tracking screens still give up after one failed load rather than
retrying. Both are product decisions from earlier modules. Raising a timeout or
adding a silent retry to make a test pass would have hidden the next real
failure, which is the thing these device jobs exist to catch.

### KI-033 — a restaurant "open all week" was shut for one second every night — **Medium, fixture and test data** — FIXED at Module 17

The Android device job on CI run 160 failed one test — `module_14`'s *the
confirmation screen opens cold on a real order id* — with:

```
ApiException(RESTAURANT_NOT_ACCEPTING_ORDERS, status: 409)
  at ApiMenuRepository.addToCart
  at seedOrderReadyToCheckOut (module_14_checkout_test.dart:188)
```

The server was right and the app was right. `[TEST] Highway Spice Kitchen` is
seeded `alwaysOpen`, which wrote `00:00:00 – 23:59:59` for all seven days.
`RestaurantAvailabilityService::covers()` asks `$time < closes_at`, so from
23:59:59.000 to 23:59:59.999 the restaurant is **closed** — and a closed
restaurant refuses a cart line, exactly as designed.

That job ran from **23:46:53 to 00:06:57 in Asia/Kolkata**. It went through the
second. A test that had added to the same cart minutes earlier was refused.

Reproduced, not inferred:

```
IST 23:59:58  availability=OPEN          ordering=OPEN_ACCEPTING  canOrder=YES
IST 23:59:59  availability=OPENING_SOON  ordering=CLOSED          canOrder=NO
IST 00:00:00  availability=OPEN          ordering=OPEN_ACCEPTING  canOrder=YES
```

**This is the second time this fixture has failed on the clock, for the same
underlying reason.** The first was a half-hour a night: `23:59:59` is a closing
time, so a restaurant open around the clock read CLOSING_SOON from 23:30, and a
docs-only commit went red. That was fixed in `closesWithin`, which now asks
whether the restaurant will be *shut* soon rather than whether the current
window ends soon. Both bugs come from the same place: **`23:59:59` was standing
in for midnight, and it is not midnight.**

**Fixed** by not using a stand-in. A twenty-four hour restaurant closes at
midnight and opens at midnight, which is precisely what an overnight window
already means in this schema — `RestaurantOpeningHour::isOvernight()` is
`closes_at <= opens_at`, and `covers()` then holds such a window open from
`opens_at` to the end of the day. So `alwaysOpen` in
`DiscoveryTestRestaurantSeeder` and `openAllWeek` in `RestaurantFixtures` both
now write `00:00:00 – 00:00:00`. No gap, and nothing left to get wrong a third
time.

Pinned by `test_a_restaurant_open_around_the_clock_is_open_through_midnight`,
which asserts every second from 23:59:57 to 00:00:01 rather than only the
guilty one — a test that checked 23:59:59 alone would pass against a fixture
that had merely moved the hole. Control: restoring `23:59:59` fails it.

**Not changed:** `covers()` itself. `$time < closes_at` is correct — a
restaurant whose stated closing time is 23:59:59 really is shut during that
second. The defect was in what the fixture claimed, not in how the rule reads
it. And `PickupWindowGeneratorTest` still passes `00:00:00 – 23:59:59` to
`openDaily` deliberately, on a frozen clock, as an explicit window rather than a
claim of being always open.

### KI-034 — a test slept instead of waiting, and failed once under load — **Low, test reliability** — FIXED after Module 17

Found by a single failure during a full-suite run while three other things were
running on the same machine: `place_search_test.dart`'s *retry re-runs the
current query*. It passed on the next four runs — one targeted, three full —
which is precisely how a race presents itself and precisely the shape that gets
written off as a flake.

It was not a flake. The test called `retry()` and then did:

```dart
await Future<void>.delayed(const Duration(milliseconds: 20));
```

`retry()` bypasses the debounce and fires immediately, so those 20 ms were
standing in for "the request has come back". On an idle machine they are enough.
On a loaded one they are not, and the assertions run against a request still in
flight.

**Fixed** with a `waitUntil(condition)` helper in that file: it waits for the
state to satisfy the condition, with a five-second deadline that is only ever
reached when the test is genuinely going to fail. A passing run leaves as soon
as the condition holds, so it is faster than the sleep it replaces as well as
sound. Control: making `retry()` a no-op fails it in five seconds with *"Timed
out waiting for the retried query to come back"* rather than hanging.

**Left alone deliberately:** the 500 ms waits in the same file. Those let a
*scripted* 400 ms request land, so they have a real basis with headroom, and
they are testing that a stale response is discarded rather than that a current
one arrived. This is the same distinction Module 12 drew about the confirmation
snackbar: a fixed wait against a known duration is a wait; a fixed wait against
"however long this takes" is a coin toss.

### KI-035 — a real customer's home screen still shows nothing, and the recorded reason has expired — **Medium, stale scaffolding** — OPEN

`UnconfiguredHomeRepository` is what a real signed-in customer gets. It returns
a dashboard with a name and nothing else:

```dart
/// Module 08 replaces this with an implementation backed by `/api/v1`.
Future<HomeDashboard> loadDashboard() async {
  return HomeDashboard(customer: CustomerSummary(fullName: customerName));
}
```

**The comment names a module that shipped.** Module 08 was search, filters and
ranking. The two things this repository declines to invent both exist now:

| What the home screen omits | Where it exists | Since |
| --- | --- | --- |
| The active journey | `ApiTripRepository.currentTrip()`, `GET /customer/trips` | Module 05 |
| The active order | `ApiOrderRepository.mine()`, `GET /customer/orders` (`active`) | Module 16, enriched by 17 |

So the decision recorded here — *"it never invents a trip or an order"* — was
right when it was made and is now doing something different from what it says.
It is no longer refusing to invent data. It is withholding data the app already
has, and the reader of that comment would not know it.

**What a customer sees today.** Somebody with food being cooked opens the app
and gets the new-customer home: no journey card, no active-order card. The
Orders tab lists that order and the tracking screen tracks it live. One screen
says "nothing is happening" while two others disagree.

**Why this is recorded rather than fixed.** Wiring it is small — both
repositories are already in the app and already tested. What is not small is
the design, and none of it has been specified:

- **Which order?** The Orders tab handles several active orders by listing
  them. A single card has to choose, or stop being a single card.
- **Which journey?** `currentTrip()` answers one question; whether a trip from
  last Tuesday still counts as current is a product decision, not a query.
- **What the card claims.** The fixture card shows a countdown to an estimated
  pickup. Module 17 was explicit that this app must not show an ETA before
  Module 18 builds one, and the fixture predates that rule.

Building it now would mean answering three product questions with my own
guesses on a screen every customer sees first. **The gap is the smaller
problem; a home screen that quietly invents a policy would be the larger one.**

**To clear:** decide the three questions above, then wire `HomeDashboard` to
the two repositories. Until then, the comment in
`unconfigured_home_repository.dart` should be read as "waiting for a decision",
not "waiting for an API".
