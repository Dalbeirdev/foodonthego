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
flutter run --dart-define=FOTG_API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's alias for the host machine — it is the default, and it is what
a developer running `php artisan serve` actually needs, because `localhost` inside an emulator is
the emulator. On an iOS simulator use `http://localhost:8000`; on a physical handset use the
machine's LAN address.

### Signing in during development

Set `OTP_PROVIDER=log` in `backend/.env` (it is the default in `.env.example`). Codes are then
written to `backend/storage/logs/otp-development.log` — a dedicated channel, so they never reach the
structured application log:

```bash
tail -f backend/storage/logs/otp-development.log
```

Use a number from the reserved test range (`+919999900000`–`+919999999999`) so a code can never
reach a real person's handset. The development sender refuses to be constructed in production, and a
production or staging boot fails outright while it is configured — see
[18-customer-authentication.md](18-customer-authentication.md).

### Checking the app really talks to the API

```bash
cd mobile
dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/integration_smoke.dart
```

This drives the app's own network layer against a running backend and a real MySQL database — no
mocks. It is a `dart run` rather than a `flutter test` because `flutter_test` replaces `HttpClient`
with a mock and could not make a real request.

## Running everything at once

Four terminals: MySQL, Redis, `php artisan serve`, and the two Vite servers.

## Tests

```bash
cd backend && php artisan test        # 197 tests
cd web     && npm test                # 29 tests
cd mobile  && flutter test            # 154 tests
```

## Static checks

```bash
cd backend && vendor/bin/pint --test  # code style
cd web     && npm run typecheck       # TypeScript, all workspaces
cd mobile  && flutter analyze --fatal-infos
cd mobile  && dart format --set-exit-if-changed .
```
