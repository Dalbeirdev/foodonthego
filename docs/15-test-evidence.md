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

Twenty-two screenshots in [`evidence/module-03/`](evidence/module-03/):

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
| Provider outage (`OTP_SEND_FAILED` from the real server) | `state-16-provider-outage.png` |
| Offline — every API call aborted at the network layer | `state-17-offline.png` |

Final run: **"No console errors, no page errors, all expected content present."**

The last two states are the failure paths, driven the same way:

- **Provider outage** — `OTP_SIMULATE_PROVIDER_FAILURE=true` on the real backend, so the server
  genuinely accepted the request, failed to deliver, invalidated the challenge and returned
  `OTP_SEND_FAILED` (503). The screen shows *"We couldn't send your code. Please try again in a
  moment."* — not a success, and not a stack trace.
- **Offline** — every `/api/v1/**` request aborted at the network layer with
  `internetdisconnected`, which is the traveller-in-a-tunnel case rather than a mocked error. The
  screen shows *"No connection. Check your signal and try again."*

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

---

# Module 04 — test evidence

Full transcript: [`evidence/module-04-verification-run.txt`](evidence/module-04-verification-run.txt).
Screenshots: [`evidence/module-04/`](evidence/module-04/).

## Automated tests — 549 total, 549 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend — address service | `php artisan test --filter=CustomerAddressServiceTest` | 16 | 16 | 0 | 0 |
| Backend — profile service | `--filter=CustomerProfileServiceTest` | 10 | 10 | 0 | 0 |
| Backend — formatter, postcodes, types | `--filter=AddressSupportTest` | 9 | 9 | 0 | 0 |
| Backend — profile endpoints | `--filter=ProfileApiTest` | 19 | 19 | 0 | 0 |
| Backend — address endpoints | `--filter=AddressApiTest` | 25 | 25 | 0 | 0 |
| Backend — ownership / IDOR | `--filter=AddressOwnershipTest` | 14 | 14 | 0 | 0 |
| Backend — address logging | `--filter=AddressLoggingTest` | 6 | 6 | 0 | 0 |
| **Backend total** | `php artisan test` | **296** | **296** | **0** | **0** |
| Mobile — edit profile | `flutter test test/profile_edit_test.dart` | 17 | 17 | 0 | 0 |
| Mobile — saved addresses | `flutter test test/saved_addresses_test.dart` | 27 | 27 | 0 | 0 |
| Mobile — address models | `flutter test test/address_models_test.dart` | 21 | 21 | 0 | 0 |
| Mobile — account isolation | `flutter test test/account_isolation_test.dart` | 3 | 3 | 0 | 0 |
| **Mobile total** | `flutter test` | **224** | **224** | **0** | **0** |
| Web (regression) | `npm test` | 29 | 29 | 0 | 0 |
| **Project total** | | **549** | **549** | **0** | **0** |

Backend grew from 197 to 296; mobile from 155 to 224.

## Integration — no mocks

| Check | Command | Result |
| --- | --- | --- |
| Flutter network layer → Laravel → MySQL | `dart run tool/profile_addresses_smoke.dart` | **24 passed, 0 failed** |
| Module 03 regression, same live backend | `dart run tool/integration_smoke.dart` | **13 passed, 0 failed** |

The 24 assertions are listed verbatim in the transcript. Ten of them are security assertions: the
verified number surviving a `PATCH` that tries to change it, an email change that never claims to be
verified, the four IDOR attempts (read, update, delete, set-default) against a second real account,
that account's address being byte-identical afterwards, a create that names another customer landing
on the caller, an unauthenticated call reaching nothing, and a revoked session reaching nothing.

## Static analysis

