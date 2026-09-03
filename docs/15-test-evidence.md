# 15 — Test evidence

Every figure below comes from a command that was actually run. The full console transcript is at
[`evidence/module-01-verification-run.txt`](evidence/module-01-verification-run.txt); screenshots
are in [`evidence/`](evidence/).

## Environment

| Tool | Version |
| --- | --- |
| PHP | 8.4.19 |
| Laravel | 12.69.1 |
| MySQL | 8.0.46 |
| Redis | 7.0.15 |
| Node.js | 22.22.2 |
| Flutter | 3.47.2 (stable) · Dart 3.13 |

## Automated tests — 115 total, 115 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend | `php artisan test` | 67 | 67 | 0 | 0 |
| Web — `@fotg/ui` | `npm test` | 18 | 18 | 0 | 0 |
| Web — `@fotg/admin` | `npm test` | 7 | 7 | 0 | 0 |
| Web — `@fotg/restaurant` | `npm test` | 4 | 4 | 0 | 0 |
| Mobile | `flutter test` | 19 | 19 | 0 | 0 |
| **Total** | | **115** | **115** | **0** | **0** |

Backend: 205 assertions, 1.13s, against real MySQL 8 and Redis 7.

## Static checks

| Check | Command | Result |
| --- | --- | --- |
| PHP code style | `vendor/bin/pint --test` | **passed** |
| TypeScript | `npm run typecheck` | **0 errors** |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --set-exit-if-changed .` | **0 changed** |
| PHP dependencies | `composer audit` | **No advisories** |
| npm dependencies | `npm audit --audit-level=high` | **0 vulnerabilities** |
| PHP static analysis | — | **NOT RUN** — see KI-003 |

## Builds

| Target | Command | Result |
| --- | --- | --- |
| Restaurant dashboard | `npm run build -w @fotg/restaurant` | ✅ 3.86s |
| Admin panel | `npm run build -w @fotg/admin` | ✅ 3.98s |
| Flutter web | `flutter build web --release` | ✅ 43s |
| **Android APK** | `flutter build apk` | **⛔ PENDING** — Android SDK unreachable (KI-001) |
| **iOS** | `flutter build ios` | **⛔ PENDING** — requires macOS + Xcode (KI-002) |

## Live API verification

Against a running `php artisan serve` with real MySQL and Redis:

| Check | Result |
| --- | --- |
| `GET /api/v1/health/ready` | 200 · MySQL **1.9 ms** · Redis **0.59 ms** |
| `GET /api/v1/nope` | 404 · `NOT_FOUND` in the documented envelope |
| `POST /api/v1/health/live` | 405 · `METHOD_NOT_ALLOWED` |
| `Origin: https://attacker.example` | **0** `Access-Control-Allow-Origin` headers returned |
| `Origin: http://localhost:5174` | `Access-Control-Allow-Origin: http://localhost:5174` |
| Structured log line | Valid JSON with `request_id`, `route`, `status`, `duration_ms`; no body, no secrets |

## Live-view verification — web

Headless Chromium, both shells, at **360 · 390 · 430 · 768 · 1024 · 1280 · 1440 · 1920 px**:

| Assertion | Result |
| --- | --- |
| Console errors / page errors / failed requests | **0** |
| Horizontal overflow (`scrollWidth > clientWidth`) | **none**, at every width |
| Horizontal overflow **with the API forced down** | **none** — the degraded state renders the longest topbar string |
| Interactive controls under 44px | **none** |
| Routes visited | **25** (11 restaurant + 14 admin) |
| Exactly one active nav link per route | ✅ |
| Breadcrumb present per route | ✅ |
| Sidebar collapse / expand | ✅ |
| Account menu opens; Escape closes | ✅ |
| Mobile drawer opens and closes on navigate | ✅ |
| Dark mode | ✅ |

**System Health rendered live values from the real API**: `Ready | Connected | Connected`.

### Screenshots

`restaurant-360` · `restaurant-390` · `restaurant-768` · `restaurant-1440` · `restaurant-collapsed` ·
`restaurant-drawer` · `restaurant-dark` · `restaurant-placeholder` · `admin-360` · `admin-768` ·
`admin-1440` · `admin-collapsed` · `admin-drawer` · `admin-dark` · `admin-system-health` ·
`admin-api-down-768`

