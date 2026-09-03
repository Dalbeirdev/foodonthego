# 09 — Testing strategy

## Principle

A test exists to catch a specific failure. Tests that assert a framework works are noise; tests that
pin a decision (redaction, contrast, idempotency, error disclosure) are the ones worth having.

## Backend — 67 tests

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

## Web — 29 tests

| Suite | Covers |
| --- | --- |
| `AppShell.test.tsx` | Navigation, active state, breadcrumbs, collapse + persistence, account menu, skip link, landmark labelling, localStorage throwing |
| `apiClient.test.ts` | Envelope unwrapping, error codes, transport vs server failure, malformed body, idempotency header, 204, abort |
| `admin/App.test.tsx` | Navigation architecture completeness; System Health states |
| `restaurant/App.test.tsx` | Navigation architecture completeness |

## Mobile — 19 tests

| Suite | Covers |
| --- | --- |
| `app_shell_test.dart` | Five destinations, tab switching, state preservation, disabled CTA, honesty notices, dark mode, system theme |
| `tokens_test.dart` | 4px grid, touch targets, type floors, **WCAG contrast ratios**, theme wiring |

`tokens_test.dart` computes real WCAG relative luminance. It caught a genuine defect: white on
`primary-600` was 3.31:1.

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

## What is not tested yet

- **No end-to-end test across all three clients** — there is no feature to drive end to end. It
  arrives with the first module that has one.
- **No Android instrumentation or iOS UI test** — see [13-known-issues.md](13-known-issues.md).
- **No PHP static analysis** — PHPStan could not be installed; see the same document.
