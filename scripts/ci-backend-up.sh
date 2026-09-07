#!/usr/bin/env bash
#
# Brings up a real backend for the on-device CI jobs, and prints a session token.
#
# The device runs under `integration_test/`, which talks to a live Laravel
# server writing real rows — that is the whole point of it, and it is why these
# jobs cannot be a `flutter test` with a fake repository behind them.
#
# Both callers (Android emulator, iOS simulator) need exactly the same six
# things, so they live here rather than being written out twice and drifting.
#
# Usage:  scripts/ci-backend-up.sh <phone-national-number>
# Prints: the session token, and nothing else, on stdout.
#
# Everything informational goes to stderr so the caller can do:
#   TOKEN="$(scripts/ci-backend-up.sh 9999900911)"

set -euo pipefail

NATIONAL="${1:-9999900911}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { printf '  %s\n' "$*" >&2; }

# --- 1. configuration ------------------------------------------------------
cd "$ROOT/backend"

cp .env.example .env
php artisan key:generate --quiet

# The development providers: OTP to a log file, places and routes computed
# locally. No third-party key is needed, and no billed call is made.
{
  echo 'APP_ENV=local'
  echo 'DB_HOST=127.0.0.1'
  echo 'DB_DATABASE=foodonthego_testing'
  echo 'DB_USERNAME=root'
  echo 'DB_PASSWORD=root'
  echo 'REDIS_HOST=127.0.0.1'
  echo 'OTP_PROVIDER=log'
  echo 'PLACES_PROVIDER=development'
  echo 'ROUTE_PROVIDER=development'
} >> .env

# --- 2. schema and fixtures ------------------------------------------------
say 'migrating'
php artisan migrate --force --quiet

# Order matters: the menu seeder attaches to restaurants the discovery seeder
# creates, and warns rather than inventing a partner if they are missing.
say 'seeding discovery and menu fixtures'
php artisan db:seed --class=DiscoveryTestRestaurantSeeder --force --quiet
php artisan db:seed --class=MenuTestDataSeeder --force --quiet

# --- 3. the server ---------------------------------------------------------
# Bound to 0.0.0.0 so the Android emulator can reach it on 10.0.2.2.
say 'starting the server'
php artisan serve --host=0.0.0.0 --port=8000 > "$ROOT/backend/storage/logs/serve.log" 2>&1 &

for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null http://127.0.0.1:8000/ 2>/dev/null; then break; fi
  sleep 1
done

if ! curl -fsS -o /dev/null http://127.0.0.1:8000/; then
  say 'the server never answered:'
  cat "$ROOT/backend/storage/logs/serve.log" >&2
  exit 1
fi

# --- 4. a session ----------------------------------------------------------
# A device cannot complete sign-in by itself — the development OTP provider
# writes the code to a log file on the server and nothing hands it back over
# HTTP. So it is read here, on the machine that has the log.
say 'signing a persona in'
cd "$ROOT/mobile"
dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart --raw "$NATIONAL"
