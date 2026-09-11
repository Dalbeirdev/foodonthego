# FoodOnTheGo

**Route-based food pre-order and pickup.** A traveller enters an origin and a destination;
FoodOnTheGo finds restaurants on or near that route; the traveller orders before arriving; the
kitchen cooks against their **expected arrival time**.

> Food should be ready when the traveller reaches the restaurant — minimising their wait without
> cooking so early that it goes cold.

Both halves of that sentence matter. "Ready on arrival" is trivially satisfied by cooking
immediately and letting it sit; the product is the *timing*.

---

## Status — Modules 01–13 complete

A customer can sign in with a phone number, plan a journey, see the route,
discover restaurants along it, search and filter them, open one, read its menu,
configure a dish, add it to a cart, correct that cart, see what it costs, and
**choose when to collect it** — with the server deciding every price and every
time.

**What is still not built**, and no screen pretends otherwise: checkout,
payment, order creation, order numbers, pickup codes, the restaurant's
accept/reject and cooking workflows, live GPS tracking, notifications, and the
ETA engine. Module 13's travel figure comes from the planned route on the
assumption the customer sets off now — that is an approximation, and it is
labelled as one everywhere it appears.

| | Result |
| --- | --- |
| Automated tests | **1,914 passed** (1,081 backend · 833 mobile), plus 29 web |
| Static checks | Pint ✅ · TypeScript 0 errors ✅ · `dart analyze --fatal-infos` clean ✅ · `dart format` clean ✅ |
| Dependency audits | `composer audit` clean ✅ · `npm audit` 0 vulnerabilities ✅ |
| On-device | Android emulator and iOS simulator run the whole `integration_test/` directory in CI, against a real Laravel server and MySQL |
| Live server runs | Recorded as output per module in [`docs/evidence/`](docs/evidence/) |

Two things a reader should know before trusting the numbers above:

- **Nothing is claimed as passing on a device unless CI says so.** This
  development environment has no Android SDK and no macOS host, so a device
  result is whatever the emulator and simulator report — never what a commit
  message asserts.
- **The tax rate and both fees are nought.** The mechanism is built and tested
  with non-zero values; the figures are a business input and must be set before
  commercial launch.

Full evidence: [`docs/15-test-evidence.md`](docs/15-test-evidence.md).
Honest list of what is broken or missing: [`docs/13-known-issues.md`](docs/13-known-issues.md).

## Architecture

| Layer | Technology |
| --- | --- |
| Backend | Laravel 12 · PHP 8.4 |
| Database | MySQL 8 — source of truth for orders, payments, payouts |
| Cache / queues / locks | Redis 7 — deliberately treated as lossy |
| Web | React 19 · TypeScript · Vite — restaurant dashboard + admin panel |
| Mobile | Flutter 3.47 — one codebase, Android and iOS · Riverpod 3 · go_router |

```
backend/          Laravel API — all business rules live here
web/              npm workspaces: packages/ui + apps/{restaurant,admin}
mobile/           Flutter customer app
docs/             15 documents, including the requirements matrix
infrastructure/   deployment material
```

**Business rules live in the backend and nowhere else.** Three clients that each compute an ETA will
disagree, and the one the customer sees will not be the one the kitchen cooks to.

## Quick start

```bash
# Backend
cd backend && composer install && cp .env.example .env && php artisan key:generate
# create foodonthego_local + foodonthego_testing, set DB_PASSWORD, then:
php artisan migrate && php artisan serve            # :8000

# Web
cd web && npm install
npm run dev:restaurant                              # :5173
npm run dev:admin                                   # :5174

# Mobile
cd mobile && flutter pub get && flutter run
```

Use `localhost`, not `127.0.0.1` — `FRONTEND_URLS` is an exact-match CORS allow-list.

Full instructions: [`docs/03-development-setup.md`](docs/03-development-setup.md).

## Tests

```bash
cd backend && php artisan test        # 67
cd web     && npm test                # 29
cd mobile  && flutter test            # 82
```

Backend tests run against **real MySQL**, not SQLite: the schema uses MySQL types and later modules
will use MySQL locking semantics, so a SQLite run would pass against a schema production cannot
create.

## Documentation

| | |
| --- | --- |
| [01 Product overview](docs/01-product-overview.md) | What the product is, and why it is not delivery |
| [02 Architecture](docs/02-architecture.md) | Components and the rules that keep them coherent |
| [03 Development setup](docs/03-development-setup.md) | Getting it running |
| [04 Environments](docs/04-environments.md) | Five environments; refuse-to-boot guards |
| [05 API standards](docs/05-api-standards.md) | Envelope, error contract, idempotency, limits |
| [06 Database conventions](docs/06-database-conventions.md) | Keys, money, soft deletes, indexes |
| [07 Security](docs/07-security.md) | Roles, headers, CORS, log redaction |
| [08 Design system](docs/08-design-system.md) | Tokens, type, motion, icons, accessibility |
| [09 Testing strategy](docs/09-testing-strategy.md) | What is tested and what is not |
| [10 Deployment](docs/10-deployment.md) | Build artefacts and release checklist |
| [11 Requirements traceability](docs/11-requirements-traceability.md) | The permanent matrix |
| [12 Module status](docs/12-module-status.md) | Where every module stands |
| [13 Known issues](docs/13-known-issues.md) | Open blockers and 13 resolved defects |
| [14 Change log](docs/14-change-log.md) | What changed |
| [15 Test evidence](docs/15-test-evidence.md) | Real commands, real numbers, screenshots |
| [16 Mobile navigation](docs/16-mobile-navigation.md) | Riverpod, go_router, feature flags, fixture isolation |
| [17 Customer app UI](docs/17-customer-app-ui.md) | Screen hierarchy, components, animation, accessibility |

## Honest limitations

- **Android and iOS builds are unverified.** The Android SDK host is blocked by this environment's
  egress policy; iOS needs macOS. Marked PENDING, never as passed.
- **No PHP static analysis.** PHPStan could not be installed here. Pint runs in its place.
- **CI has never executed.** The workflow is written; the first run will surface whatever it surfaces.
- **Only `users` exists in the database.** Module-specific migrations arrive with their modules.
- **The mobile app has no backend integration.** A production build resolves to a repository that
  returns no journey and no order — the truthful state for an empty account. It never invents data.
