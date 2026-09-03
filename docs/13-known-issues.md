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

### KI-005 · No authentication

Module 01 has no login. Both web shells render a clearly-labelled development persona and the
account menu's items are disabled and marked *Module 02*. **Every API endpoint that will need
authorisation must gain it in the module that introduces it** — no endpoint currently authenticates
because none currently carries data.

### KI-006 · Only `users` exists in the database

Deliberate: creating thirty half-designed tables now would fix decisions before the features that
depend on them are understood. Module-specific migrations arrive with their modules.

---

### KI-005 · The customer app has no backend integration

**Severity:** Medium — by design, but worth stating plainly.

Module 02 is a shell. `UnconfiguredHomeRepository` is what a production build resolves to, and it
returns a dashboard with no journey and no order — the truthful state for an account with nothing in
it. It never invents data.

Real data arrives when the modules that own it land: journeys in Module 05, orders in Module 08.
Only the provider changes; no widget does.

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
