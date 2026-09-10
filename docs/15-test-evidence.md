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

This module was **reworked**: a first pass built a journey planner from the
project roadmap rather than from the specification, and was replaced. Everything
below describes the module as it now stands, and every number was re-measured
after the rework.

## Automated tests — 724 total, 724 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend | `php artisan test` | 408 | 408 | 0 | 0 |
| Flutter | `flutter test` | 312 | 312 | 0 | 0 |
| Web shells | `npm test` | 4 | 4 | 0 | 0 |

Static checks: `./vendor/bin/pint --test` → passed. `flutter analyze` → no
issues. `dart format` → clean.

### The suites this module added or rewrote

| Suite | Tests | What it establishes |
| --- | --: | --- |
| `TripServiceTest` | 26 | Endpoint resolution, coordinate validation, the (0, 0) sentinel, the same-place rule, the open limit |
| `TripApiTest` | 30 | The endpoints as a client sees them; that no DELETE exists and no route field is ever returned |
| `TripOwnershipTest` | 14 | The IDOR matrix, including creating a trip from another customer's saved address |
| `TripLoggingTest` | 8 | That no place, coordinate or search query reaches the log file on disk |
| `PlaceApiTest` | 14 | Caching by query alone, session tokens, one opaque failure code, authentication |
| `PlaceProviderTest` | 18 | All three providers; the Google adapter against a stubbed transport |
| `ProductionConfigGuardTest` | 15 | Including: an unconfigured place provider blocks a production boot |
| `trip_models_test.dart` | 22 | Parsing, the wire shape, the same-place rule, and that no payload carries a customer id or a route field |
| `trip_planner_test.dart` | 20 | The whole planner, plus the accessibility of every labelled row |
| `trips_screen_test.dart` | 13 | Two scopes, four states, discarding, and that no row shows a distance |
| `place_search_test.dart` | 13 | Debounce, the session-token lifecycle, and the stale-answer race |
| `location_permission_test.dart` | 15 | Every permission outcome, contextual asking, and a device that never answers |
| `address_location_test.dart` | 4 | Locating a saved address; an unlocated one sends no coordinates |

## Integration — no mocks, no fakes, no stubs

`dart run tool/trip_planner_smoke.dart` drives this app's own `ApiClient` and
repositories against a running Laravel server, real MySQL and real Redis.

**31 assertions, 31 passed, 0 failed.**

It walks: an empty account · place search, one-letter refusal, details resolving
to a real position, reverse geocoding keeping the caller's coordinates, an
impossible coordinate refused, unauthenticated lookup refused · a trip created
from a saved address and a searched place · that no route is calculated and none
is claimed · that the saved address is snapshotted (edited **and** deleted, the
trip unmoved) · that the payload contains no distance, duration, polyline, ETA,
customer id or address id · same-place, out-of-range and (0, 0) refusals · a
mass-assignment payload carrying `customer_id`, `id`, `uuid`, `status`,
`route_status`, `distance`, `duration`, `eta`, `polyline` and `cancelled_at`,
all ignored · four attacks on Ananya from Rahul's session, including creating a
trip from her saved address · that no refusal leaks a word of her data · that
missing and forbidden are indistinguishable · that the list filter the client
sends is one the server actually reads · discarding, and its refusal to happen
twice · an unauthenticated call · a revoked session.

## Database verification

Read directly with `mysql`, not through the API.

```
status  route_status    origin_source_type  origin_name  origin_latitude  destination_name
CANCELLED  NOT_CALCULATED  CURRENT_LOCATION  New Delhi   28.5590000       Jaipur International Airport
ROUTE_PENDING  NOT_CALCULATED  SAVED_ADDRESS  Office     28.4949000       Sector 17 Plaza
```

- `route_status` is `NOT_CALCULATED` on **every** row. No trip claims a route.
- `SHOW COLUMNS FROM trips` lists 30 columns and **none** of them is a distance,
  a duration, a polyline or an ETA.
- Coordinates are real published positions, stored at seven decimal places, with
  no zeros and no (0, 0).
- `origin_saved_address_id` is `NULL` on the trip whose address was deleted — the
  `ON DELETE SET NULL` provenance rule — and the trip's own copy of the address
  is unchanged.

## Log verification

Read from `storage/logs/foodonthego-2026-09-04.log` after a full round of
operations.

Present: `trip.created`, `trip.discarded`, `trip.access_denied`,
`places.lookup_failed`, each with a request id, the actor's uuid, the trip's
uuid, the source kinds and `route_status`.

Absent — eleven needles grepped, **zero hits**: `Jaipur`, `Green Park`,
`Hawa Mahal`, `Sector 17`, `Gurugram`, `Cyber City`, `28.5590`, `77.2070`,
`26.8242`, `AIza`, and the test phone numbers.

## Live-view verification — 28 states

A `production` Flutter web build (no fixtures, no development harness) against
the running API and database, driven in headless Chromium through the DOM
semantics tree, with the browser's own geolocation standing in for a handset's.

| # | State | File |
| --: | --- | --- |
| 01 | Home, with the planner call to action | `state-01-home.png` |
| 02 | The planner, both ends empty | `state-02-planner-empty.png` |
| 03 | The picker: current location, saved addresses, search | `state-03-picker-origin.png` |
| 04 | Origin filled from a real device fix | `state-04-origin-current-location.png` |
| 05 | Search results, typed a letter at a time | `state-05-search-results.png` |
| 06 | A search that matches nothing | `state-06-search-no-results.png` |
| 07 | Both ends chosen | `state-07-both-ends-chosen.png` |
| 08 | Swapped | `state-08-swapped.png` |
| 09 | The created journey — "Route not calculated yet" | `state-09-journey-created.png` |
| 10 | The journeys list | `state-10-trips-list.png` |
| 11 | The same place at both ends, refused before sending | `state-11-same-place-refused.png` |
| 12 | One end cleared | `state-12-cleared-origin.png` |
| 13 | Nothing chosen: the missing end is named | `state-13-origin-required.png` |
| 14 | The row menu | `state-14-row-menu.png` |
| 15 | The discard confirmation | `state-15-discard-dialog.png` |
| 16 | After discarding | `state-16-after-discard.png` |
| 17 | The discarded scope | `state-17-discarded-scope.png` |
| 18 | An address with no location | `state-18-address-not-located.png` |
| 19 | The address locator — search only | `state-19-address-locator.png` |
| 20 | The address located | `state-20-address-located.png` |
| 21a | Asking the device | `state-21a-locating.png` |
| 21b | The device never answered — and the screen said so | `state-21b-location-timed-out.png` |
| 22 | The place provider down | `state-22-search-failure.png` |
| 23 | Offline | `state-23-offline-search.png` |
| 24 | 320dp | `state-24-320-planner.png` |
| 25 | 360dp | `state-25-360-planner.png` |
| 26 | 430dp | `state-26-430-planner.png` |
| 27 | Dark mode | `state-27-dark-picker.png` |

The run asserts on every state: no console errors, no page errors, and **no
"km", no "min", no "ETA" anywhere**. It finished with *No problems found*.

### Permission outcomes, and where each was exercised

| Outcome | Browser | Widget test |
| --- | :-: | :-: |
| Granted | ✅ real geolocation | ✅ |
| Granted but coarse | ➖ | ✅ |
| Denied | ➖ | ✅ |
| Denied permanently | ➖ | ✅ |
| Services switched off | ➖ | ✅ |
| Timed out | ✅ pending prompt | ✅ |
| Platform failure | ➖ | ✅ |
| Never answers at all | ✅ | ✅ |

A browser can produce two of these honestly; the rest need a state a browser will
not enter on request, so they are driven through a fake `LocationService` that
returns each outcome in turn. That is stated here rather than implied by a tick.

## Defects found and fixed

Eleven, with root causes, in [13-known-issues.md](13-known-issues.md)
(M05-B01 … M05-B11). Six were high severity.

Four were found by inspection methods rather than by tests, and could not have
been found any other way:

- **B08** — the picker's labelled rows could not be activated by assistive
  technology. Only visible when driving the built app through the semantics tree;
  every widget test tapped by widget, which works regardless.
- **B09** — "Finding you…" never resolved when a browser left the permission
  prompt pending. `geolocator`'s own `timeLimit` does not fire there.
- **B10** — every list filter was ignored, because the client sent `?scope=` and
  the server reads `?status=`. An unknown query parameter is *ignored*, so the
  request looked healthy and every fake-backed test still passed.
- **B11** — every journey started from a place called "Use my current location".
  Found by reading the `trips` rows, which no API assertion would have
  questioned.

## What is pending, and why

- **Live Google Places verification = PENDING — environment unavailable.** No API
  key here, and the provider answers 403 without one. The adapter is verified
  against a stubbed HTTP transport. (KI-010, M05-037.)
- **Android runtime verification = PENDING — environment unavailable.** (KI-001.)
- **iOS runtime verification = PENDING — environment unavailable.** (KI-002.)

None of the three is a code failure, and none is reported as a pass.

---

# Module 06 — Maps, Route Calculation, Distance & Travel Time

Full transcript: [`evidence/module-06-verification-run.txt`](evidence/module-06-verification-run.txt).
Screenshots: [`evidence/module-06/`](evidence/module-06/).

## Automated tests — 938 total, 938 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend | `php artisan test` | 527 | 527 | 0 | 0 |
| Flutter | `flutter test` | 382 | 382 | 0 | 0 |
| Web shells and `@fotg/ui` | `npm test` | 29 | 29 | 0 | 0 |

Static checks: `./vendor/bin/pint --test` → passed. `flutter analyze` → no
issues. `dart format --set-exit-if-changed` → clean.

### The suites this module added

| Suite | Tests | What it pins |
| --- | --: | --- |
| `PolylineCodecTest` | 8 | Google's own worked example; refusal of empty, truncated, over-long and out-of-alphabet geometry |
| `RouteProviderTest` | 28 | The Routes v2 request (key header, six-field mask, travel mode, traffic preference, alternatives), the `staticDuration`/`duration` traffic mapping, `"16200s"` parsing, timeouts, 429, malformed bodies, and both non-Google providers |
| `RouteValidatorTest` | 15 | What a response must satisfy before it is stored |
| `RouteCalculationServiceTest` | 23 | Freshness window, concurrency lock, invalidation, transactional persistence, each failure kind, and recovery |
| `TripRouteApiTest` | 26 | The three endpoints as a client sees them, including that `GET` never calculates |
| `TripRouteOwnershipTest` | 9 | The route IDOR matrix |
| `RouteLoggingTest` | 7 | Reads the log file on disk: events present, geometry and coordinates absent |
| `route_models_test.dart` | 25 | A route with no distance, duration or geometry does not construct; crossed bounds are dropped; formatting |
| `route_controller_test.dart` | 16 | Mostly counting provider calls: opening twice calculates once, a rebuild calculates never, a refresh asks again |
| `route_screen_test.dart` | 29 | Every state, the alternatives, the layout at 320dp, long names, large text |

## Integration — no mocks, no fakes, no stubs

`dart run tool/route_smoke.dart` drives this app's own `ApiClient` and
`ApiRouteRepository` against a running Laravel server and a real MySQL database.
**21 assertions, 21 passed.**

It plans a journey through the Module 05 flow, calculates a route, decodes the
geometry and checks it runs between the two places, proves the freshness window
by counting provider calls, moves an endpoint underneath a stored route to prove
invalidation, sends a tamper payload carrying `distance_meters: 1`,
`duration_seconds: 1` and `route_status: READY`, and runs the route IDOR matrix
across two real accounts.

It prints what the configured provider returned rather than asserting against
numbers baked into the test:

```
── what the configured provider returned ──
   provider          : development
   real provider     : false
   routes returned   : 1
   distance (metres) : 235526
   duration (seconds): 14103
   traffic (seconds) : not supplied
   summary           : Development stand-in — not a real route
   polyline points   : 25
```

and, because that provider returned one route:

```
NOTE  Alternative-route runtime test = NOT APPLICABLE — the configured
      provider returned a single route for this journey.
```

No second route was fabricated in order to have something to select.

### Regression, same live backend

| Run | Assertions | Result |
| --- | --: | --- |
| `tool/integration_smoke.dart` (Module 03) | 13 | 13 passed, 0 failed |
| `tool/profile_addresses_smoke.dart` (Module 04) | 24 | 24 passed, 0 failed |
| `tool/trip_planner_smoke.dart` (Module 05) | 31 | 31 passed, 0 failed |