## Live-view verification — mobile

The Flutter app was **built and rendered**, and the real widget tree was screenshotted at four
device sizes plus dark mode, with all five tabs visited.

| Device profile | Logical size |
| --- | --- |
| iPhone SE (compact) | 375 × 667 |
| iPhone 15 (standard) | 393 × 852 |
| iPhone 15 Pro Max (large) | 430 × 932 |
| Small Android | 360 × 800 |

Runtime errors: **0**.

Screenshots: `flutter-iphone-se` · `flutter-iphone-15` · `flutter-iphone-15-pro-max` ·
`flutter-android-small` · `flutter-dark` · `flutter-tab-{home,trips,orders,alerts,profile}`.

> **What this rendering is and is not.** It is the real Flutter widget tree, real theme, real
> navigation — compiled from the same Dart source an Android or iOS build would use. It is **not** an
> Android emulator or an iOS simulator, so it does not exercise platform channels, native safe-area
> insets, the on-screen keyboard, permissions or lifecycle. Those remain **PENDING** (KI-001,
> KI-002).
>
> The screenshots were produced by a **throwaway build** that temporarily bundled a stand-in font,
> because Flutter web fetches its fallback font from a CDN this environment blocks. That change was
> reverted immediately; the committed app uses the platform font. Layout, colour, spacing, icons and
> navigation in the images are the product's own.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Body text contrast, light + dark | WCAG luminance computed in `tokens_test.dart` | ≥ 4.5:1 |
| Secondary text contrast | same | ≥ 4.5:1 |
| Primary button text | same | 4.88:1 (**was 3.31:1 — fixed, R-08**) |
| Touch targets, web | browser sweep, 8 widths | none < 44px |
| Touch targets, mobile | `tokens_test.dart` | 48dp floor |
| Type floors | `tokens_test.dart` | body ≥ 15sp |
| Focus visible | `:focus-visible` ring on all interactives | ✅ |
| Skip link | `AppShell.test.tsx` | ✅ |
| Navigation landmark labelled | `AppShell.test.tsx` | ✅ (**moved off `<aside>` — R-09**) |
| Reduced motion honoured | token-level on web, `FotgMotion` in Flutter | ✅ |

## Defects found and fixed during verification

Thirteen, listed with root causes in [13-known-issues.md](13-known-issues.md). Live-view inspection
found five that no unit test would have caught (CORS, overflow, desktop button visibility, dead CSS
rule, favicon 404); the contrast test found the palette defect.


---

# Module 02 — test evidence

Full transcript: [`evidence/module-02-verification-run.txt`](evidence/module-02-verification-run.txt).
Screenshots: [`evidence/module-02/`](evidence/module-02/).

## Automated tests — 197 total, 197 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Mobile — domain models | `flutter test test/domain_models_test.dart` | 16 | 16 | 0 | 0 |
| Mobile — components | `flutter test test/components_test.dart` | 21 | 21 | 0 | 0 |
| Mobile — navigation | `flutter test test/navigation_test.dart` | 12 | 12 | 0 | 0 |
| Mobile — home screen | `flutter test test/home_screen_test.dart` | 14 | 14 | 0 | 0 |
| Mobile — fixture isolation | `flutter test test/fixture_isolation_test.dart` | 11 | 11 | 0 | 0 |
| Mobile — design tokens | `flutter test test/tokens_test.dart` | 8 | 8 | 0 | 0 |
| **Mobile total** | `flutter test` | **82** | **82** | **0** | **0** |
| Backend (regression) | `php artisan test` | 67 | 67 | 0 | 0 |
| Web (regression) | `npm test` | 29 | 29 | 0 | 0 |
| **Project total** | | **178** | **178** | **0** | **0** |

Mobile grew from 19 tests in Module 01 to 82.

## Static analysis

