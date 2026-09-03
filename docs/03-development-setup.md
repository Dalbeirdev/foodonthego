# 03 — Development setup

## Prerequisites

| Tool | Version used | Notes |
| --- | --- | --- |
| PHP | 8.4 | with `pdo_mysql`, `redis`, `mbstring`, `intl`, `zip` |
| Composer | 2.x | |
| MySQL | 8.0 | 8.0.46 verified |
| Redis | 7.x | 7.0.15 verified |
| Node.js | 22.5+ | |
| Flutter | 3.47 stable | Dart 3.13 |

## Backend

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
```

Create the databases and a development user:

```sql
CREATE DATABASE foodonthego_local   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE foodonthego_testing CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER 'fotg'@'127.0.0.1' IDENTIFIED BY 'choose-your-own';
GRANT ALL PRIVILEGES ON foodonthego_local.*   TO 'fotg'@'127.0.0.1';
GRANT ALL PRIVILEGES ON foodonthego_testing.* TO 'fotg'@'127.0.0.1';
```

Fill `DB_PASSWORD` in `.env`, then:

```bash
php artisan migrate
php artisan serve          # http://localhost:8000
```

Confirm it is really connected — this endpoint runs `SELECT 1` against MySQL and `PING` against
Redis, so a 200 here means the whole chain is up:

```bash
curl -s http://localhost:8000/api/v1/health/ready | jq
```

## Web

```bash
cd web
npm install
npm run dev:restaurant     # http://localhost:5173
npm run dev:admin          # http://localhost:5174
```

> **Use `localhost`, not `127.0.0.1`.** `FRONTEND_URLS` is an exact-match allow-list and the two are
> different origins to a browser. A CORS failure here is the allow-list working.

The admin panel's **System Health** page calls the real API. If it shows *API unreachable*, the
backend is not running or `VITE_API_BASE_URL` is wrong.

## Mobile

```bash
cd mobile
flutter pub get
flutter run                # a connected device or emulator
```

## Running everything at once

Four terminals: MySQL, Redis, `php artisan serve`, and the two Vite servers.

## Tests

```bash
cd backend && php artisan test        # 67 tests
cd web     && npm test                # 29 tests
cd mobile  && flutter test            # 19 tests
```

## Static checks

```bash
cd backend && vendor/bin/pint --test  # code style
cd web     && npm run typecheck       # TypeScript, all workspaces
cd mobile  && flutter analyze         # Dart analyzer
```