| Check | Command | Result |
| --- | --- | --- |
| Backend style | `vendor/bin/pint --test` | **passed** |
| Backend advisories | `composer audit` | **none** |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --set-exit-if-changed .` | **93 files, 0 changed** |
| Flutter web build | `flutter build web --release` | **✓ Built** |
| TypeScript (regression) | `npm run typecheck` | **0 errors** |

## Database verification — real MySQL

| Check | Query | Result |
| --- | --- | --- |
| One default per customer is a *database* rule | direct `INSERT` of a second default | **ERROR 1062, duplicate key** |
| No customer holds two defaults | `GROUP BY customer_id HAVING COUNT(*)>1` where `is_default=1` | **empty set** |
| Generated column behaves | `default_for_customer` | customer id on the default row, `NULL` elsewhere |
| Coordinates are not invented | `latitude IS NULL` | **all rows** |
| Verified phone unchanged by tampering | `phone_e164` after a `PATCH` carrying a new one | **unchanged** |
| Role and status unchanged by tampering | `role`, `status` | `customer`, `active` |
| A new email is not verified | `email_verified_at` | **NULL** |
| The victim's address untouched after four IDOR attempts | full row compare | **identical** |
| No duplicate rows from repeated submission | `GROUP BY customer_id, formatted_address` | **empty set** |
| Foreign key is explicit | `SHOW CREATE TABLE` | `ON DELETE RESTRICT` (KI-009) |

## Log review — real application log

1,634 lines from a complete profile-and-address session including the IDOR attempts.

| Check | Occurrences |
| --: | --: |
| Any saved address line, city or postcode | **0** |
| Any customer email address | **0** |
| Any full phone number | **0** |
| `address.access_denied` lines (the IDOR attempts) | **4** |

Every operational line names the event, the record uuid and the actor uuid — and nothing about where
anybody lives. `profile.updated` logs the *names* of the fields that changed, never their values.

## Live-view verification

A Flutter **web release build with `FOTG_ENV=production`** — no fixtures, no development harness —
served at `http://localhost:5173`, talking to Laravel at `http://localhost:8000` against MySQL.
Driven with Playwright through Flutter's DOM semantics tree.

Twenty-four screenshots in [`evidence/module-04/`](evidence/module-04/):

| State | File |
| --- | --- |
| Profile, signed in, real identity | `state-01-profile.png` |
| Edit profile — phone rendered read-only | `state-02-edit-profile.png` |
| Profile validation failure | `state-03-profile-validation.png` |
| Profile saved (after the server confirmed) | `state-04-profile-saved.png` |
| Saved addresses — empty state | `state-05-addresses-empty.png` |
| Add address form | `state-06-add-address-form.png` |
| Add address validation | `state-07-add-address-validation.png` |
| Add address filled | `state-08-add-address-filled.png` |
| First address, automatically the default | `state-09-address-home-default.png` |
| List with two addresses | `state-10-addresses-populated.png` |
| Other type with a custom label | `state-11-add-other-custom-label.png` |
| All three types listed | `state-12-addresses-three-types.png` |
| Row action menu | `state-13-row-menu.png` |
| Default moved to another address | `state-14-default-changed.png` |
| Edit an existing address | `state-15-edit-address.png` |
| Delete confirmation | `state-16-delete-confirmation.png` |
| Offline — every API call aborted at the network layer | `state-17-addresses-offline.png` |
| Dark mode, profile and addresses | `variant-dark-*.png` |
| 320dp (smallest supported), three screens | `variant-320-*.png` |
| 768dp tablet | `variant-768-addresses.png` |
| Large text (1.4x clamp) | `variant-large-text-addresses.png` |

Final run: **"No console errors, no page errors, all expected content present."**

Every state above is the real API's answer. The success states were captured *after* the server
returned 200 — no state in this module is rendered optimistically, and the transcript's database
section shows the same rows the screenshots show.

## Account isolation

Signed in as Rahul, saved addresses, signed out, signed in as Ananya through the real OTP flow:
Ananya's list is Ananya's, with no frame of Rahul's data in between. This is not a cleanup step that
could be forgotten — `AddressesController` watches the auth session, so ending the session disposes
the state. Pinned by `test/account_isolation_test.dart`, which drives the real sign-in flow rather
than re-mounting the widget tree.

## Android verification

**PENDING — environment unavailable.** `dl.google.com` is denied by the network egress policy, so the
Android SDK cannot be installed. See KI-001. Not claimed as passed.

## iOS verification

**iOS Runtime Verification = PENDING — environment unavailable.** No macOS host and no Xcode. See
KI-002. Not claimed as passed.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Read-only phone announces why | `LockedPhoneField` reads the number and "verified, cannot be changed" | ✅ |
| Row menu is identifiable | Tooltip reads "Options for Home", not a bare "Edit" (M04-B06) | ✅ |
| Default badge is a word, not a colour | Renders the text "DEFAULT" | ✅ |
| Touch targets ≥ 48dp | Row menu button and type selector sized to the control height | ✅ |
| Text scaling | Rendered at the app's 1.4x clamp; no overflow | ✅ |
| 320dp | Type labels drop their icons rather than wrapping mid-word (M04-B05) | ✅ |
| Errors are text, not colour alone | Every field error carries a sentence | ✅ |
| Destructive action is confirmed | Delete opens a dialog naming the address | ✅ |
| Contrast, light and dark | Unchanged tokens; `tokens_test.dart` still passes | ≥ 4.5:1 |

## Defects found and fixed

