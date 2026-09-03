# FoodOnTheGo

**Route-based food pre-order and pickup.** A traveller enters an origin and a destination;
FoodOnTheGo finds restaurants on or near that route; the traveller orders before arriving; the
kitchen cooks against their **expected arrival time**.

> Food should be ready when the traveller reaches the restaurant — minimising their wait without
> cooking so early that it goes cold.

Both halves of that sentence matter. "Ready on arrival" is trivially satisfied by cooking
immediately and letting it sit; the product is the *timing*.

---

## Status — Module 01 complete

Module 01 is the **foundation only**: architecture, design system, API contract, database
conventions, security baseline, application shells, CI and documentation.

**No business feature is implemented.** No authentication, journey planner, restaurant search,
ordering, payments or ETA engine. Every shell route without a feature behind it renders a
placeholder that says so and names the module that will deliver it.

| | Result |
| --- | --- |
| Automated tests | **115 passed**, 0 failed, 0 skipped |
| Static checks | Pint ✅ · TypeScript 0 errors ✅ · `flutter analyze` clean ✅ |
| Dependency audits | `composer audit` clean ✅ · `npm audit` 0 vulnerabilities ✅ |
| Live API | MySQL 1.9 ms · Redis 0.59 ms, verified through a browser |
| Responsive | 8 widths × 2 shells, no overflow, no console errors |
| Android build | **PENDING** — SDK unreachable in this environment |
| iOS build | **PENDING** — requires macOS + Xcode |

Full evidence: [`docs/15-test-evidence.md`](docs/15-test-evidence.md).

## Architecture

| Layer | Technology |
| --- | --- |
| Backend | Laravel 12 · PHP 8.4 |
| Database | MySQL 8 — source of truth for orders, payments, payouts |
| Cache / queues / locks | Redis 7 — deliberately treated as lossy |
| Web | React 19 · TypeScript · Vite — restaurant dashboard + admin panel |
| Mobile | Flutter 3.47 — one codebase, Android and iOS |

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
cd mobile  && flutter test            # 19
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

## Honest limitations

- **Android and iOS builds are unverified.** The Android SDK host is blocked by this environment's
  egress policy; iOS needs macOS. Marked PENDING, never as passed.
- **No PHP static analysis.** PHPStan could not be installed here. Pint runs in its place.
- **CI has never executed.** The workflow is written; the first run will surface whatever it surfaces.
- **Only `users` exists in the database.** Module-specific migrations arrive with their modules.
