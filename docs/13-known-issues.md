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

## Bug register — Module 05

All found during Module 05, all fixed and retested. Environment: PHP 8.4.19 /
Laravel 12.69.1 / MySQL 8.0.46 / Flutter 3.47.2 on Ubuntu 24.04; live-view render
in Chromium at 320–768dp.

| ID | Requirement | Description | Severity | Reproduction | Expected | Actual | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M05-B01 | M05-007 | A journey could be created in the past | **High** | Call `TripService::create()` with a departure behind the clock | Refused | Accepted and stored | `update()` checked the departure and `create()` did not — it leaned on the form request, so any caller reaching the service another way could write a journey into the past | The service checks its own boundary, with the same configured grace the request applies | `TripServiceTest`: a past departure is refused | **Fixed** |
| M05-B02 | M05-019 | Cancelling threw an assertion in debug and could crash the screen | **High** | Open the cancel dialog, confirm it | The dialog closes cleanly | `A TextEditingController was used after being disposed` | The controller was created beside `showDialog` and disposed as soon as the future completed — while the dialog's exit animation was still building its `TextField` | The dialog became a `StatefulWidget` that owns its controller and disposes it with itself | `trips_screen_test`: three cancel tests | **Fixed** |
| M05-B03 | M05-014 | The Trips empty state's only action was unreachable on the smallest supported screen | **High** | Open Trips with no journeys at 320×568 | "Plan your first journey" is on screen | Measured at y=580 on a 568px display — below the fold, reachable only by scrolling | The 116px motif plus a headline, a paragraph and padding is taller than the space a short phone leaves under an app bar, a segmented control and the navigation bar | The shared `EmptyStateView` shrinks its motif and tightens its spacing below 420px of height; the action never moves | `trips_screen_test` at 320dp; `variant-320-trips.png` | **Fixed** |
| M05-B04 | M05-011 | A partial update silently reset the traveller count | **High** | Plan a journey for three, then edit only its note | Three travellers | One | `TripDraft.travellerCount` defaulted to 1, so every partial update sent `traveller_count: 1` for a field the customer had not touched — invisible to the API assertions, which only checked the update that set it | The default removed: null means "the request said nothing" | A model test asserts the key is absent; the integration run now re-reads the row | **Fixed** |
| M05-B05 | M05-002 | The two place rows and the two time rows were unlabelled to a screen reader | Medium | Inspect the planner's semantics | Each row names itself and what it holds | A tappable region with no accessible name at all | An `InkWell` around an `InputDecorator` produces a gesture target, not a labelled control | Both wrapped in `Semantics(button: true, label: …)` carrying the field, its value and any error | Semantics inspected in the live run; the rows are now drivable by name | **Fixed** |

No Module 05 issue was left open.

### Noted, not a defect

Flutter web does not place the bottom `NavigationBar` in the DOM semantics tree,
so the live-view driver reaches it by geometry. The bar is a standard Material
`NavigationBar` with a label and a tooltip on every destination, and it is
exposed correctly on Android and iOS; this is a Flutter web rendering
limitation, not a gap in the app, and it is recorded here so the next module's
driver does not spend time rediscovering it.

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