## Database verification

Read back directly from MySQL after the runs:

| Check | Result |
| --- | --- |
| Routes stored | 55 |
| Rows with `is_selected = 1` | 55 |
| Distinct trips with a selection | 55 |
| Trips with more than one selected route | **0** |
| Routes with a zero or negative distance, duration, or empty geometry | **0** |
| Routes whose traffic duration is below the base duration | **0** |
| Routes with no endpoint fingerprint | **0** |
| Trips `READY` with no routes | **0** |
| Orphan routes | **0** |
| `trip_routes_one_selected_per_trip` unique index present | yes |

Every stored route carries a positive distance, a positive duration and real
geometry, and the one-selected-route invariant holds at the storage layer rather
than only in the service that writes it.

## Log verification

Eight route events were recorded during the runs: `route.calculated`,
`route.calculation_failed`, `route.invalidated`, `route.no_route`,
`route.provider_rejected`, `route.provider_unconfigured`,
`route.response_rejected`, `route.selection_denied`.

The privacy sweep greps the day's application log for thirteen needles — both
place names, the four test coordinates, `encoded_polyline`, `polyline`, the
polyline prefix `_p~`, the `AIza` key prefix and the test phone numbers — and
finds **0 hits for every one of them**. What is logged is the trip uuid, the
actor uuid, the provider and the outcome.

## Live-view verification — 20 states

A **release** web build (`--dart-define=FOTG_ENV=production`) served over HTTP and
driven in headless Chromium through Flutter's DOM semantics tree, against the
real API and the real database, with the browser's geolocation standing in for a
handset's.

| # | State | What it establishes |
| --: | --- | --- |
| 01 | Journey without a route | "Route not calculated yet"; nothing claims a distance |
| 02 | Route ready | Distance and travel time from a real calculation |
| 03 | Map unavailable | The full summary and both place names survive without a map |
| 04 | Development-provider notice | A non-real route says so, on screen |
| 05 | Travel-time wording | "Driving time from the route"; "Calculated just now"; **no "ETA" anywhere** |
| 06 | No recentre without a map | A control that cannot act is not offered |
| 07 | Recalculated | An explicit refresh asks again |
| 08 | Trip detail | The figures reached the detail screen |
| 09 | Journeys list | And the list |
| 10 | Home, after a cold reload | And the home card: "3 hr 56 min · 237 km" |
| 11 | No route | The provider's considered answer, with **no** retry |
| 12 | Timeout | "That took too long", with a retry |
| 13 | Rate limited | "Route planning is busy", with a retry |
| 14 | Provider outage | "We couldn't work out your route", with a retry |
| 15 | Offline with a stored route | The route is kept, and labelled as the last calculated one |
| 16 | Offline with nothing | An offline state, and no empty map frame |
| 17–19 | 320 / 360 / 430dp | The route screen at every supported width |
| 20 | Dark mode | The whole screen in the dark theme |

The run asserts throughout that no screen shows the word **"ETA"**, and that no
console error or page error occurs outside the four deliberately injected
provider failures.

Module 05's live run was re-driven against the same build as a regression: 28
states, no problems.

## Defects found and fixed

Eight, all closed, all in [13-known-issues.md](13-known-issues.md):

- **B01** — a test that could not fail, because Laravel caches a resolved
  controller on the `Route` object across requests in one test process.
- **B02** — a successful calculation reported as a failure when an unrelated
  refresh failed.
- **B03** — a Module 03 defect this module's tests exposed: `AuthController.restore()`
  wrote state after two async gaps with no disposal check.
- **B04, B05, B08** — three layout defects at 320–390dp, the last of which put the
  development-provider banner on top of the place names.
- **B06** — a Module 01 defect: an unauthenticated request without
  `Accept: application/json` was answered **500** instead of 401. Four modules of
  JSON-speaking tests never saw it.
- **B07** — a recentre control offered where there was no map to recentre.

Two further defects were found in the verification harness itself and are
recorded in the same place: `Playwright`'s `hasText` matches case-insensitively,
so "the screen never says ETA" was matching "route d**eta**ils"; and Flutter
renders a semantic heading as an `<h2>`, so "home shows *Your journey*" could
never have passed. Both assertions could only ever have produced the wrong
answer.

## What is pending, and why

- **Live Google Routes API verification = PENDING — environment unavailable.** No
  key here, and every alternative routing provider is blocked by the egress
  policy. The adapter is verified against a stubbed HTTP transport by 28 tests.
  (KI-012, M06-051.)
- **Live map SDK render = PENDING — environment unavailable.** No Maps key, no
  Android SDK, no macOS host, so every screenshot shows the documented
  map-unavailable state. (KI-011, M06-053.)
- **Alternative-route runtime test = NOT APPLICABLE for this test response.** The
  configured provider returned one route. (M06-052.)
- **Android runtime verification = PENDING — environment unavailable.** (KI-001.)
- **iOS runtime verification = PENDING — environment unavailable.** (KI-002.)

None is a code failure, and none is reported as a pass.

---

# Module 07 — Restaurant Discovery Along the Selected Route

Full transcript: [`evidence/module-07-verification-run.txt`](evidence/module-07-verification-run.txt).
Screenshots: [`evidence/module-07/`](evidence/module-07/).

## Automated tests — 1 120 total, 1 120 passed, 0 failed, 0 skipped

| Suite | Command | Tests | Passed | Failed | Skipped |
| --- | --- | --: | --: | --: | --: |
| Backend | `php artisan test` | 635 | 635 | 0 | 0 |
| Flutter | `flutter test` | 456 | 456 | 0 | 0 |
| Web shells and `@fotg/ui` | `npm test` | 29 | 29 | 0 | 0 |

Static checks: `./vendor/bin/pint --test` → passed. `flutter analyze` → no
issues. `dart format --set-exit-if-changed` → clean.

### The suites this module added

| Suite | Tests | What it pins |
| --- | --: | --- |
| `RouteGeometryTest` | 11 | Projection against distances checkable by hand: perpendicular rather than nearest-vertex, ordering along the route, behind-origin, beyond-destination, self-crossing, and that simplification cannot move a restaurant across the corridor |
| `RestaurantEligibilityTest` | 13 | Every rule, and **all 72 combinations** asserting the SQL scope and the service never disagree |
| `RestaurantAvailabilityTest` | 13 | Restaurant-local timezone, overnight windows, split service days, and that a paused restaurant is never reported as open |
| `RestaurantDiscoveryServiceTest` | 22 | The pipeline with a provider the test controls |
| `DiscoveryRankingTest` | 11 | The score as product statements — which of two restaurants wins, and why |
| `TripRestaurantApiTest` | 17 | The endpoint as a client sees it, including the private-column sweep |
| `TripRestaurantOwnershipTest` | 6 | The discovery IDOR matrix |
| `DiscoveryLoggingTest` | 5 | Reads the log file: counts present, names and coordinates absent |
| `DiscoveryPerformanceTest` | 5 | 2 000 restaurants, and a query count that does not grow with the result count |
| `discovery_models_test.dart` | 18 | A restaurant with no id, name, position or route relation does not construct |
| `discovery_controller_test.dart` | 18 | Mostly counting requests: a rebuild, a view switch and a rapid double-open all cost one |
| `discovery_screen_test.dart` | 38 | Every state, both presentations, marker/card synchronisation, 320dp, long names, 1.6× text, accessibility |

## Integration — no mocks, no fakes, no stubs

`dart run tool/discovery_smoke.dart` drives this app's own `ApiClient` and
`ApiDiscoveryRepository` against a running Laravel server, real restaurant rows
in MySQL, and the real route geometry Module 06 stored. **22 assertions, 22
passed.**

What the run actually returned, against the pilot Green Park → Jaipur route:

```
route provider    : development      corridor (metres) : 5000
real provider     : false            candidates        : 6      returned : 5

restaurant                      availability            prox m  detour m  det s   ahead m
[TEST] Highway Spice Kitchen    OPEN                       900        19      1     66304
[TEST] Paused Highway Grill     NOT_ACCEPTING_ORDERS      1000        21      1     85249
[TEST] Rajasthan Highway Bites  OPEN                      2400        77      4    146830
[TEST] Closed Route Cafe        CLOSED                    1100        25      1    165762
[TEST] Behind You Diner         OPEN                      2897      5737    343         0
```

The proximity column is worth reading twice: 900, 1000, 2400, 1100 metres are
**exactly** the perpendicular offsets the seeder placed those fixtures at. The
projection recovers them from a real stored polyline, which is the strongest
evidence in this module that the geometry is right rather than merely
self-consistent.

Absent from the list, and asserted absent: Suspended Dhaba, Pending Restaurant
(neither is eligible) and Far Away Kitchen (60 km off the road, rejected by the
corridor without costing a provider call).

The run also records what it **cannot** establish:

```
NOTE  Detour-threshold exclusion = NOT APPLICABLE for this run — the
      configured provider models the road network as a straight line,
      so no in-corridor stop can exceed the detour limit.
```

### Regression, same live backend

| Run | Assertions | Result |
| --- | --: | --- |
| `tool/integration_smoke.dart` (Module 03) | 13 | 13 passed, 0 failed |
| `tool/profile_addresses_smoke.dart` (Module 04) | 24 | 24 passed, 0 failed |
| `tool/trip_planner_smoke.dart` (Module 05) | 31 | 31 passed, 0 failed |
| `tool/route_smoke.dart` (Module 06) | 21 | 21 passed, 0 failed |

## Database verification

| Check | Result |
| --- | --- |
| Restaurants stored | 8 |
| Discoverable by the SQL scope | 6 |
| Suspended | 1 (never returned) |
| Unverified | 1 (never returned) |
| Without coordinates | 0 |
| **With an invented rating** | **0** |
| Cuisine / facility / opening-hour rows | 11 / 11 / 56 |
| Fixtures prefixed `[TEST]` | 8 |
| **Fixtures NOT prefixed** | **0** |
| Indexes on `restaurants` | `(latitude, longitude)`, `(status, verification_status, is_discoverable)` |

## Performance

Measured rather than asserted.

| Measurement | Result |
| --- | --- |
| Restaurants in the table (test) | 2 008 |
| Reduced by the bounding box to | a small fraction |
| Reduced by the corridor to | 8 — the ones actually on the road |
| Provider calls | ≤ 8, and never more than the configured budget |
| Queries per discovery | fewer than 12, and **flat** as the result count triples |
| Live API latency (pilot route, 6 candidates) | **8 ms** |
| Live API latency (25 candidates, 12 detours) | **13 ms** |
| Cached second call | 0 provider calls |

The N+1 test is the one that matters for the shape of the code: three times as
many restaurants on the road adds at most two queries, because cuisines,
facilities and opening hours are eager-loaded once rather than once per row.

## Log verification

Three discovery events are recorded: `discovery.completed`,
`discovery.detour_provider_failed`, `discovery.restaurant_timezone_invalid`. Each
carries counts and uuids — candidates, corridor survivors, detours evaluated,
duration, cache hit or miss.

The privacy sweep greps the day's log for fourteen needles — every fixture name,
route geometry, all five private restaurant columns, the key prefix, and the
stored coordinates of a discovered restaurant — and finds **0 hits for every
one**.

That sweep is also how this module's most serious defect was found, and it was
not in this module: see **M07-B08** below.

## Live-view verification — 21 states

A **release** web build served over HTTP and driven in headless Chromium through
Flutter's DOM semantics tree, against the real API and the real database, with
the browser's geolocation standing in for a handset's.

| # | State | What it establishes |
| --: | --- | --- |
| 01 | Route screen | "Find food on this route" is a real control now |
| 02 | Discovery list | Real restaurants, from the real route |
| 03 | Route figures | "66 km ahead", "1 min detour", "900 m off your route", and price as a word |
| 04 | Ineligible absent | Suspended, pending and far-away fixtures are nowhere on screen |
| 05 | Availability | Open, Not accepting orders and Closed, told apart in words |
| 06 | No invented rating | Nothing where a rating would go |
| 07 | Provider notice | A stand-in route says so |
| 08 | Map view | Map-unavailable state, naming both ends and the stop count |
| 09 | Back to the list | Results intact; the toggle never re-searches |
| 10 | Card selected | |
| 11 | Behind you | Labelled, listed last, and never "0 m ahead" |
| 12 | Route not ready | "Work out your route first", with a way back and **no** retry |
| 13 | Rate limited | "Just a moment" |
| 14 | Discovery failed | A retry, and no internal error text |
| 15 | Empty | "No stops on this route yet", naming the 5 km corridor |
| 16 | Offline, cached | The stops stay |
| 17 | Offline, cold | An offline state |
| 18–20 | 320 / 360 / 430dp | Every supported width |
| 21 | Dark mode | |

