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
cd mobile  && flutter test            # 155 tests
```

## Static checks

```bash
cd backend && vendor/bin/pint --test  # code style
cd web     && npm run typecheck       # TypeScript, all workspaces
cd mobile  && flutter analyze --fatal-infos
cd mobile  && dart format --set-exit-if-changed .
```

---

## Seeding a menu (Module 10)

```bash
php artisan db:seed --class=DiscoveryTestRestaurantSeeder --force
php artisan db:seed --class=MenuTestDataSeeder --force
```

Order matters — the menu seeder attaches to restaurants the discovery seeder
creates, and warns rather than inventing a partner if they are missing.

Both refuse to run when `APP_ENV=production`, mark everything they create with
`[TEST]`, and are **not** in `DatabaseSeeder`. Re-running is safe: each clears
its own rows first (the menu seeder deletes items before categories, because the
composite foreign key holds them together).

### Two environment gotchas worth knowing

**MySQL and Redis stop when the container idles.** `service mysql start` and
`service redis-server start` bring them back. `redis-cli -n 1 FLUSHDB` clears
the discovery cache; `redis-cli FLUSHALL` also clears the OTP per-IP budget,
which a long driver run will exhaust.

**The live-view driver and the smoke suite share a database and must not run at
the same time.** `restaurant_detail_smoke` re-seeds the discovery fixtures,
which recreates the restaurant rows — and menu rows cascade-delete with their
restaurant. Running both at once will empty a menu underneath a driver that is
halfway through asserting on it.

---

## Seeding customization and carts (Module 11)

The same seeder does it. `MenuTestDataSeeder` now also creates the variants,
modifier groups and options Module 11 needs:

```bash
php artisan db:seed --class=DiscoveryTestRestaurantSeeder --force
php artisan db:seed --class=MenuTestDataSeeder --force
```

What it gives you, and why each one exists:

| Fixture | Shape | What it is there to prove |
| --- | --- | --- |
| Paneer Tikka | Regular ₹249 (default), Large ₹329, Family ₹549 (unavailable) | A default size; a sold-out size that must still be visible and inert |
| Masala Chai | 150 ml ₹49, 250 ml ₹69, **no default** | The dish that opens with the button reading *"Choose required options"* |
| Spice level | 1–1, Mild (free, default), Medium, Hot | A required question whose configured default costs nothing |
| Add extras | 0–2, Extra Paneer ₹60, Extra Cheese ₹40, Jalapeños ₹20, Extra Cashew ₹80 (unavailable) | Optional, a ceiling to hit, and a sold-out option |
| Pick your sides | 2–4, attached to no dish | A group whose minimum is above one, for the API tests |
| Papad | no variants, no groups | A dish that adds in one tap |

Clearing is ordered: pivot → options → groups → variants → items → categories.
Anything else trips the composite foreign keys, which is the point of them.

Carts are not seeded. A cart belongs to a customer and a trip, and both of those
come from signing in and planning a journey — a seeded cart would be a cart
nobody's phone knows about. To clear them between runs:

```bash
mysql -N -B foodonthego_local -e 'DELETE FROM carts;'
```

Cart items and their modifier snapshots cascade with the cart.

### Reading a cart back

The rows a driver writes are worth looking at directly, because they are the
proof that the server priced the line rather than the phone:

```bash
mysql -N -B --default-character-set=utf8mb4 foodonthego_local \
  -e 'SELECT quantity, unit_price_minor, line_total_minor, special_instructions FROM cart_items;'
```

`--default-character-set=utf8mb4` is not optional. A special instruction can
contain Devanagari or an emoji, and without it `mysql` hands back bytes that
decode to a `FormatException` rather than the note the customer typed.

---

## Running the app on a device (`integration_test/`)

`test/` holds widget tests, which run against repositories we wrote. `tool/`
holds smoke drivers, which run this app's network layer against a live server.
`integration_test/` is the third thing: **the real app, on a real device,
against a live server.** It is what an Android or iOS runtime verification is
made of.

### Why it needs a token

A handset cannot complete sign-in by itself. `LogOtpProvider` writes the code to
a log file on the *server* and there is deliberately no endpoint that hands it
back — that absence is what makes the provider unusable in production, and it is
not going to be loosened to make a test convenient.

So the code is read on the machine that has the log, and the session token is
passed to the device:

```bash
# On the machine running the backend
php artisan serve --host=0.0.0.0 --port=8000
php artisan db:seed --class=DiscoveryTestRestaurantSeeder --force
php artisan db:seed --class=MenuTestDataSeeder --force

cd mobile
dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart
```

It prints an ordinary Sanctum token for an ordinary test persona.

### On a device or emulator

```bash
flutter devices           # confirm one is attached

flutter test integration_test/ \
  --dart-define=FOTG_API_BASE_URL=http://192.168.1.20:8000 \
  --dart-define='FOTG_TEST_TOKEN=369|…'
```

Three things that will otherwise waste an afternoon:

| Trap | What to do |
| --- | --- |
| The token contains a `\|` | **Quote it.** Unquoted, the shell reads it as a pipe. |
| The device cannot reach `127.0.0.1` | Use `10.0.2.2` for an Android emulator, `127.0.0.1` for an iOS simulator, the host's **LAN address** for a physical handset — and bind the backend to `0.0.0.0`, not `127.0.0.1`. |
| Cleartext HTTP | Fine in the debug build `flutter test` produces. A release build refuses it, and should. |

### Without a device

`flutter test integration_test/` needs an attached device. `flutter drive` does
not — it can run the same target in a browser, which is how these drivers are
checked on a machine with no Android SDK:

```bash
chromedriver --port=4447 &

CHROME_EXECUTABLE=/path/to/chrome flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/module_11_add_to_cart_test.dart \
  -d web-server --browser-name=chrome --driver-port=4447 \
  --web-browser-flag=--headless=new \
  --dart-define=FOTG_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define='FOTG_TEST_TOKEN=…'
```

`chromedriver`'s major version must match the browser's, or the session is
refused with *"This version of ChromeDriver only supports Chrome version N"*.
Matching builds are at
`https://storage.googleapis.com/chrome-for-testing-public/<version>/linux64/chromedriver-linux64.zip`.

**A browser run proves the driver and the flow. It does not prove Android or
iOS**, and no report should read as if it did.