| Check | Command | Result |
| --- | --- | --- |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --output=none --set-exit-if-changed .` | **53 files, 0 changed** |
| Flutter web build | `flutter build web --release` | **✓ Built** |
| Backend style (regression) | `vendor/bin/pint --test` | **passed** |
| TypeScript (regression) | `npm run typecheck` | **0 errors** |

## Live-view verification

The Flutter app was **built and run**, and the rendered widget tree was inspected. Zero runtime
errors and zero console errors across every capture.

### Required states

| # | State | Screenshot | Inspected |
| --: | --- | --- | :-: |
| 1 | Home — new customer | `state-01-home-new-customer.png` | ✅ |
| 2 | Home — active journey | `state-02-home-active-journey.png` | ✅ |
| 3 | Home — active order | `state-03-home-active-order.png`, `state-03b-…-scrolled.png` | ✅ |
| 4 | Trips — empty | `tab-trips.png` | ✅ |
| 5 | Orders — empty | `tab-orders.png` | ✅ |
| 6 | Notifications — empty | `tab-alerts.png` | ✅ |
| 7 | Profile | `tab-profile.png` | ✅ |
| 8 | Offline banner | `state-08-offline-banner.png` | ✅ |
| 9 | Error state | `state-09-error.png` | ✅ |
| 10 | Loading / skeleton | asserted by widget test (`bySemanticsLabel('Loading your home screen')`) | ✅ |
| 11 | Future-feature placeholder | `state-11-coming-soon-placeholder.png` | ✅ |
| + | Long content | `state-11-long-content.png`, `…-scrolled.png` | ✅ |
| + | Dark mode | `home-dark.png` | ✅ |
| + | Large text | `home-large-text.png` | ✅ |
| + | Development harness | `dev-harness-open.png` | ✅ |

### Screen sizes rendered

| Profile | Logical size | Screenshot |
| --- | --- | --- |
| Compact | 320 × 640 | `home-320-compact.png` |
| Small Android | 360 × 800 | `home-360-android.png` |
| iPhone SE | 375 × 667 | `home-375-iphone-se.png` |
| iPhone 15 | 390 × 852 | `home-390-iphone15.png` |
| iPhone 15 Pro Max | 430 × 932 | `home-430-promax.png` |
| Tablet (graceful rendering only) | 768 × 1024 | `home-768-tablet.png` |

### Navigation matrix — all verified by test

| From | Action | Expected | Result |
| --- | --- | --- | --- |
| Home | tap Trips | Trips tab | ✅ |
| Trips | tap Orders | Orders tab | ✅ |
| Orders | tap Notifications | Alerts tab | ✅ |
| Notifications | tap Profile | Profile tab | ✅ |
| Profile | tap Home | Home tab | ✅ |
| Any | 60 rapid un-settled taps | index intact, no exception | ✅ |
| Orders | double-tap Orders | idempotent | ✅ |
| Profile | Android back | returns to Home, does not exit | ✅ |
| Home → Trips → Home | — | no re-fetch (`loadCount` stays 1) | ✅ |

## Android verification

**PENDING — environment unavailable.**

`flutter doctor` reports `✗ Android toolchain — Unable to locate Android SDK`, because
`dl.google.com` is denied by this environment's egress policy (HTTP 000 / CONNECT refused, verified
again in this run). No emulator was launched and no APK was built. Not claimed as passed.

## iOS verification

**PENDING — environment unavailable.**

`xcodebuild` is not present and cannot be: the host is Linux. No simulator was launched. Safe-area,
Dynamic Island, keyboard, gesture-navigation and orientation behaviour on iOS remain **unverified**.
The code uses `SafeArea` and the platform font resolves to San Francisco, but that is design intent,
not evidence.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Touch targets ≥ 48dp | Widget tests measure avatar and buttons | ✅ |
| Text scaling to 1.4x | Order card rendered at 1.4x, no overflow | ✅ |
| Type floors | `tokens_test.dart` | body ≥ 15sp |
| Contrast, light and dark | WCAG ratio computed in `tokens_test.dart` | ≥ 4.5:1 |
| Status not colour-alone | Every state asserted to carry a distinct icon | ✅ |
| Semantic labels | Avatar, chips, progress track, quick actions, route endpoints | ✅ |
| Reduced motion | Token-level durations + `FotgMotion` + skeleton stops looping | ✅ |
| Long content at 320dp | Persona D renders without a RenderFlex overflow | ✅ |

## Defects found and fixed

Eight, with root causes, in [13-known-issues.md](13-known-issues.md) (M02-B01 … M02-B08). Three were
found only by running the app: the harness crash, the 320dp greeting truncation and the full-width
button bug. One — the silent retry loop — was found by a test that counted repository calls rather
than asserting on pixels.

---

# Module 03 — test evidence

Full transcript: [`evidence/module-03-verification-run.txt`](evidence/module-03-verification-run.txt).
Screenshots: [`evidence/module-03/`](evidence/module-03/).

## Automated tests — 381 total, 381 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend — phone normalization | `php artisan test --filter=PhoneNormalizerTest` | 27 | 27 | 0 | 0 |
| Backend — OTP challenges | `--filter=OtpChallengeServiceTest` | 15 | 15 | 0 | 0 |
| Backend — registration token | `--filter=RegistrationTokenServiceTest` | 9 | 9 | 0 | 0 |
| Backend — customer auth service | `--filter=CustomerAuthServiceTest` | 12 | 12 | 0 | 0 |
| Backend — development sender | `--filter=LogOtpProviderTest` | 6 | 6 | 0 | 0 |
| Backend — OTP endpoints | `--filter=CustomerOtpTest` | 19 | 19 | 0 | 0 |
| Backend — registration endpoint | `--filter=CustomerRegistrationTest` | 11 | 11 | 0 | 0 |
| Backend — session endpoints | `--filter=CustomerSessionTest` | 11 | 11 | 0 | 0 |
| Backend — authorization boundary | `--filter=AuthorizationBoundaryTest` | 8 | 8 | 0 | 0 |
| Backend — auth logging | `--filter=AuthLoggingTest` | 5 | 5 | 0 | 0 |
| Backend — challenge pruning | `--filter=PruneOtpChallengesTest` | 4 | 4 | 0 | 0 |
| Backend — production guard (extended) | `--filter=ProductionConfigGuardTest` | 13 | 13 | 0 | 0 |
| **Backend total** | `php artisan test` | **197** | **197** | **0** | **0** |
| Mobile — auth flow | `flutter test test/auth_flow_test.dart` | 27 | 27 | 0 | 0 |
| Mobile — session lifecycle | `flutter test test/auth_session_test.dart` | 12 | 12 | 0 | 0 |
| Mobile — API client | `flutter test test/api_client_test.dart` | 13 | 13 | 0 | 0 |
| Mobile — auth models | `flutter test test/auth_models_test.dart` | 21 | 21 | 0 | 0 |
| **Mobile total** | `flutter test` | **155** | **155** | **0** | **0** |
| Web (regression) | `npm test` | 29 | 29 | 0 | 0 |
| **Project total** | | **381** | **381** | **0** | **0** |

Backend grew from 67 to 197; mobile from 82 to 155.

## Integration — no mocks

| Check | Command | Result |
| --- | --- | --- |
| Flutter network layer → Laravel → MySQL | `dart run tool/integration_smoke.dart` | **15 passed, 0 failed** |
| Same, returning-customer path (second run) | as above | **13 passed, 0 failed** |

The 15 assertions cover: masking in the API response, no code in the response, code delivery, a
wrong code rejected by the real server, the registration branch, the token not containing the phone
number, a session for the verified number, a real Sanctum token, `/customer/me` authenticating,
UUIDs rather than database keys, an unauthenticated 401, replay refusal, logout revocation, an
invalid number, and the resend cooldown.

## Static analysis

| Check | Command | Result |
| --- | --- | --- |
| Backend style | `vendor/bin/pint --test` | **passed** |
| Backend advisories | `composer audit` | **none** |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --set-exit-if-changed .` | **77 files, 0 changed** |
| Flutter web build | `flutter build web --release` | **✓ Built** |
| TypeScript (regression) | `npm run typecheck` | **0 errors** |