Modules 05 and 06 were re-driven against the same build as a regression.

## Defects found and fixed

Eight, all closed, all in [13-known-issues.md](13-known-issues.md). The three
worth naming here could each only have been found the way they were:

- **B01** — a stop *behind* the origin was offered as the traveller's **next**
  stop, because journey order sorts by distance-along-route and a backtracking
  restaurant projects to zero.
- **B02** — a screen reader was told "0 m ahead" about the restaurant the screen
  labelled "Behind you". Only visible by driving the built app through its
  semantics tree; no screenshot could show it.
- **B08** — **a customer's phone number was being written to the application
  log.** Found by grepping a real log during the privacy sweep. A Module 01
  defect, not a Module 07 one, and it had been there since Module 03.

Two further defects were in the *tests* rather than the code: a fixture that
inherited a factory default nobody had chosen, and a fixture placed so far from
the route that the rule it existed to prove never ran. Both are recorded, because
a test that cannot fail is worse than no test.

## What is pending, and why

- **Live routing-provider detour figures = PENDING — environment unavailable.**
  With a straight-line road network every in-corridor stop costs almost nothing
  to reach — the largest detour for a stop ahead was **4 seconds** — so the
  detour *threshold* cannot exclude anything at runtime. The rule is covered by
  `RestaurantDiscoveryServiceTest` against a provider the test controls. (KI-012,
  M07-055.)
- **Live map render with markers = PENDING — environment unavailable.** (KI-011,
  M07-057.)
- **Alternative-route discovery = NOT APPLICABLE for this test response.**
  Discovery reads the selected route by construction; the provider returns one
  route, so there is no alternative to select. (M07-056.)
- **Marker clustering = NOT IMPLEMENTED**, deliberately, at a 25-result limit.
  (M07-058.)
- **Android and iOS runtime verification = PENDING — environment unavailable.**
  (KI-001, KI-002.)

None is a code failure, and none is reported as a pass.

---

# Module 08 — Restaurant search, filters, sorting and discovery ranking

Recorded against PHP 8.4.19 / Laravel 12.69.1 / MySQL 8.0.46 / Redis 7.0.15 /
Flutter 3.47.2 on Ubuntu 24.04. Providers: `ROUTE_PROVIDER=development`,
`PLACES_PROVIDER=development`, `OTP_PROVIDER=log`.

Full run output: [`evidence/module-08-verification-run.txt`](evidence/module-08-verification-run.txt).
Screenshots: `evidence/module-08/state-01..28-*.png`.

## Automated tests

| Suite | Result |
| --- | --- |
| Backend (PHPUnit) | **741 passed**, 3 049 assertions, 0 failed, 0 skipped |
| Flutter | **539 passed**, 0 failed, 0 skipped |
| Laravel Pint | clean |
| `flutter analyze --fatal-infos` | no issues |
| `dart format` | clean |

New in Module 08: 106 backend test methods and 90 Flutter test cases, measured
against the Module 07 commit.

| File | Tests |
| --- | --- |
| `tests/Unit/DiscoveryQueryTest.php` | 22 |
| `tests/Unit/SearchMatcherTest.php` | 14 |
| `tests/Unit/DiscoveryRankingTest.php` | 14 |
| `tests/Feature/DiscoveryRefinerTest.php` | 30 |
| `tests/Feature/Api/Customer/TripRestaurantFilterApiTest.php` | 37 |
| `mobile/test/discovery_query_test.dart` | 21 |
| `mobile/test/discovery_refine_controller_test.dart` | 28 |
| `mobile/test/discovery_filters_screen_test.dart` | 34 |

## Integration run — real backend, real MySQL, real route geometry

`mobile/tool/discovery_filters_smoke.dart`: **28 passed, 0 failed.**

Rahul signs in, plans Green Park → Jaipur airport, calculates a route through
Module 06, and then every check runs against what Module 07 actually found on
it.

What the route offered:

```
eligible stops : 5
cuisines       : bakery(1) cafe(1) chinese(1) fast_food(1)
                 north_indian(2) rajasthani(1) vegetarian(1)
facilities     : parking(4) restroom(2) seating(2) takeaway(1)
price levels   : 1(1) 2(3) 3(1)
rating filter  : false
detour ceiling : 900s
```

Selected checks:

| Check | Result |
| --- | --- |
| Searching "Suspended Dhaba" | 0 results |
| Searching "Pending Restaurant" | 0 results |
| Searching "Far Away Kitchen" (outside the corridor) | 0 results |
| Eleven filter shapes against ineligible restaurants | none reachable |
| `cuisines=rajasthani,chinese` (OR) | 2 of 5 |
| `facilities=parking,restroom` (AND) | excludes the parking-only fixture |
| `availability=open_now` vs `accepting_orders` | the paused grill is in the first, not the second |
| `price_levels=1` | exactly the level-1 fixture |
| `min_rating=4` | 0 results, `rating_available: false` |
| Eight malformed filters | each a 422 naming its own field |
| `sort=highest_rated` | 422, not a silent downgrade |
| `search='; DROP TABLE restaurants; --` | empty page; the table is intact |
| Seven filter/sort/page variations after one warm call | `from_cache: true` on every one |
| Suspending a restaurant mid-session | gone from the very next filtered call |

Two things the run reports as **NOT APPLICABLE** rather than passing:

- Detour-ceiling exclusion — a straight-line road network cannot produce a stop
  above any ceiling the filter can set (KI-012).
- The rating filter against real data — no restaurant has a rating, because
  there is no reviews module.

## Regression — Modules 01–07

| Module | Run | Result |
| --- | --- | --- |
| 01–03 | `tool/integration_smoke.dart` | 13 passed, 0 failed |
| 04 | `tool/profile_addresses_smoke.dart` | 24 passed, 0 failed |
| 05 | `tool/trip_planner_smoke.dart` | 31 passed, 0 failed |
| 06 | `tool/route_smoke.dart` | 21 passed, 0 failed |
| 07 | `tool/discovery_smoke.dart` | 22 passed, 0 failed |

One Module 07 assertion was updated rather than fixed: the unfiltered default
order is now recommended rather than journey order, so the run asks for journey
order by name. The eligible universe is unchanged. See `14-change-log.md`.

## Performance — measured

Refining is pure computation, and the measurement says so:

| Operation | 8 restaurants | 5 008 restaurants |
| --- | --- | --- |
| Cold discovery | 27 ms, 5 eligible | 73 ms, 258 eligible |
| Warm discovery | 9 ms | 70 ms |
| Refine, unfiltered | 0.46 ms, **0 queries** | 6.5 ms, **0 queries** |
| Refine, search | 0.61 ms, **0 queries** | 12.8 ms, **0 queries** |
| Refine, one cuisine | 0.21 ms, **0 queries** | 6.9 ms, **0 queries** |
| Refine, two facilities | 0.20 ms, **0 queries** | — |
| Refine, sort | 0.15 ms, **0 queries** | — |
| Refine, page 2 | 0.20 ms, **0 queries** | — |

Eleven combinations, zero database queries each. Provider calls: unchanged
across all of them, counted directly in
`test_changing_a_filter_never_calls_the_routing_provider`.

Detours evaluated stayed at **17** whether the table held 8 restaurants or
5 008 — the billed-call budget bounds it, not the corpus. Bounding-box
candidates are capped at `DISCOVERY_MAX_CANDIDATES` (300), so the cached payload
cannot grow without limit.

The warm path is only slightly cheaper than the cold one at scale, because only
the *selection* is cached: eligibility and availability are re-checked on every
hit by design, which is why a suspension takes effect immediately.

Query plans, and the index that was measured and then removed, are in the
evidence file.

## Live view — 28 states in a running release build

Release web build on `:5173` against the same Laravel backend on `:8000`,
driven with Playwright through the app's own semantics tree. Every state was
reached by clicking through the app as a signed-in customer with a real
calculated route. **No problems found; no console errors.**

| # | State |
| --- | --- |
| 01 | Search field above the route's stops |
| 02 | Search narrowed the list |
| 03 | Result count reads "of 5 stops" |
| 04 | Search matched nothing — its own words, not "empty road" |
| 05 | Search cleared, results restored |
| 06 | A suspended restaurant is not findable by exact name |
| 07 | Filter sheet, offering only what this route has |
| 08 | "Any of these" / "All of these" spelled out |
| 09 | No rating control, because nothing is rated |
| 10 | Detour options, from the server's ceiling |
| 11 | Draft state — choosing does not apply |
| 12 | Applying does |
| 13 | Active chip with its own remove action |
| 14 | Filter badge showing "1 filter" |
| 15 | Two cuisines are an OR |
| 16 | Removing one chip leaves the other |
| 17 | Clear all restores all 5 stops |
| 18 | Filtered empty — "There are 5 stops", with Clear filters |
| 19 | Recovered from the empty state |
| 20 | Sort sheet |
| 21 | "Highest rated" shown, disabled, with the server's reason |
| 22 | Sort applied — "Sorted by Soonest on your route" |
| 23 | Map view keeps the filtered set |
| 24 | "Taking orders" excludes the paused and closed stops |
| 25 | 320 dp — controls fit |
| 26 | 360 dp |
| 27 | 430 dp |
| 28 | Dark mode filter sheet |

Responsive widths were additionally verified in widget tests at 320, 360, 375,
390, 412 and 430 dp with no overflow, and at 1.6× text scaling — including that
the filter sheet still reaches its apply button.

## Runtime coverage

| Runtime | Result |
| --- | --- |
| Web (Chromium, release build) | **PASS** — 28 states, no console errors |
| Android | **PENDING — environment unavailable.** No Android SDK; `dl.google.com` is blocked by the egress policy. `flutter doctor`: "[✗] Android toolchain — Unable to locate Android SDK." (KI-001) |
| iOS | **PENDING — environment unavailable.** No macOS host. (KI-002) |
| Live Google map render | **PENDING** — no Maps SDK key. (KI-011) |

---

# Module 09 — Restaurant details, facilities, availability and customer preview

Recorded against PHP 8.4.19 / Laravel 12.69.1 / MySQL 8.0.46 / Redis 7.0.15 /
Flutter 3.47.2 on Ubuntu 24.04. Providers: `ROUTE_PROVIDER=development`,
`PLACES_PROVIDER=development`, `OTP_PROVIDER=log`.

Full run output: [`evidence/module-09-verification-run.txt`](evidence/module-09-verification-run.txt).
Screenshots: `evidence/module-09/state-01..25-*.png`.

## Automated tests

| Suite | Result |
| --- | --- |
| Backend (PHPUnit) | **801 passed**, 3 319 assertions, 0 failed, 0 skipped |
| Flutter | **613 passed**, 0 failed, 0 skipped |
| Laravel Pint | clean |
| `flutter analyze --fatal-infos` | no issues |
| `dart format` | clean |

New in Module 09: 60 backend test methods and 74 Flutter test cases.

| File | Tests |
| --- | --- |
| `tests/Unit/RestaurantHoursTest.php` | 19 |
| `tests/Unit/RestaurantOrderingStateTest.php` | 8 |
| `tests/Feature/Api/Customer/RestaurantDetailApiTest.php` | 30 |
| `tests/Feature/RestaurantDetailPerformanceTest.php` | 3 |
| `mobile/test/restaurant_detail_models_test.dart` | 19 |
| `mobile/test/restaurant_detail_controller_test.dart` | 17 |
| `mobile/test/restaurant_detail_screen_test.dart` | 34 |

## Integration run — real backend, real MySQL, real route geometry

`mobile/tool/restaurant_detail_smoke.dart`: **25 passed, 0 failed.**

Rahul signs in, plans Green Park → Jaipur airport, Module 06 calculates the
route, Module 07 finds the stops, and every check runs against one of them.

What the run opened:

```
name          : [TEST] Highway Spice Kitchen
cuisines      : North Indian, Vegetarian
facilities    : Parking, Restroom, Seating
price level   : 2
rating        : none
photographs   : 3
ordering      : OPEN_ACCEPTING
timezone      : Asia/Kolkata
distance ahead: 66 304 m
detour        : 1 s
off route     : 900 m
route cached  : true
```

Selected checks:

