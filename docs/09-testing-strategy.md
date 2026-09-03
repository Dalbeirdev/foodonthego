# 09 — Testing strategy

## Principle

A test exists to catch a specific failure. Tests that assert a framework works are noise; tests that
pin a decision (redaction, contrast, idempotency, error disclosure) are the ones worth having.

## Backend — 197 tests

Run against **real MySQL 8**, not SQLite. The schema uses MySQL types and later modules will use
MySQL locking semantics; a SQLite run would pass against a schema production cannot create.
Cache/session/queue use array drivers so a run neither depends on nor pollutes a live Redis — the
Redis integration itself is covered by the readiness test.

| Suite | Covers |
| --- | --- |
| `HealthTest` | Liveness, readiness against real MySQL + Redis, no credential leakage |
| `ErrorContractTest` | Every error shape; that a 5xx never describes itself |
| `RequestIdTest` | Correlation IDs; forged/oversized/injection-shaped inbound ids |
| `SecurityHeadersTest` | Header baseline; CORS never reflects an arbitrary origin |
| `IdempotencyTest` | Replay via a call counter; same key + different body rejected |
| `RateLimitTest` | Limit headers, 429 contract, health exemption |
| `StructuredLoggingTest` | Redaction across 11 sensitive key shapes, nested and deep |
| `RoleTest` | All seven roles; restaurant/platform roles disjoint |
| `ProductionConfigGuardTest` | Every refuse-to-boot condition |
| `UserModelTest` | UUID assignment, route key, hashing, soft delete, default role |
| `PhoneNormalizerTest` | Nine spellings of one number → one identity; landline and hostile input rejected; longest calling code wins |
| `OtpChallengeServiceTest` | Plaintext never stored, peppering, expiry, replay, attempt exhaustion killing a correct code, supersession, delivery failure |
| `RegistrationTokenServiceTest` | Forged, tampered, stale, unconsumed and mismatched tokens all refused |
| `CustomerAuthServiceTest` | No password column, phone≠email verification, role-scoped lookup, ability scoping, status gating, registration race |
| `LogOtpProviderTest` | The development sender refuses production, declares it cannot reach a handset, and writes to its own channel |
| `CustomerOtpTest` | Both endpoints end to end: masking, no enumeration, cooldown, rate limits, every failure code |
| `CustomerRegistrationTest` | Registration bound to the token; a caller-supplied number is ignored; idempotent retry |
| `CustomerSessionTest` | 401 shapes, expiry, logout scope, no cookie auth, no token in a query string |
| `AuthorizationBoundaryTest` | A customer token refused by restaurant- and admin-shaped routes, and the reverse |
| `AuthLoggingTest` | A complete sign-up written to disk, then grepped: no code, no token, no full number |
| `PruneOtpChallengesTest` | Retention window; a live challenge is never pruned |

## Web — 29 tests

| Suite | Covers |
| --- | --- |
| `AppShell.test.tsx` | Navigation, active state, breadcrumbs, collapse + persistence, account menu, skip link, landmark labelling, localStorage throwing |
| `apiClient.test.ts` | Envelope unwrapping, error codes, transport vs server failure, malformed body, idempotency header, 204, abort |
| `admin/App.test.tsx` | Navigation architecture completeness; System Health states |
| `restaurant/App.test.tsx` | Navigation architecture completeness |

## Mobile — 155 tests

| Suite | Tests | Covers |
| --- | --: | --- |
| `domain_models_test.dart` | 16 | Greeting/initials edge cases, order lifecycle, progress clamping, dashboard states |
| `components_test.dart` | 21 | Every status state, countdown flooring, touch targets, long content, 1.4x text, error kinds, loading button |
| `navigation_test.dart` | 12 | The five-tab matrix, rapid switching, double-tap, Android back, state retention, placeholder routing |
| `home_screen_test.dart` | 14 | Personas A–D, loading, four error kinds, retry re-fetch, dark mode |
| `fixture_isolation_test.dart` | 11 | Environment gating, feature flags, production repository invents nothing |
| `tokens_test.dart` | 8 | 4px grid, touch targets, type floors, **WCAG contrast ratios**, theme wiring |
| `auth_flow_test.dart` | 27 | The whole sign-in walk: guard redirects, local validation, every server failure code, resend countdown, registration binding |
| `auth_session_test.dart` | 12 | Restore with and without a network, expired tokens, sign-out confirmation, sign-out with the server unreachable |
| `api_client_test.dart` | 13 | Envelope unwrapping, unknown codes, gateway HTML, credential placement, one-401-ends-the-session |
| `auth_models_test.dart` | 21 | Trunk-zero handling, per-country plausibility, masking parity with the server, token never printed, every backend error code mapped |

Two of these earn their keep by asserting things a screenshot cannot show: `retry actually re-asks
the repository` counts calls and caught a silent retry loop; the contrast tests compute WCAG
luminance and caught a palette below AA.

`tokens_test.dart` computes real WCAG relative luminance. It caught a genuine defect: white on
`primary-600` was 3.31:1.

## Integration — the real thing

`mobile/tool/integration_smoke.dart` drives **this app's own `ApiClient` and `ApiAuthRepository`**
against a running Laravel server and a real MySQL database. No mocks, no fakes, no stubs: 15
assertions covering request, wrong code, correct code, registration, `/customer/me`, replay refusal,
logout revocation, an invalid number, and the resend cooldown.

It exists because the widget tests prove the screens behave correctly against a fake and the backend
tests prove the API behaves correctly on its own — but neither proves the two agree on the wire. A
field renamed on one side and not the other passes both suites and fails in a customer's hand.

It is deliberately a `dart run` and not a `flutter test`: `flutter_test` replaces `HttpClient` with
a mock, so a "test" there could never make a real request.

## Live-view verification

Automated, not manual claims. `web` shells are driven in headless Chromium across **360, 390, 430,
768, 1024, 1280, 1440 and 1920px**, asserting on each:

- no console errors, page errors or failed requests
- `scrollWidth <= clientWidth` (no horizontal overflow) — **including with the API forced down**,
  because the degraded state renders the longest string in the topbar
- no interactive control shorter than 44px

Then every one of the 25 nav routes is visited, asserting exactly one active link and a breadcrumb;
the sidebar collapse, the account menu, Escape-to-close and the mobile drawer are exercised.

Flutter is built for web and rendered at iPhone SE / iPhone 15 / iPhone 15 Pro Max / small-Android
logical sizes, with all five tabs visited and dark mode captured.

For Module 03 the Flutter build is driven **against the real API and database** — a `production`
build, so no fixtures and no development harness — through Flutter's DOM semantics tree: welcome →
country picker → phone → code (wrong, then right) → registration → home → profile → sign out →
reload. 20 screenshots, and the run asserts no console errors and no page errors throughout.

## What is not tested yet

- **No end-to-end test across all three clients** — the customer app now has a real integration run
  against the API (above), but the restaurant and admin shells still have nothing to authenticate
  with. That arrives with the module that gives them a sign-in.
- **No Android instrumentation or iOS UI test** — see [13-known-issues.md](13-known-issues.md).
- **No PHP static analysis** — PHPStan could not be installed; see the same document.