## Database verification — real MySQL

| Check | Query | Result |
| --- | --- | --- |
| No plaintext code in any column | `SUM(otp_hash REGEXP '^[0-9]{6}$')` | **0** |
| All codes hashed | `SUM(otp_hash REGEXP '^[0-9a-f]{64}$')` | **all rows** |
| Token stored as a hash of the plaintext | `token = SHA2(<plaintext>,256)` | **1** |
| Token never stored in plaintext | `token = <plaintext>` | **0** |
| Token carries one ability and an expiry | `abilities`, `expires_at` | `["customer"]`, set |
| Customer has no password | `password IS NULL` | **1** |
| Phone verified, email not | `phone_verified_at`, `email_verified_at` | set, NULL |
| Status is an ENUM, like `role` | `SHOW COLUMNS` | `enum('active','suspended','disabled','deleted')` |

## Log review — real application log

2,589 lines from a complete sign-up flow.

| Check | Occurrences |
| --- | --: |
| Any full test phone number | **0** |
| Any OTP written to the development channel | **0** |
| Phone numbers appearing masked (`+91 ••••••0002`) | every auth line |
| Token ids | `[REDACTED]` |

## Live-view verification

A Flutter **web release build with `FOTG_ENV=production`** — so no fixtures and no development
harness — served at `http://localhost:5173` and talking to the Laravel server at
`http://localhost:8000` against MySQL. Driven with Playwright through Flutter's DOM semantics tree.