| Check | Result |
| --- | --- |
| The route figures equal the card's, field for field | PASS |
| Suspended restaurant by uuid | `RESTAURANT_UNAVAILABLE`, and the body names nothing |
| Unverified restaurant by uuid | Same |
| A restaurant outside the corridor | `RESTAURANT_OUTSIDE_ROUTE` |
| An unknown uuid | `RESTAURANT_NOT_FOUND` |
| Overnight kitchen (18:00–02:00) | One window a day, flagged overnight |
| Split service | Two windows on Tuesday; Monday closed |
| Everything optional missing | description, phone, media, facilities and price all absent |
| Private data in the raw body | None of 11 needles; the published phone is present |
| `PUT`/`PATCH`/`DELETE`/`POST` | 404 or 405 |
| Ten opens | `route_from_cache: true` on every one |
| Pause applied after discovery | Page reads `OPEN_PAUSED` |
| Suspension applied after discovery | Page withdrawn |
| Rahul on Ananya's trip | `TRIP_NOT_FOUND` |

Two things the run reports as **NOT APPLICABLE** rather than passing: ratings
(no reviews module) and detour *magnitude* (KI-012, straight-line road network).

## Regression — Modules 01–08

| Module | Run | Result |
| --- | --- | --- |
| 01–03 | `tool/integration_smoke.dart` | 13 passed, 0 failed |
| 04 | `tool/profile_addresses_smoke.dart` | 24 passed, 0 failed |
| 05 | `tool/trip_planner_smoke.dart` | 31 passed, 0 failed |
| 06 | `tool/route_smoke.dart` | 21 passed, 0 failed |
| 07 | `tool/discovery_smoke.dart` | 22 passed, 0 failed |
| 08 | `tool/discovery_filters_smoke.dart` | 28 passed, 0 failed |

Module 08's run expects eight eligible restaurants rather than five, because
Module 09 added three fixtures to the same road. Two assertions were updated to
match; neither is a behaviour change.

## Performance — measured

| Operation | Result |
| --- | --- |
| Cold discovery (8 eligible) | 54 ms, 9 queries |
| Open a restaurant | **14–20 ms, 14 queries** |
| …with 23 photographs, 12 cuisines, 13 facilities | **14 queries** — unchanged |
| …with 15 more restaurants on the route | **14 queries** — unchanged |
| Route context across ten opens | **10 of 10 from cache** |

Nine of the fourteen queries are the discovery half — validating the route and
rebuilding the cached selection against live rows, which is what makes a
suspension take effect immediately. Five are the profile: one restaurant row and
four eager loads.

**No N+1**, and asserted rather than reviewed: `RestaurantDetailPerformanceTest`
adds twenty photographs and asserts the query count is identical.

**No routing provider call**, and it is structural: the only thing in the
application that can reach one is `discover()`, which is already cached before
the detail service is asked.

## Live view — 25 states in a running release build

Release web build on `:5173` against the same Laravel backend on `:8000`, driven
with Playwright through the app's own semantics tree. **No problems found; no
console errors.**

| # | State |
| --- | --- |
| 01 | The full restaurant page, from a card |
| 02 | The route summary — ahead, detour, off route |
| 03 | Open · Accepting orders, with a live **View menu** |
| 04 | A three-photograph gallery |
| 05 | **New**, with no fabricated score |
| 06 | About and Facilities |
| 07 | Opening hours, collapsed |
| 08 | Opening hours, expanded, with the timezone |
| 09 | Location, and the way back to the map |
| 10 | Back to discovery — the search still typed |
| 11 | Open · paused, with its banner and no order button |
| 12 | Closed, and when it opens again |
| 13 | An overnight kitchen, marked overnight |
| 14 | A split service, and a day marked Closed |
| 15 | A restaurant with nothing optional — placeholder, no About, no Facilities |
| 16 | The same, further down |
| 17 | Withdrawn between the list and the tap |
| 18 | On a different road |
| 19 | Load failure, with **Try again** |
| 20 | Offline, showing what was last loaded |
| 21 | The loading skeleton |
| 22 | 320 dp |
| 23 | 360 dp |
| 24 | 430 dp |
| 25 | Dark mode |

States 23–25 were re-run after the OTP per-IP budget was exhausted mid-run — a
known limit of this environment, not a product behaviour.

## Runtime coverage

| Runtime | Result |
| --- | --- |
| Web (Chromium, release build) | **PASS** — 25 states, no console errors |
| Android | **PENDING — environment unavailable.** No Android SDK; `dl.google.com` is blocked by the egress policy. (KI-001) |
| iOS | **PENDING — environment unavailable.** No macOS host. (KI-002) |
| Live Google map render | **PENDING** — no Maps SDK key. (KI-011) |

---

# Module 10 — Menu, categories and menu item browsing

Recorded against PHP 8.4.19 / Laravel 12.69.1 / MySQL 8.0.46 / Redis 7.0.15 /
Flutter 3.47.2 on Ubuntu 24.04. Providers: `ROUTE_PROVIDER=development`,
`PLACES_PROVIDER=development`, `OTP_PROVIDER=log`.

Full run output: [`evidence/module-10-verification-run.txt`](evidence/module-10-verification-run.txt).
Screenshots: `evidence/module-10/state-01..30-*.png`.

## Automated tests

| Suite | Result |
| --- | --- |
| Backend (PHPUnit) | **864 passed**, 3 616 assertions, 0 failed, 0 skipped |
| Flutter | **686 passed**, 0 failed, 0 skipped |
| Laravel Pint | clean |
| `dart analyze` | no issues |

New in Module 10: 63 backend test methods and 73 Flutter test cases.

| File | Tests |
| --- | --- |
| `tests/Unit/MoneyTest.php` | 10 |
| `tests/Feature/Api/Customer/RestaurantMenuApiTest.php` | 42 |
| `tests/Feature/MenuPerformanceTest.php` | 11 |
| `mobile/test/menu_models_test.dart` | 24 |
| `mobile/test/menu_controller_test.dart` | 15 |
| `mobile/test/menu_screen_test.dart` | 34 |

## Integration run

`mobile/tool/menu_smoke.dart` against a live Laravel server, real MySQL rows and
this app's own network layer: **32 passed, 0 failed.**

The checks worth naming:

| Check | What it establishes |
| --- | --- |
| the wire carries no rendered price string | No `₹` anywhere in the response; `amount_minor` present |
| a five-figure price groups the way the locale does | ₹12,999 from `intl`, not from the server |
| a withdrawn category takes its items with it | Gulab Jamun is invisible although the item row is active |
| an item in a withdrawn category is not reachable by id | uuid read straight from MySQL, then refused |
| another restaurant's item cannot be read through this one | The IDOR test the module mandates |
| a suspended restaurant will not serve a menu to a known id | 404, matching a nonexistent one |
| the preview reflects a price that has since changed | Price altered behind the API's back and re-read |
| no operator-private field is on the wire | 13 needles, raw body |
| a customer has no way to change a menu | Six verb/path pairs, all refused |
| **opening a menu asks no routing provider** | Provider log unchanged across 15 menu and item requests |

The direct-id checks read fixture uuids **from the database**, not from an API
response — the point is that an identifier obtained outside the API buys
nothing, and taking it from a response would not test that.

## Performance

| Measurement | Result |
| --- | --- |
| Menu queries, 6 items / 3 categories | 2 |
| Menu queries, 500 items / 20 categories | 2 |
| Whole request, either size | 17 |
| 500-item response time | < 1 500 ms budget; measured well under |
| 500-item payload | ~130 KB, unpaginated |
| Query count vs 60 more items | unchanged |
| Query count vs 17 more categories | unchanged |
| Routing provider calls on menu open | 0 |

The 500-item fixture is generated inside the test. Production data is never used
for a load measurement.

## Live view — a rendered release build

A release web build of the same Flutter code, served on `:5173` against the live
backend on `:8000`, driven with Playwright through Flutter's real DOM semantics
tree.

| State | What it shows |
| --- | --- |
| 01 | The menu, opened from the restaurant page |
| 02 | Prices, locale-formatted — no `₹249.00`, no `24900` |
| 03 | Declared dietary types, and only those |
| 04 | A sold-out dish, shown and labelled |
| 05 | A dish with nothing optional (Papad) |
| 06 | The withdrawn item and withdrawn category are absent |
| 07 | The section selector |
| 08 | Tapping a section takes the customer to it |
| 09 | A free item priced at ₹0 |
| 10 | ₹12,999, grouped |
| 11 | Scrolling moves the highlight |
| 12 | A 60-character dish name, wrapped |
| 13 | The read-only item preview |
| 14 | Nothing in it can be ordered |
| 15 | Search narrows the menu |
| 16 | A search that matched nothing |
| 17 | Clearing brings the menu back |
| 18 | Back to the restaurant page |
| 19 | A restaurant with no menu |
| 20 | A paused kitchen — browse only |
| 21 | A closed restaurant — browse only |
| 22 | Load failure, with **Try again** |
| 23 | Withdrawn, with no retry |
| 24 | Offline, keeping the menu |
| 25 | Loading |
| 26 | 320 dp |
| 27 | 360 dp |
| 28 | 430 dp |
| 29 | Dark mode |
| 30 | 200% text |

**50 assertions across those states, none failing.** State 03 was re-run on its
own with a corrected probe: the first attempt named Dal Makhani as the dish with
no declared diet, and the seeder does declare that one vegetarian. Papad is the
fixture with nothing set, and its sentence goes straight from the name to the
price.

### What the screenshots can and cannot show

Flutter web paints text to a canvas this headless Chromium does not capture, so
every screenshot here shows layout, colour, icons, badges and structure — and no
words. That has been true since Module 09 and is a property of the environment,
not of the app.

**Text is verified through the semantics tree**, which is real DOM and is
exactly what a screen reader reads, and through the widget tests, which can read
a rendered string. Where the two differ the live driver asserts the spoken form:
the card's merged label is *"Paneer Tikka. Veg. 249 rupees"*, and the rendered
*"₹249"* is asserted in `menu_screen_test.dart`.

## Regression, Modules 01–09

| Run | Result |
| --- | --- |
| `integration_smoke` (M01–04) | 13 passed, 0 failed |
| `profile_addresses_smoke` (M04) | 24 passed, 0 failed |
| `trip_planner_smoke` (M05) | 31 passed, 0 failed |
| `route_smoke` (M06) | 21 passed, 0 failed |
| `discovery_smoke` (M07) | 22 passed, 0 failed |
| `discovery_filters_smoke` (M08) | 28 passed, 0 failed |
| `restaurant_detail_smoke` (M09) | 25 passed, 0 failed |

**164 integration checks across nine modules, none failing.**

The last four were first attempted while the live-view driver was still signing
in roughly a dozen times, and hit the **OTP per-IP budget** — a limit of this
environment, not a product behaviour. They were re-run afterwards, and Module
10's own run was re-run again after them, because `restaurant_detail_smoke`
re-seeds the discovery fixtures and menu rows cascade-delete with their
restaurant.

## Runtime coverage

| Runtime | Result |
| --- | --- |
| Web (Chromium, release build) | **PASS** — 30 states |
| Android | **PENDING — environment unavailable.** No Android SDK; `dl.google.com` is blocked by the egress policy. (KI-001) |
| iOS | **PENDING — environment unavailable.** No macOS host. (KI-002) |

---

# Module 11 — Menu item details, variants, addons, customization and Add to Cart

Full log: [`evidence/module-11-verification-run.txt`](evidence/module-11-verification-run.txt).
Screenshots: [`evidence/module-11/`](evidence/module-11/).

## Suites

| Suite | Result |
| --- | --- |
| Backend, PHPUnit | **957 passed** (3,982 assertions), 39.7s |
| Backend, Laravel Pint | **passed** |
| Mobile, `flutter analyze --fatal-infos` | **No issues found** |
| Mobile, `dart format --set-exit-if-changed` | **clean** (0 changed on the second pass) |
| Mobile, `flutter test` | **772 passed** |

New in Module 11: 93 backend test methods and 86 Flutter test cases.

| Backend file | Methods | What it holds the line on |
| --- | --- | --- |
| `Feature/CustomizationPricingTest.php` | 30 | Every price the server computes, in integer minor units |
| `Feature/Api/Customer/ItemCustomizationApiTest.php` | 15 | What the item endpoint will and will not show |
| `Feature/Api/Customer/AddToCartApiTest.php` | 39 | Every way an add can be refused, and every way it can be raced |
| `Feature/CartPerformanceTest.php` | 9 | Query counts, and zero routing-provider calls |