Eight, with root causes, in [13-known-issues.md](13-known-issues.md) (M04-B01 … M04-B08). One was
critical: both forms were built on a lazy `ListView`, so a field scrolled out of view was never
registered with its `Form` and validation silently skipped it — an invalid address could be
submitted. Two were found only by running the app in a browser (the primary action sitting under the
bottom navigation bar, and the row menu's misleading tooltip), and two by running the migration
against real MySQL rather than SQLite.

---

# Module 05 — test evidence

Full transcript: [`evidence/module-05-verification-run.txt`](evidence/module-05-verification-run.txt).
Screenshots: [`evidence/module-05/`](evidence/module-05/).

## Automated tests — 707 total, 707 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend — journey lifecycle | `php artisan test --filter=TripServiceTest` | 29 | 29 | 0 | 0 |
| Backend — journey endpoint value object | `--filter=JourneyEndpointTest` | 12 | 12 | 0 | 0 |
| Backend — journey endpoints | `--filter=TripApiTest` | 34 | 34 | 0 | 0 |
| Backend — ownership / IDOR | `--filter=TripOwnershipTest` | 13 | 13 | 0 | 0 |
| Backend — journey logging | `--filter=TripLoggingTest` | 7 | 7 | 0 | 0 |
| **Backend total** | `php artisan test` | **391** | **391** | **0** | **0** |
| Mobile — journey models and time | `flutter test test/trip_models_test.dart` | 25 | 25 | 0 | 0 |
| Mobile — the Trips screen | `flutter test test/trips_screen_test.dart` | 19 | 19 | 0 | 0 |
| Mobile — the planner | `flutter test test/trip_planner_test.dart` | 18 | 18 | 0 | 0 |
| Mobile — account isolation | `flutter test test/account_isolation_test.dart` | 6 | 6 | 0 | 0 |
| **Mobile total** | `flutter test` | **287** | **287** | **0** | **0** |
| Web (regression) | `npm test` | 29 | 29 | 0 | 0 |
| **Project total** | | **707** | **707** | **0** | **0** |

Backend grew from 296 to 391; mobile from 224 to 287.

## Integration — no mocks

| Check | Command | Result |
| --- | --- | --- |
| Flutter network layer → Laravel → MySQL | `dart run tool/trip_planner_smoke.dart` | **30 passed, 0 failed** |
| Module 04 regression, same live backend | `dart run tool/profile_addresses_smoke.dart` | **24 passed, 0 failed** |
| Module 03 regression, same live backend | `dart run tool/integration_smoke.dart` | **13 passed, 0 failed** |

The 30 assertions are listed verbatim in the transcript. Nine are security
assertions, including the four-way journey IDOR matrix, the attempt to plan a
journey from another customer's saved address, an unauthenticated call and a
revoked session.

One assertion — "a partial update leaves untouched fields alone in the database"
— exists because of a defect the responses hid. It re-reads the journey rather
than trusting the update's own answer.

## Static analysis

| Check | Command | Result |
| --- | --- | --- |
| Backend style | `vendor/bin/pint --test` | **passed** |
| Backend advisories | `composer audit` | **none** |
| Dart analyzer | `flutter analyze --fatal-infos` | **No issues found** |
| Dart format | `dart format --set-exit-if-changed .` | **106 files, 0 changed** |
| Flutter web build | `flutter build web --release` | **✓ Built** |
| TypeScript (regression) | `npm run typecheck` | **0 errors** |

## Database verification — real MySQL

| Check | Query | Result |
| --- | --- | --- |
| No coordinate was invented | any of the four lat/lng columns not null | **0 rows** |
| Nothing stored half a location | `(lat IS NULL) <> (lng IS NULL)` | **0 rows** |
| No journey ends where it starts | formatted addresses compared | **0 rows** |
| A partial update left the rest alone | `traveller_count` after a note-only edit | **3**, the value the earlier edit set |
| The endpoint snapshot survived an address edit | `origin_city` after the address moved to Mumbai | **New Delhi** |
| The victim's journey untouched after four attacks | full row compare | **identical** |
| Status is a two-case ENUM | `SHOW COLUMNS` | `enum('PLANNED','CANCELLED')` |
| Provenance links are nullable and SET NULL | `SHOW CREATE TABLE` | both `*_address_id` FKs |
| Customer FK is explicit | `SHOW CREATE TABLE` | `ON DELETE RESTRICT` |

## Log review — real application log

5,421 lines, covering 209 journey creations, 23 updates, 27 cancellations and 45
denied accesses.

| Check | Occurrences |
| --- | --: |
| Any journey city, area or address | **0** |
| Any note or cancellation reason a customer typed | **0** |
| Any departure or arrival time | **0** |
| Any full phone number | **0** |

An update logs the *names* of the fields that changed. The eight columns of an
endpoint collapse to the single name `"destination"`, so the log records that the
destination changed without recording where to. When somebody's home will be
empty is as sensitive as where it is, and neither is in the file.

## Live-view verification

A Flutter **web release build with `FOTG_ENV=production`** — no fixtures, no
development harness — served at `http://localhost:5173`, talking to Laravel at
`http://localhost:8000` against MySQL. Driven with Playwright through Flutter's
DOM semantics tree.

Twenty-four screenshots in [`evidence/module-05/`](evidence/module-05/):

| State | File |
| --- | --- |
| Home, signed in, no journey planned | `state-01-home-no-journey.png` |
| Trips — empty state | `state-02-trips-empty.png` |
| The planner, empty | `state-03-planner-empty.png` |
| Planner validation — both ends required | `state-04-planner-validation.png` |
| The place picker | `state-05-place-picker.png` |
| A place typed into the picker | `state-06-place-typed.png` |
| The planner, filled | `state-07-planner-filled.png` |
| Journey saved (after the server confirmed) | `state-08-journey-saved.png` |
| Journey detail | `state-09-journey-detail.png` |
| Two journeys, soonest first | `state-10-two-journeys.png` |
| The row menu | `state-11-row-menu.png` |
| Editing a journey | `state-12-edit-journey.png` |
| Cancel confirmation, with a reason field | `state-13-cancel-confirmation.png` |
| After cancelling | `state-14-after-cancelling.png` |
| The Cancelled scope | `state-15-cancelled-scope.png` |
| The Past scope, empty | `state-16-past-empty.png` |
| Home with the real next journey | `state-17-home-next-journey.png` |
| Offline — every API call aborted at the network layer | `state-18-trips-offline.png` |
| Dark mode, trips and home | `variant-dark-*.png` |
| 320dp (smallest supported), trips and planner | `variant-320-*.png` |
| 768dp tablet | `variant-768-trips.png` |
| A taller phone | `variant-420-tall.png` |

Final run: **"All expected content present."**

**Console errors, in full and unedited:** two font fetches to
`fonts.gstatic.com` refused by this environment's egress policy — the same
CanvasKit limitation the Module 04 run recorded — and two API requests aborted
because the offline state was being driven deliberately. There are no
application errors and no page errors.

Every state above is the real API's answer. The success states were captured
*after* the server returned 200, and the transcript's database section shows the
same rows the screenshots show.

## Account isolation

Signed in as Rahul, planned a journey, signed out, signed in as Ananya through
the real OTP flow: her journeys are hers, with no frame of his. Structural rather
than a cleanup step — `TripsController` watches the auth session, so ending it
disposes the state. Pinned by three tests in `account_isolation_test.dart` that
drive the real sign-in flow rather than re-mounting the widget tree.

## Android verification

**PENDING — environment unavailable.** `dl.google.com` is denied by the network
egress policy, so the Android SDK cannot be installed. See KI-001. Not claimed as
passed.

## iOS verification

**iOS Runtime Verification = PENDING — environment unavailable.** No macOS host
and no Xcode. See KI-002. Not claimed as passed.

## Accessibility evidence

| Check | Method | Result |
| --- | --- | --- |
| Place and time rows name themselves | `Semantics(button:, label:)` carrying field, value and error (M05-B05) | ✅ |
| Row menu identifies its journey | Tooltip reads "Options for New Delhi → Jaipur" | ✅ |
| Cancelled and departed are words, not colours | Renders "CANCELLED" / "Departed" | ✅ |
| A read-only journey says why | Notice above the missing actions | ✅ |
| Traveller stepper buttons are labelled | "One more traveller" / "One fewer traveller" | ✅ |
| Scope labels never break mid-word at 320dp | Test at 320dp; horizontal scroll below it | ✅ |
| The primary action is reachable at 320×568 | Pinned action; empty state shrinks its motif (M05-B03) | ✅ |
| Destructive action is confirmed | Dialog naming what happens to the journey | ✅ |
| Contrast, light and dark | Unchanged tokens; `tokens_test.dart` still passes | ≥ 4.5:1 |

## Defects found and fixed

Five, with root causes, in [13-known-issues.md](13-known-issues.md) (M05-B01 …
M05-B05). Four were high severity. Two were found by inspection methods rather
than by tests: the unreachable empty-state action by driving a real browser at
320×568, and the silently reset traveller count by reading MySQL after the
integration run — the assertions had passed.