Twenty screenshots in [`evidence/module-03/`](evidence/module-03/):

| State | File |
| --- | --- |
| Welcome (unauthenticated entry) | `state-01-welcome.png` |
| Phone entry, empty | `state-02-phone-empty.png` |
| Country picker sheet | `state-03-country-picker.png` |
| Phone entry, valid, action enabled | `state-04-phone-valid.png` |
| Code entry with live countdowns | `state-05-otp-empty.png` |
| Wrong code rejected by the real server | `state-06-otp-wrong-code.png` |
| Registration (new number) | `state-07-registration-empty.png` |
| Registration validation | `state-08-registration-validation.png` |
| Registration filled | `state-09-registration-filled.png` |
| Home, signed in, real identity | `state-10-home-signed-in.png` |
| Profile, real name and masked number | `state-11-profile-identity.png` |
| Profile scrolled | `state-12-profile-scrolled.png` |
| Sign-out confirmation | `state-13-sign-out-confirm.png` |
| Welcome after a deliberate sign-out | `state-14-welcome-after-signout.png` |
| Reload stays signed out | `state-15-reload-stays-signed-out.png` |
| Dark mode, welcome and phone | `variant-dark-*.png` |
| 320dp (smallest supported) | `variant-320-*.png` |
| 768dp tablet | `variant-768-welcome.png` |

Final run: **"No console errors, no page errors, all expected content present."**

## Android verification

**PENDING — environment unavailable.** `dl.google.com` is denied by the network egress policy, so
the Android SDK cannot be installed. See KI-001. Not claimed as passed.

## iOS verification

**iOS Runtime Verification = PENDING — environment unavailable.** No macOS host and no Xcode. See
KI-002. Not claimed as passed.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Semantic label on the code field | `Semantics(textField:)` asserted in the live semantics tree | ✅ |
| Semantic label on the country picker | Reads "Select country, India +91" | ✅ |
| Loading buttons announce state | `PrimaryButton`/`SecondaryButton` add ", loading" | ✅ |
| Touch targets ≥ 48dp | Picker sized to the full control height; `LinkAction` padded | ✅ |
| Text scaling | Rendered at 320dp with the app's 1.4x clamp; no overflow | ✅ |
| Errors are text, not colour alone | Every error carries an icon and a sentence | ✅ |
| Autofill without a permission | `AutofillHints.oneTimeCode`; no SMS-read permission requested | ✅ |
| Contrast, light and dark | Unchanged tokens; `tokens_test.dart` still passes | ≥ 4.5:1 |

## Defects found and fixed

Thirteen, with root causes, in [13-known-issues.md](13-known-issues.md) (M03-B01 … M03-B13). Five were
**critical or high**, and the two most serious were found by tests rather than by looking: the OTP
closure that hashed an undefined variable (nothing could ever verify) and the missing Sanctum trait
(no session could be issued). Two more were found only by running the app in a browser: the welcome
screen's layout assertion and the country picker swallowing the phone field.

## A note on the screenshots

CanvasKit fetches its fallback font from a CDN this environment blocks, so a font (LiberationSans)
was bundled temporarily to make text render and then removed. The committed `pubspec.yaml` bundles
no font and `FotgTypography.fontFamily` is `null`, as Module 01 requires.

LiberationSans has no regional-indicator glyphs, so the country flag appears as two empty boxes in
the screenshots. On iOS and Android the platform emoji font renders it; the dial code beside it is
the functional part and renders everywhere.