| Flutter file | Cases | What it holds the line on |
| --- | --- | --- |
| `test/item_customization_models_test.dart` | 15 | Parsing, and the rules a group's two numbers imply |
| `test/item_customization_controller_test.dart` | 34 | Selection, idempotency, and every failure the screen can show |
| `test/item_detail_screen_test.dart` | 37 | What the screen says, and what it refuses to say |

## The one number that matters

The live run's state 19 records two lines the rest of this module exists to
produce:

```
cart rows: 1
unit price: 38900
```

The phone was showing **Add to cart · ₹778** and sent no price at all. The row
the server wrote is **₹389** a unit — ₹329 for the Large size, ₹40 for Extra
Cheese, ₹20 for Jalapeños — times two. Every one of those numbers came out of
the restaurant's menu.

There is no assertion here that the client sent the right price, because there
is no field in which it could send one. `CustomizationSelection` has no price,
no subtotal, no discount and no total; a request carrying them parses to the
same object as a request without them.

## Integration — `tool/cart_smoke.dart`

```
dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/cart_smoke.dart
48 passed, 0 failed
```

It drives this app's own `ApiClient` against the running Laravel backend and a
real MySQL database — not a mock, not a fixture. Among the 48: the
price-tampering attempt (`unit_price_minor: 1`, `discount: 999999`) landing at
the correct price anyway, the duplicate tap producing one line, the lost
response producing one line, a modifier borrowed from another dish being
refused, and another customer's trip returning the same 404 a nonexistent one
does.

## Live view — 34 states

| # | State |
| --- | --- |
| 01 | The dish, as it opens |
| 02 | Sizes, with the configured default chosen |
| 03 | A sold-out size, shown and inert |
| 04 | A required group, stating its rule |
| 05 | An optional group, stating its ceiling |
| 06 | A paid option, showing what it adds |
| 07 | **No paid option preselected** |
| 08 | The free default, already chosen, priced |
| 09 | Single-select replaces rather than adds |
| 10 | A paid option moves the price |
| 11 | Multi-select, and the ceiling reached |
| 12 | A sold-out option, shown and inert |
| 13 | A size changes the price **absolutely** |
| 14 | The sold-out size still cannot be chosen |
| 15 | Quantity at one |
| 16 | Quantity at two, and the line total |
| 17 | The note, and what it does not promise |
| 18 | The note, filled |
| 19 | **Added to cart** |
| 20 | A dish with no default: *"Choose required options"* |
| 21 | Tapping it marks the unanswered question |
| 22 | Answering it prices the button |
| 23 | A dish with nothing to choose |
| 24 | A sold-out dish, with no button at all |
| 25 | The kitchen stopped taking orders |
| 26 | It sold out between opening and adding |
| 27 | The cart already holds another restaurant |
| 28 | **The price changed** |
| 29 | Offline, with every choice kept |
| 30 | Loading |
| 31 | 320 dp |
| 32 | 430 dp |
| 33 | Dark mode |
| 34 | 200% text |

**61 assertions across those states, none failing.**

States 25–28 are provoked by intercepting the add and returning the error the
server would return, because provoking them for real would mean racing a
restaurant edit against a tap. The refusals themselves — every one of those four
codes — are asserted against the real backend in `AddToCartApiTest` and
`cart_smoke`.

### Three assertions that are worth reading as sentences

**State 07** is asserted with Extra Cheese on screen and unticked. A test that
merely failed to find *"Extra Cheese. Adds 40 rupees. Selected"* would pass just
as well on a screen that had not rendered the option at all.

**State 13** expects ₹389, not ₹638. A variant is the price, not a surcharge; if
it were ever added to the base price instead of replacing it, this is the state
that says so.

**State 17** asserts two absences — *"guarantee"* and *"will definitely"*. The
note field is allowed to say the kitchen *will do what they can*, and is not
allowed to promise anything, because a customer with an allergy reads that
sentence differently from everyone else.

### What the screenshots can and cannot show

As in Modules 09 and 10: Flutter web paints text to a canvas this headless
Chromium does not capture, so the screenshots carry layout, colour, icons,
badges and structure — and no words. Text is verified through the semantics
tree, which is real DOM and is what a screen reader reads.

Two things the pictures do show, and both matter: at 320 dp and at 200% text
there is **no overflow stripe anywhere**, which is the defect three of this
module's four bugs were.

## Regression, Modules 01–10

| Run | Result |
| --- | --- |
| `integration_smoke` (M01–04) | 13 passed, 0 failed |
| `profile_addresses_smoke` (M04) | 24 passed, 0 failed |
| `trip_planner_smoke` (M05) | 31 passed, 0 failed |
| `route_smoke` (M06) | 21 passed, 0 failed |
| `discovery_smoke` (M07) | 22 passed, 0 failed |
| `discovery_filters_smoke` (M08) | 28 passed, 0 failed |
| `restaurant_detail_smoke` (M09) | 25 passed, 0 failed |
| `menu_smoke` (M10) | 32 passed, 0 failed |
| `cart_smoke` (M11) | 48 passed, 0 failed |

**244 integration checks across ten modules, none failing.**

Run in three batches with `redis-cli FLUSHALL` between them: every driver signs
a persona in, and a full pass exhausts the OTP per-IP budget. A 429 from it is
the rate limiter doing its job, and is a limit of this environment rather than a
product behaviour.

Module 11's own run goes last, because `restaurant_detail_smoke` re-seeds the
discovery fixtures and the menu, variant, modifier and cart rows all
cascade-delete with their restaurant.

## Runtime coverage

| Runtime | Result |
| --- | --- |
| Web (Chromium, release build) | **PASS** — 34 states |
| **Android (emulator, API 34, pixel_6, x86_64)** | **PASS** — 8 of 8 on CI |
| **iOS (simulator, macos-latest)** | **PASS** — 8 of 8 on CI |

Both device runtimes were unavailable on the development machine (KI-001: no
Android SDK, `dl.google.com` blocked by the egress policy; KI-002: no macOS
host) and are now covered by CI instead, which has both.

### The on-device driver — run, on both platforms

`integration_test/module_11_add_to_cart_test.dart` walks this module on a real
handset: the dish arrives over the device's own network stack, the controls are
tapped through the real gesture pipeline, and the row the server writes is read
back and checked. Eight tests — the dish and its rules, nothing paid
preselected, a size as an absolute price, a sold-out size that cannot be chosen,
the whole journey ending in `subtotal == 77800`, a second identical tap becoming
a quantity rather than a line, a dish with no default size, and a sold-out dish
with no button at all.

**It has now been executed, on an Android emulator and an iOS simulator, against
a real Laravel server and a real MySQL.**

| | Android emulator | iOS simulator |
| --- | --- | --- |
| Commit | `c8c1161` | `c8c1161` |
| Job | [101822160662](https://github.com/Dalbeirdev/foodonthego/actions/runs/34147358654/job/101822160662) | [101822160506](https://github.com/Dalbeirdev/foodonthego/actions/runs/34147358654/job/101822160506) |
| Device | API 34, `pixel_6`, x86_64, KVM | first available iPhone, by udid |
| "Run the on-device tests" | **success**, 17:23:58 → 17:33:10 | **success**, 17:28:19 → 17:36:37 |
| "Backend log, if anything failed" | **skipped** | **skipped** |

Two independent readings of the same fact, which is why both rows are here.
`flutter test` exits non-zero if any test fails, so a successful step means all
eight passed; and the diagnostic step that prints the backend log is guarded by
`if: failure()`, so its being *skipped* says the same thing from the other side.

### Why this is believable, when the browser run was not

An earlier revision of this section claimed the driver had been "run green in a
browser, twice" through `flutter drive`. **That claim was false and was
withdrawn.** On the development machine `flutter drive` exits 0 and prints *"All
tests passed."* while the test body never runs — proven with two negative
controls that both had to fail and did not.
[KI-013](13-known-issues.md) records it, along with the rule taken from it: *a
green result is worth nothing until a negative control has been seen to fail.*

The CI runs satisfy that rule, and not by assertion. They failed, repeatedly and
specifically, before they passed:

| Head | Android | What it said |
| --- | --- | --- |
| `cf14169` | invocation failed | `Integration tests and unit tests cannot be run in a single invocation` |
| `c5ceb76` | 6 of 8 | `"Hot"` at y=977 in an 890-tall view — built, off screen, tap missed |
| `ea04624` | 6 of 8 | `CART_TRIP_CONFLICT` — the setup's own discarded journeys |
| `38a74f0` | 7 of 8 | `Add to cart · ₹389` reachable? no — behind the confirmation |
| `00a4dde` | 7 of 8 | the confirmation still in the tree 30s after a 3s SnackBar |
| **`c8c1161`** | **8 of 8** | — |

Each of those named the failing test, the line, and the widget. A harness that
reports *that* is a harness whose green means something. The browser driver
never once said any of it, which is exactly what was wrong with it.

iOS tracked Android test-for-test at every step, including 7/8 with an identical
message on `38a74f0` — two platforms agreeing on the same failure and then on
the same pass.

### What the device runs prove that the widget tests could not

- The item screen loads over a device's own network stack, against a server on
  another host, and renders what that server sent.
- The selection rules hold under **real touch input** through the real gesture
  pipeline and the real hit test — not `tester.tap` on a fake tree.
- The price on the sticky button tracks the choices as a thumb makes them.
- `POST /cart/items` carries **no price**, and the row the server writes is read
  back over HTTP and checked: `subtotal == 77800` paise for Large + Extra Cheese
  + Jalapeños ×2, a figure the phone never sent.
- A second identical tap becomes a quantity, not a second line — verified
  against the server's own count, not the screen's.

---

# Module 12 — cart management, price revalidation and the order summary

## Suites

| Suite | Count |
| --- | --: |
| Backend (PHPUnit) | 1,018 |
| Flutter widget and unit | 797 |
| **Automated total** | **1,815** |
| On-device, Android (API 34 emulator) | 15 |
| On-device, iOS (iPhone simulator) | 15 |

Both device jobs ran the whole `integration_test` directory on `cbcf4e5`:
Module 12's seven checks and Module 11's eight, all passing on both platforms.

New backend coverage this module: `CartManagementApiTest` (30),
`CartRevalidationApiTest` (16), `CartLifecycleApiTest` (3), `CartTotalsTest` (9).
New Flutter coverage: `cart_screen_test.dart` (20), plus five conflict-resolution
tests added to `item_detail_screen_test.dart`.

## The seven on-device checks

| # | Check | What it asserts against |
| --: | --- | --- |
| 1 | the cart arrives from the server with its lines and totals | the screen, then the seeded rows |
| 2 | the cart is reachable from the menu | navigation from the menu's app bar |
| 3 | the plus changes the quantity the server holds | `GET /cart` after the tap |
| 4 | the minus stops at one rather than removing the line | `GET /cart` — the line survives |
| 5 | removing the line empties the cart on the server | `cart` is null, `item_count` 0 |
| 6 | emptying asks first, and backing out changes nothing | `item_count` still 3 |
| 7 | confirming empties it, and the journey is usable again | an add that the old code refused |

**Every one reads the server back.** A cart screen that shows the right number
while the database holds a different one is exactly what this module exists to
prevent, and a test that only inspected the screen could not tell them apart.

## Thirteen negative controls

Each broke the code deliberately and confirmed the test went red, then restored
it. Twelve fired on the first attempt.

The thirteenth did not, and the reason was a defect in the test rather than the
code: its `FakeCartRepository` was constructed and never wired into the harness,
so `emptyCalls` could not move whatever the code did. Every assertion about it
was vacuous. **An assertion that cannot fail looks identical to one that
passes** — which is the whole argument for running controls on assertions that
look obviously correct.

The full table is in [12-module-status.md](12-module-status.md).

## What is not claimed

No live view pass is claimed for this module: the cart screen was verified by
797 widget and unit tests and by fifteen on-device checks on each platform, not
by a rendered-release-build inspection of the kind Modules 09–11 recorded.

The tax rate and both fees are **nought**, and the mechanism is tested with
non-zero values in fixtures only. No production rate has been set, and none was
guessed.

---

## Module 13 — pickup time, arrival windows and pre-checkout validation

| | |
| --- | --- |
| Backend, PHPUnit | **1,081 passed**, 4,658 assertions |
| Mobile, `flutter test` | **833 passed** |
| Pint / `dart analyze --fatal-infos` / `dart format` | clean |
| Live server run | recorded in [`evidence/module-13-verification-run.txt`](evidence/module-13-verification-run.txt) |
| On device | whatever the emulator and simulator report — never what a commit claims |

### The live run

Driven over HTTP against a real Laravel server, real MySQL and real Redis, with
the output recorded rather than transcribed:

```
travel 66 min, arrival 00:31Z = 06:01 Asia/Kolkata
kitchen ready 23:49Z          = 05:19 local
max(arrival, ready) = 06:01, rounded FORWARD -> 06:10 recommended
stored selection 00:40Z, which is 06:10 local
```

Two dishes gave **20 minutes of preparation, not 40** — the maximum rather than
the sum, live rather than only in a unit test. Adding a dish after choosing a
time moved `ready_for_checkout` from true to false with status `STALE`. A used
option id, a forged one and a request carrying its own pickup time were all
refused with the **same** code. The `orders`, `order_items`, `payments` and
`pickup_codes` tables were all absent.

### Negative controls

**More than sixty run; exactly eight stayed silent.** The total is deliberately
not quoted precisely — several attempts were re-runs of a refined mutation
against the same target, and counting those as separate controls would inflate
it. What can be enumerated exactly is the eight that did not fire, and each one
exposed something:

| What was mutated | What it exposed |
| --- | --- |
| Recommendation rounds back | The mutation could not distinguish the case the test used. A generator-level control fires instead, and the planner is insensitive to it by design. |
| Fingerprint reacts to a price change | The mutation did not model the risk — it summed stored line prices, which a menu price change does not move. Re-run against the menu price, and it fired. |
| Option not bound to its cart | Only one clause of a three-clause condition was disabled. Disabling the whole condition fired. |
| Token-shape guard removed | The guard is **hygiene, not the defence** — a cache key is a literal string, so a `*` selects nothing. The comment now says so, and the lookup that does refuse has its own control. |
| Readiness derived from blockers | The mutation agreed with the server in that scenario. A sharper test was added: the server refuses and lists nothing, and the screen still says no. |
| Unknown issue code dropped | The widget fakes build objects directly, so **no JSON parsing was covered at all**. `pickup_models_test.dart` was written for it, and the control then fired. |
| Screen formats the instant | The fake's own options made the counter clock and the instant identical. It now builds them through the real parser from strings carrying an offset. |
| Past-window check disabled | Genuinely subsumed by the feasibility test in every shipped configuration. Recorded **in the test itself** rather than left to look load-bearing. |

Three of those eight ended in a test being strengthened, one in a comment being
corrected to say what the code actually does, one in a whole test file being
written, and one in an assertion being labelled honestly as unreachable.

### What the device run found

The first execution of `module_13_pickup_test.dart` on the Android emulator
failed two of seven. One was a **real API defect** — the chosen window reported
in UTC while the options beside it reported in the restaurant's zone, rendering
as "12:50 am" above a list starting "6:20 am". Each half was correct alone, so
no unit test could have caught it; it took the first screen to render both
together. The other two were bugs in the test, both recorded in
[13-known-issues.md](13-known-issues.md) and in the commit that fixed them.

---

# Module 14 — Checkout, commercial calculation and payment readiness

## Totals

| Suite | Result |
| --- | --- |
| Backend (PHPUnit) | **1,119 passed**, 4,837 assertions |
| Flutter | **904 passed** |
| Web | typecheck, tests, both builds clean |
| Pint | clean |
| `dart analyze --fatal-infos` | clean |
| `dart format` | clean |

New in this module: `CommercialCalculationServiceTest` (14),
`CheckoutApiTest` (23, including the whole-body clock control),
`PickupTimeApiTest` +1, `checkout_models_test.dart` (21),
`checkout_controller_test.dart` (17), `checkout_screen_test.dart` (30),
`pickup_time_screen_test.dart` +3, `module_14_checkout_test.dart` (5, on device).

## The device runs

Not a claim from a commit message. CI run
[34233058604](https://github.com/Dalbeirdev/foodonthego/actions/runs/34233058604),
all seven jobs green.

**Android emulator** (`pixel_6`, API 34, `google_apis`, x86_64): the shipping app
built, installed, and driven against a real Laravel server writing to a real
MySQL 8 database. **27 tests passed** across Modules 11–14. The five for
Module 14:

```
✅ the payable amount on screen is the one the server wrote
✅ only the configured components appear, with their real figures
✅ the pickup window reads on the counter clock, not the device
✅ Proceed asks the server and stops at the payment boundary
✅ editing the cart makes the quote stale and it refreshes
```

**iOS simulator**: the same suite, on a macOS runner, green.

Every assertion that matters in those tests is made against the server's own
state, fetched over a separate connection after the taps. A screen that agreed
with itself would pass whatever either side said.

## Negative controls

Sixteen mutations, applied one at a time to shipping code, each reverted after
the run. **Every one fired**, and the tests that failed are named because a
control that fires on the wrong test has told you your test is measuring
something else.

### Parsing (`checkout_models_test.dart`)

| # | Mutation | Tests it broke |
| --- | --- | --- |
| 1 | derive `payableTotal` by summing subtotal and charges | the payable total is read, never re-added from the parts |
| 2 | derive `readyForPayment` from `issues.isEmpty` | readiness is the server flag · readiness is false when the field is missing · a checkout with no quote still parses |
| 3 | unknown status falls back to `ACTIVE` | a status this build has never heard of is not read as usable · an absent status is not read as usable |
| 4 | read the expiry with `DateTime.parse().toUtc()` | the expiry keeps the clock the server wrote it on |
| 5 | recompute `hasConfiguredAdjustments` from the lists | an empty charge list with the flag set is believed |

### The screen (`checkout_screen_test.dart`)

| # | Mutation | Tests it broke |
| --- | --- | --- |
| 6 | `readyForPayment` from the blocker list | Proceed is refused when the server says the order is not ready |
| 7 | CTA ignores the quote status | a status this build has never heard of stops the checkout |
| 8 | expiry converted with `.toLocal()` | the expiry is shown on the counter's clock |
| 9 | the summary card sums its rows | the total shown is the server's, not the sum of the rows |
| 10 | invent a zero row for every unconfigured charge | with nothing configured the payable is the subtotal, said so · a charge configured as zero is shown as a row |

### The controller (`checkout_controller_test.dart`)

| # | Mutation | Tests it broke |
| --- | --- | --- |
| 11 | a forgotten quote no longer re-prepares | a forgotten quote is replaced rather than reported · an expired quote is replaced too |
| 12 | remove the in-flight guard on validate | a second validate is ignored while the first is in flight |
| 13 | refresh revalidates instead of preparing | a refresh prepares afresh · preparing again picks up the new quote id |
| 14 | a failed validate wipes the held quote | a failed validate leaves the quote on screen |

### The entry point (`pickup_time_screen_test.dart`)

| # | Mutation | Tests it broke |
| --- | --- | --- |
| 15 | show Continue to checkout regardless of the verdict | a refusal offers no way on to a checkout |
| 16 | point the route at a path nothing serves | Continue to checkout opens the checkout |

### The two clock controls

Both were written before the fix and watched to fail. `CheckoutApiTest`'s named
all five offending fields in its failure message:

```
instants on more than one clock: {
  "+00:00": ["pickup.server_now", "pickup.travel.estimated_arrival_at",
             "pickup.travel.calculated_at", "pickup.earliest_ready_at",
             "expires_at"],
  "+05:30": ["pickup.selection.start_at", "pickup.selection.end_at"]
}
```

`PickupTimeApiTest`'s then found the one the first fix had missed:
`cart.expires_at`, still in UTC.

## One control that fired on the wrong thing

Worth recording, because it is the failure mode this practice exists to catch.

The first screenshot run reported **no problems** and produced six images with no
text in them at all. The assertions read Flutter's semantics tree; the deliverable
was pixels. Both were true statements about different things.

See [13-known-issues.md](13-known-issues.md) M14-B03.

## Live verification

The whole flow was driven against a live Laravel server on a real MySQL
database, in a browser, by a script rather than by hand:

- signed in through the real OTP flow,
- planned Green Park → Jaipur International Airport,
- calculated a route, discovered `[TEST] Highway Spice Kitchen`,
- added Paneer Tikka (Large, Mild) ×2,
- chose the recommended pickup window,
- prepared a checkout and read the payable amount off the screen.

Server: `payable = 65800` minor units, `charges = []`, `ready = true`.
Screen: **₹658**, "No additional charges are currently configured", Proceed
enabled.

With `tax_rate_bps = 500` and `packaging_fee_minor = 1500` configured on the same
restaurant, the same code path: server `payable = 70590`, `TAX:3290`,
`PACKAGING_FEE:1500`; screen **₹658 + ₹32.90 + ₹15 = ₹705.90**, and the "no
additional charges" sentence gone.

## Screenshots

Twelve, in [evidence/module-14/](evidence/module-14/), listed with what each
shows in [30-client-review-package.md](30-client-review-package.md) section H.

## What is still not proven

- **No payment has been tested, because none exists.** Module 15.
- **The pickup time is not a live ETA.** Unchanged from Module 13 and not
  closable by any device run.
- **Nothing is deployed**, so nothing has been verified over a public network,
  under TLS, or behind a real load balancer.
- **Six of seven roles have no login to verify.**

---

# Module 14T — Multi-tenancy and tenant isolation

## Totals

| Suite | Result |
| --- | --- |
| Backend (PHPUnit) | **1,141 passed** (was 1,119), 4,885 assertions |
| Pint | clean |

New: `tests/Feature/Api/Tenancy/TenantIsolationTest.php` — **22 tests**, every
one over HTTP with a real Sanctum token. A service method cannot be IDOR-tested;
only a route can.

## What is asserted

Two restaurants, five people: Priya manages the Spice Kitchen, Vikram manages the
Coast Cafe, Arjun owns the Spice Kitchen, Meera is a super administrator, Rahul is
a customer.

| Area | Tests |
| --- | --- |
| List isolation | sees only assigned tenants · no assignment sees nothing |
| Single-record isolation | reads own · cannot read another's · **foreign and non-existent answer identically** |
| Write isolation | writes own · cannot write another's, *and the row is unchanged* · staff read but cannot write |
| The indirect path | a menu item by its **own id** is still scoped, with its own control · a menu list through a foreign restaurant id |
| Revocation | revoked assignment grants nothing · suspended account · deactivated account |
| The surface gate | a customer cannot reach the restaurant surface · **an assignment does not promote a customer account** |
| Platform accounts | no grant reaches nothing · reaches exactly what is granted · platform-wide grant · revoked grant · support agent scoped to one |
| Depth | owner holds everything a manager does · stronger of assignment and grant |

Two assertions worth singling out:

- **"one tenants manager cannot write to another tenant"** reads the row back from
  the database rather than trusting the response. A refusal that still wrote would
  be the worst outcome and would look identical from outside.
- **"a foreign tenant and a nonexistent one answer identically"** compares the two
  responses' code and message. A 403 here would tell somebody enumerating
  identifiers which ones are real.

## Negative controls

Seven mutations, applied one at a time to shipping code, each reverted. **Every
one fired.**

| # | Mutation | Tests it broke |
| --- | --- | --- |
| 1 | the single-tenant lookup loses `reachableBy` | 6 — cross-tenant read, identical-404, cross-tenant write, revoked, deactivated, suspended |
| 2 | the indirect path loses `inReachableTenant` | 1 — a menu item by its own id |
| 3 | platform role implies platform-wide access | 4 — no-grant, exact grant, revoked grant, support agent scope |
| 4 | revoked assignments count as access | 1 |
| 5 | the surface check is dropped | 3 — deactivated, suspended, assignment-does-not-promote |
| 6 | suspended/disabled treated as usable | 2 |
| 7 | the write action drops to staff depth | 1 |

Control 3 is the most informative: making the role string imply breadth broke
*four* tests including "reaches exactly what they are granted", which is what
proves the grant scoping does real work rather than merely agreeing with the role.

## A control that found a real bug

`accountUsable()` was first written as `$user->is_active === true`.

`is_active` defaults to **true in the database**, so a model that has not
round-tripped since `create()` holds `NULL` — and `=== true` read that absence as
a disabled account. Every account the fixtures made was therefore denied, and
every "this account reaches nothing" assertion passed **whether the boundary
worked or not**.

That is the one bug a tenancy suite must never have: green that means the subject
was broken, not that the guard held. It surfaced because a single test asserted a
*positive* — that somebody with a grant does get a capability — and that test
failed. Only an explicit `false` denies now, and `status` and `is_active` have a
test each.

## What is not proven

- **No operator login exists**, so no test signs in as a restaurant user through a
  real flow. Tokens are minted directly. What is proven is the boundary; what is
  not is the door.
- **No orders, payments or settlements exist** to be tenant-scoped yet.
  `BelongsToTenant` is the seam they will attach to.

# Module 15 — orders, payment, webhooks and reconciliation

## Totals

| Suite | Result |
| --- | --- |
| Backend (PHPUnit) | **1,201 passed** (was 1,141), 5,212 assertions |
| Flutter (`flutter test`) | **938 passed** (was 904) |
| Pint / `flutter analyze --fatal-infos` / `dart format` | clean |

Sixty new backend tests and thirty-four new Flutter tests.

| File | Tests | Subject |
| --- | --- | --- |
| `tests/Unit/RazorpaySignatureTest.php` | 8 | The HMAC arithmetic, with real HMACs |
| `tests/Feature/Api/Payments/OrderAndPaymentApiTest.php` | 25 | Placing, intent, the three checks, ownership, one clock |
| `tests/Feature/Api/Payments/WebhookApiTest.php` | 13 | Signature, idempotency, poisoning, unknown subjects |
| `tests/Feature/Api/Payments/OrderTenancyAndReconciliationTest.php` | 12 | Cross-tenant orders, reconciliation |
| `tests/Unit/ProductionConfigGuardTest.php` | +2 | Boot refusal for missing keys and missing webhook secret |
| `test/placed_order_models_test.dart` | 12 | Parsing, unknown status, wall clock, no secret field |
| `test/order_controller_test.dart` | 12 | Never paid from a handoff; failure mapping |
| `test/payment_screen_test.dart` | 9 | Screen states, unavailable ≠ declined, 2× text |

## The assertions worth singling out

- **`test_a_correctly_signed_payment_for_another_provider_order_settles_nothing`**
  — the signature is genuine and verifies. What fails is the binding. A project
  that checked only signatures would pass every other test in this suite and
  ship this hole.
- **`test_a_payment_for_the_wrong_amount_settles_nothing`** — real, signed,
  correctly bound, and for ₹1.
- **`test_a_forged_delivery_cannot_poison_the_idempotency_key`** — see below.
- **`test_a_handoff_claiming_success_does_not_make_an_order_paid`** — the app is
  told the payment succeeded and the server says otherwise. The screen follows
  the server.
- **`test_no_response_ever_contains_the_key_secret`** — four endpoints, checked
  for both the value and the field name.

## Negative controls

Ten mutations, applied one at a time to shipping code, each reverted.

| # | Mutation | Tests it broke |
| --- | --- | --- |
| 1 | signature verification always agrees | 4 |
| 2 | the payment/order binding check is dropped | 1 |
| 3 | the amount check is dropped | 3 — client, webhook and reconciliation |
| 4 | the webhook records the delivery before verifying it | 1 — the poisoning test |
| 5 | a duplicate delivery is reprocessed instead of skipped | 1 |
| 6 | placement stops checking for an existing order | 1 |
| 7 | settle stops checking whether the order is already paid | **0, then 1** |
| 8 | the receipt resolves the dish through the menu | 1 |
| 9 | one instant is rendered on a second clock | 1 |
| 10 | an already-paid order may open another payment | 1 |

## The control that stayed silent

**Control 7 did not fire**, and that was the most useful result of the ten.

Deleting the "is this order already paid?" guard from `settle()` changed
nothing. `test_verifying_twice_settles_once` still passed — because both
verifications happened inside the same second and `paid_at` is a second-precision
column. The second settlement rewrote an identical value, and
`assertEquals($paidAt, $order->fresh()->paid_at)` could not tell the difference
between "the guard held" and "the guard was gone and wrote the same number".

The test was green for a reason that had nothing to do with the property it
claimed to check. It now moves the clock five minutes between the two calls, and
also pins the payment's `verified_at`. Re-run with the same mutation, the control
fires.

This is the second time in this project a control has caught a test rather than
the code — Module 14T's `accountUsable` bug was the first. Both were found the
same way: **a control that stays silent has told you something.**

## What is not proven

- **No live payment has ever been taken.** No credentials exist, so
  `RazorpayGateway` has never made a request and no provider checkout has ever
  opened. Everything above is verified against a deterministic double and real
  HMAC arithmetic; none of it proves Razorpay behaves as its documentation says.
- **No refund, settlement or payout path exists** to be tested.
- **Module 15's device coverage lives in `module_14_checkout_test.dart`**, which
  was extended to the new boundary rather than duplicated into a new file: the
  flow is one continuous journey and a second file would have copied two hundred
  lines of seeding to reach the same screen. It asserts, from the server, that
  the quote became exactly one order, that it is `AWAITING_PAYMENT`, and that
  `paid_at` is null.

## The device run, and how long it took to read it

Module 15's device coverage is now verified rather than asserted. Run 116 on
`4c590e9`: seven CI jobs, zero failures, **27 of 27 device tests passing on both
the iOS simulator and the Android emulator.**

| Job | Result |
| --- | --- |
| Backend — Laravel 12 | 1,201 tests, green |
| Web — React + TypeScript | green |
| Mobile — Flutter | 938 tests, green |
| Mobile — iOS build | green |
| Mobile — iOS simulator | 27/27 device tests |
| Mobile — Android review build | green |
| Mobile — Android emulator | 27/27 device tests |

The boundary the module rests on is proved on real hardware, from the server
rather than the screen: tapping Proceed places exactly one order, the payment
screen shows the order number the server minted, the order is `AWAITING_PAYMENT`
and `paid_at` is null.

**Getting there took five runs, and none of the delay was the tests' fault.**
The failing assertion — `ApiException(UNAUTHENTICATED, status: 401)`, with a
stack trace naming the file and line — was thrown correctly on the very first
run. It reached a human on the fifth. The cause was one missing named argument
in a *test helper*: `ApiClient.get` takes `{bool authenticated = false}`, and
`ordersFor` took the default, so no `Authorization` header was ever sent. The
route did precisely its job in rejecting it.

Three defects in the CI plumbing kept that message from being printed, and they
are recorded in full as **KI-023**. The part worth repeating here, because it is
about evidence rather than about shell scripting:

> The diagnostic step printed its own header and nothing else. Twice. That was
> read as "no assertion failed" when it meant "nothing was ever printed."

This document already says, in two places, that a control which stays silent has
told you something. Applied to the code under test twice — Module 14T's
`accountUsable`, Module 15's already-paid guard — and not applied to the
instrumentation itself, which had never been negative-controlled against a
failing run at all. The scoreboard for the episode: one real bug, three
self-inflicted tooling bugs, and two diagnoses stated confidently and wrongly
before the evidence existed to support either.

`scripts/ci-device-report.sh` now carries the report, is exercised against a
missing log, an empty log, a log with no markers and a log with a real
assertion, and `device-tests.log` is kept as a CI artifact on every run whether
it passes or fails.

# Module 16 — order creation, confirmation, order number and pickup code

## Totals

| Suite | Tests | New in this module |
| --- | --- | --- |
| Backend (PHPUnit/Pest, real MySQL) | **1,252 passed**, 5,551 assertions | 51 |
| Flutter (widget + unit) | **950 passed** | 12 |

Backend duration 97.5s; Flutter 2m08s. Both green with no skips.

The 51 backend tests are `OrderPlacementTest` (23), `OrderConfirmationApiTest`
(12), `OrderRecoverySweepTest` (9) and `OrderSnapshotImmutabilityTest` (7). Two
of the 51 — the restaurant-isolation test and the default-grace test — exist
only because negative controls proved the tests already written could not see
the properties they claimed.

## Negative controls

Twelve mutations were applied to shipping code, the targeted suite was run, and
the code was reverted. **Every one of them now fails the suite.** Four did not,
at first.

| # | Mutation | Result | Target |
| --- | --- | --- | --- |
| NC-01 | Remove the captured-status guard | FIRED | `OrderPlacementTest` |
| NC-02 | Remove the amount/currency agreement check | FIRED | `OrderPlacementTest` |
| NC-03 | Drop `restaurant_id` from the credential context | **silent → FIRED** | `OrderPlacementTest` |
| NC-04 | Drop the credential version from the context | FIRED | `OrderPlacementTest` |
| NC-05 | Store the plaintext code instead of its digest | FIRED | `OrderPlacementTest` |
| NC-06 | Stop excluding payment targets from the Orders tab | FIRED | `OrderConfirmationApiTest` |
| NC-07 | Make the credential response cacheable | **silent → FIRED** | `SecurityHeadersTest` |
| NC-08 | Put the order number into the QR payload | FIRED | `OrderConfirmationApiTest` |
| NC-09 | Cast a missing credential version instead of refusing | FIRED | `OrderPlacementTest` |
| NC-10 | Read the legacy `users.phone` for the snapshot | **silent → FIRED** | `OrderPlacementTest` |
| NC-11 | Put the order total into the outbox payload | FIRED | `OrderRecoverySweepTest` |
| NC-12 | Set the recovery grace period to zero | **silent → FIRED** | `OrderRecoverySweepTest` |

## The four that stayed silent

Each had a different cause, and only one of them was the control's own fault.

### NC-03 — a test that could not tell which field was doing the work

`test_a_credential_cannot_be_replayed_at_another_restaurant` builds two placed
orders at two restaurants and asserts neither accepts the other's credential.
With `restaurant_id` removed from the HMAC context, it stayed green.

It had to. **Two orders at two restaurants also have two different uuids**, so
the derived credentials differ whether or not the restaurant is in the input.
The test proves order binding. It never proved tenant binding, and it read as
though it did — including in the traceability entry written for it.

`test_the_restaurant_id_alone_changes_the_credential` holds the uuid and the
version constant, moves only `restaurant_id`, and asserts both derived values
change. It also asserts the uuid and version did *not* change, so the finding
cannot be explained by something else moving. Re-run with the same mutation,
the control fires.

### NC-07 — the guarantee was somewhere else entirely

Changing the controller's `Cache-Control` to `private, max-age=60` left
`test_the_credential_endpoint_returns_a_code_and_forbids_caching` green.

The reason is that `SecureHeaders` sets `Cache-Control: no-store, private` on
**every** API response and runs after the controller. The property holds — more
broadly than the module claimed — but not for the reason the controller's own
docblock gave, and the header set in the controller never ships.

Nothing was wrong except the story. The controller's header is kept, because a
future narrowing of the middleware should not silently make this one response
cacheable, and its docblock now says plainly that the middleware is what ships.
Re-aimed at `SecureHeaders`, the control fails both `SecurityHeadersTest` and
the credential endpoint's own test.

### NC-10 — the control was pointed at the wrong file

The `phone_e164` guard lives in `OrderPlacementTest`, not in
`OrderSnapshotImmutabilityTest` where the control was aimed. Re-run against the
right suite it fails immediately, on the assertion that caught this bug the
first time.

This one is the control's fault rather than the suite's, and it is recorded
rather than quietly re-run because **a control aimed at the wrong target is
indistinguishable, in its output, from a property nothing is testing.** Both
print a passing suite.

### NC-12 — the default was the one value nothing exercised

Changing `capturedWithoutOrder(int $graceSeconds = 120)` to `0` left all eight
sweep tests green, because every test that cared about the grace period passed
`--grace` explicitly.

**The default is the value that runs in production**, where nobody passes a
flag. `test_the_default_grace_period_leaves_a_fresh_capture_alone` runs
`orders:recover-captured` with no options against a 30-second-old capture and
asserts nothing is placed — then ages the same capture to 300 seconds and
asserts it *is*, so a sweep that never places anything could not pass.

The property being protected: a capture seconds old very likely has a creation
still in flight, and sweeping it means two workers racing to place the same
order. The unique index would hold, but the sweep would be manufacturing the
collision it exists to clean up after.

## What that pattern keeps costing

Four modules in a row have now produced a silent control, and every one of them
found a defect that the assertions themselves were blind to:

| Module | Silent control exposed |
| --- | --- |
| 14T | `accountUsable()` denying by accident, making every "reaches nothing" assertion pass regardless |
| 15 | An already-paid guard whose test could not distinguish "held" from "gone and wrote the same value" |
| 16 (during build) | Four HTTP-level guards short-circuited by Module 15 before reaching Module 16's checks |
| 16 (this pass) | A cross-tenant test proving order binding only; a cache header set in the wrong place; an untested production default |

None of these were found by a test failing. All of them were found by a test
**not** failing when it should have.

## Defects found by guards rather than by assertions

| Defect | What found it |
| --- | --- |
| `customer_phone_snapshot` written as `NULL` — the code read `users.phone`, a legacy column that is never populated | An assertion that the *fixture* was non-empty, placed before the assertion about the snapshot |
| Two different pickup credentials for one order, depending on whether the model had been reloaded — `(int) null` is `0`, a usable HMAC input | A guard refusing a missing `pickup_credential_version` instead of casting it |
| `PlacedOrder.orderNumber` non-nullable in Dart: a `FormatException` on the payment screen for every customer | Reading the code. Every widget test passed, because the fake always supplied a number |
| A QR-payload assertion that matched a substring, which an empty field also satisfies | Rewriting it as equality against `prefix + token` |
| A 44px overflow in the Orders tab at 320px and 2× text, in two separate rows | Testing at that size instead of the default surface |

## What is not proven

- **No live Razorpay capture has ever reached this module.** Every path
  downstream of a capture is verified against the deterministic fake gateway.
  What is unproven is the *shape* of the real provider's data — field names,
  statuses, amount units — not the logic consuming it. KI-026.
- **Pickup verification does not exist.** No redemption endpoint, no scanner, no
  counter flow. The credential is minted and served; nothing consumes it. No
  claim is made that QR pickup works.
- **There is no attempt limit on guessing a pickup code**, because there is
  nothing yet to limit. KI-024.
- **`payments:reconcile` is still unscheduled.** Noticed while registering this
  module's three commands, deliberately not changed here. KI-025.
- **An order cannot move past `PLACED`.** The state machine's empty arrays are
  the current truth. KI-027.
- **The device suite has not yet been extended to the confirmation flow.** The
  existing 27 device tests still pass; they exercise the boundary as Module 15
  left it.

# Module 17 — customer order tracking, status timeline and order state presentation

## Totals

| Suite | Tests | New in this module |
| --- | --- | --- |
| Backend (PHPUnit/Pest, real MySQL) | **1,305 passed**, 5,826 assertions | 45 |
| Static analysis (PHPStan 2.2.13 + Larastan 3.12.0) | **level 3, 0 errors** | new (KI-003) |
| Flutter (widget + unit) | **986 passed** | 34 |
| Device (integration_test) | 29 per platform | 1 |

Backend 78.2s; Flutter 1m43s. No skips.

### CI, as verified rather than assumed

Commit `1026fe3`, read back from the GitHub API rather than inferred from a green
badge:

| Run | Event | Result |
| --- | --- | --- |
| 34486169856 | `pull_request` | **success — 7/7** |
| 34486164760 | `push` | success |
| 34486164771 | `push` (deploy) | success |

This run is the one that carries the eight-process parallel race (KI-029). It passing
on a shared CI runner, not just on a quiet development machine, is the evidence that
the harness is not too timing-sensitive to keep.

**The `pull_request` run is the one that counts.** Device jobs run only on
`pull_request` and `main`, so a green push run says nothing about the handsets — its
three mobile device jobs report `skipped`, which is not a pass. All seven jobs are
green on the PR run: Backend, Web, Mobile Flutter, iOS build, iOS simulator, Android
review build, Android emulator.

The backend job's steps, in order and all green:

```
Pint → Static analysis (PHPStan + Larastan) → Migrate → Test → composer audit
```

That third line is new, and it is also the proof that KI-003's recorded diagnosis was
wrong: `composer install` fetched `phpstan/phpstan` in CI without incident. The
restriction was only ever the development container's repository scoping.

The backend total moved from 1,297 to 1,301 after the module closed: KI-008's
session tests were rewritten from one test pinning the old behaviour into five
covering the new one — three refusals, one control proving the gate still lets a
healthy account through, and one asserting that revoking the tokens still ends
the session too. The two tenancy tests affected by the same change did not move
the count; they gained assertions.

## The evidence file

`evidence/module-17/tracking-lifecycle-run.txt` is produced by
`ModuleSeventeenEvidenceTest`, which walks one real order from a captured
payment through `ACCEPTED → COOKING → READY → PICKED_UP`, reading the tracking
API after each step and writing down what it saw. It asserts as it goes, so a
broken run produces a failure rather than a confident file of wrong numbers.

Two limitations are printed on the face of the file: the capture is from the
deterministic fake gateway, and the transitions are driven by the `TEST_HARNESS`
actor because no restaurant UI exists. The service, the locking, the tenant
check and the audit trail are the real ones.

**The clock moves two minutes between steps, and that is not decoration.** With
a frozen clock every milestone lands on the same instant, and the file could
show five identical timestamps while describing a build that wrote `placed_at`
five times. The run shows 12:00, 12:02, 12:04, 12:06, 12:08 — and four
assertions require each milestone to be strictly later than the one before.

## Negative controls

Twelve mutations, applied to shipping code, targeted suite run, reverted. **All
twelve now fail the suite.**

| # | Mutation | Result |
| --- | --- | --- |
| NC-01 | Validate the caller's stale model instead of re-reading under the lock | FIRED |
| NC-02 | Make the transition table permit anything | FIRED |
| NC-03 | Drop the cross-tenant actor check | FIRED |
| NC-04 | Stop bumping `order_version` | FIRED |
| NC-05 | Give upcoming timeline steps the current time | FIRED |
| NC-06 | Keep the happy path going after a rejection | FIRED |
| NC-07 | Send the internal reason code as the customer note | FIRED |
| NC-08 | Put the pickup credential into the tracking response | FIRED |
| NC-09 | Sort active orders by id instead of soonest pickup | **silent → FIRED** |
| NC-10 | Treat every order as active | FIRED |
| NC-11 | Remove the already-in-that-state early return | FIRED |
| NC-12 | Stop writing the initial `PLACED` history row | **silent → FIRED** |

## The harness was the defect, not the code

Eight controls appeared silent on the first pass. They were not eight findings.

One control removed a line by replacing it with an empty string, and the revert
did `content.replace("", original)` — which inserts at **position 0**, ahead of
`<?php`. Every control after it ran against a file that no longer parsed, and
PHP's *"strict_types declaration must be the very first statement"* contains
neither "failed" nor "error", so the harness scored those runs as silent.

**What gave it away was the shape.** Eight controls going quiet at once is not a
plausible pattern of eight independent test defects. One silent control invites
you to investigate the test; eight invite you to investigate the instrument.

Two rules, now in the harness:

- **Revert from a saved copy**, never by reversing a string edit. A reverse
  replace is not the inverse of a replace when either side is empty.
- **A parse error is not a fired control.** It is reported as
  `BROKEN-HARNESS` rather than folded into either outcome.

Second time instrumentation has been the defect rather than the code — KI-023
was the first — and both times the instrumentation had never been
negative-controlled against a known failure.

## The two real defects the controls found

### NC-09 — a test that every sort would pass

Active orders sort by soonest pickup. The test created the later pickup
**second**, so the newer order also had the sooner pickup, and sorting by id
descending produced the same list as sorting by pickup time.

The two orderings now disagree — the order placed first is the one to be
collected soonest — and a guard asserts `$sooner->id < $later->id` so the
disagreement is a fact of the test rather than an accident of fixture order.

### NC-12 — an assertion about its own fixture

"Placement writes the first history entry" ran against a test helper that wrote
the row itself. Commenting out the save in `CreateOrderFromCapturedPayment` left
it green, because the claim was about the fixture.

It is now asserted against a payment captured through the real HTTP surface,
including that the history row's `occurred_at` equals the order's `placed_at` —
the same instant on the live path, and deliberately not the same instant when a
recovery sweep finishes a stranded capture hours later.

## A defect caught by an existing invariant

The timeline, the credential expiry and `server_time` all shipped in UTC while
every other instant in the order response was on the restaurant's clock. Module
13's `every instant in one order response is on one clock` failed immediately.

The presenter's zone helper is now shared rather than duplicated, which is what
stops a fourth producer of instants introducing a fourth clock.

## A defect caught by writing the test, not by running it

The status hero rendered the client's own label while the timeline rendered the
server's wording, so one screen could show *"Being prepared"* above *"Your food
is being prepared"*. The server sends the copy precisely so the client does not
decide it.

`PlacedOrder` now carries `status_title` and `status_subtitle`, and the fake
carries them too — a fake more complete than reality is what made Module 16's
nullable order number invisible to every widget test.

## What is not proven

- **No restaurant has ever moved an order.** Every transition in every test was
  driven by the system, payment or test-harness actor. The restaurant path is
  tested with controlled identities at the service layer; no screen exists.
  KI-028.
- **Concurrency is tested sequentially.** The collisions run through the real
  service with stale model instances, which is what a losing worker holds, but
  two processes at the same instant are not reproduced. KI-029.
- **No live Razorpay capture**, unchanged since Module 15.
- **No refund exists to display.** `PaymentStatus` has no `REFUNDED` case.
- **No realtime, no ETA, no push, no pickup verification** — and tests assert
  the app does not claim any of them.

## The device run, and the second evidence file

Two device failures on CI run 158, on iOS only, on a commit whose Android run
was green apart from one of them. They had two different causes, and treating
them as one would have got both wrong.

**The tracking screen could not load an order.** A real defect: `tracking()`
unwrapped the response envelope twice, so `TrackedOrder.fromJson` was handed
null on every real call. Nothing in the suite could have caught it — all 962
widget tests then in the suite drive a fake repository, so the code that turns
an actual HTTP body into a model had never executed once, not once.
`test/order_repository_wire_test.dart`
is the missing layer: the real repository against a `MockClient` returning the
envelope copied out of the live run, not written from the model's point of view.
Restoring the double unwrap fails three of its four cases.

**The menu item screen could not load an item.** Not a defect in the app. The
device job's backend was `php artisan serve` with its default single worker,
answering one request at a time while the app asked nine at once; one of them
passed the client's ten-second timeout and the screen said so. The measurement
is in `evidence/module-17/serve-concurrency-run.txt`, and the fix is eight
workers in `scripts/ci-backend-up.sh`. KI-032.

That file is worth reading for one thing beyond the numbers: the first attempt
at the measurement showed **no difference at all** between one worker and eight,
because Laravel silently declines `PHP_CLI_SERVER_WORKERS` without `--no-reload`
and both arms were the control. The script now greps its own log for that
warning.

## The Android run, and the third harness fault

The next run put the tracking fix on both devices and turned up one more
failure, on Android: `module_14`'s *the confirmation screen opens cold on a real
order id*, refused `RESTAURANT_NOT_ACCEPTING_ORDERS` while adding to the cart.

The server was right. The fixture restaurant is seeded "open all week", which
wrote `00:00:00 – 23:59:59`; `covers()` asks `$time < closes_at`; so it was shut
for the whole 23:59:59 second, every night. That job ran from **23:46:53 to
00:06:57 in Asia/Kolkata**. Reproduced locally rather than inferred — see KI-033
for the three-line table that shows OPEN, then CLOSED, then OPEN across the
boundary.

Both the seeder and `RestaurantFixtures::openAllWeek` now write an overnight
`00:00:00 – 00:00:00`. `test_a_restaurant_open_around_the_clock_is_open_through_midnight`
pins it across five consecutive seconds, and restoring `23:59:59` fails it.

Backend after the change: **1,294 passed**, one more than before, and that one
is the new test.

## Tracking screenshots

Eight, in `evidence/module-17/screenshots/`, with a README naming what each one
evidences. Captured by `mobile/tool/capture_tracking_screenshots.dart` — the
real widget tree with Roboto and MaterialIcons loaded out of the Flutter SDK, so
unlike the Module 01 and 14 images there is no stand-in font here.

It lives under `tool/` rather than `test/` deliberately: `flutter test` with no
path runs `test/` only, so CI never runs it, and a golden that CI does not
enforce cannot fail a build over an antialiasing difference between two
machines. These are evidence, not assertions. The assertions about this screen
are in `test/order_tracking_test.dart`, and the proof that it works against a
real server is the on-device suite.

One artefact is left in the images rather than cropped: the app bar title
renders as boxes under this harness while every other string resolves. The cause
was not found, it does not reproduce on either device run, and the README says
so — a screenshot with something quietly removed is worth less than one with
something visibly unexplained.
