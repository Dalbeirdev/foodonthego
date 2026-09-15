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

# How many requests the development server can answer at once. See KI-032 at
# the server block below for why this is not one, which is the default.
WORKERS="${FOTG_SERVE_WORKERS:-8}"

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
#
# KI-032. `php artisan serve` is PHP's built-in development server, and by
# default it is *one worker*: it accepts connections and then answers them
# strictly one at a time. The app does not ask one question at a time. Opening
# a screen cold fires the session, the trip, the route, the restaurant, the
# menu and the item together -- around nine requests in flight at once -- and
# on one worker the ninth waits for the sum of the eight in front of it.
#
# That is not a theory about the log, it is what the log says. On run 158 the
# same endpoints that answer in 0.04 ms when nothing else is in flight took
# 1s, 3s, 4s, 5s and 7s during a launch, in a rising staircase; ServeCommand
# starts its timer at `Accepted`, so the number it prints includes the wait,
# not just the work. The app gives up at ApiConfig.requestTimeout, ten
# seconds, and shows its error state -- which is exactly what the iOS job
# photographed: "We couldn't load this item", on a request the server went on
# to answer.
#
# Measured here, nine concurrent requests against the same endpoint on a
# four-core box:
#
#   one worker  0.012 0.023 0.034 0.046 0.056 0.067 0.078 0.090 0.101  (10 ms apart)
#   eight       0.012 0.013 0.022 0.023 0.032 0.043 0.054 0.066 0.077
#
# The single-worker column is a perfect staircase, which is the signature of a
# queue rather than of load. Worst case falls by about a third on a machine
# with four cores and a request that costs ten milliseconds; in CI, where the
# requests cost hundreds of milliseconds, the same queue is what turns a
# 0.04 ms endpoint into a 5 s one.
#
# --no-reload is not optional: Laravel refuses to honour PHP_CLI_SERVER_WORKERS
# without it and warns "Only creating a single server", which is how a fix
# like this fails silently. Nothing edits backend files while CI runs, so
# there is nothing for the reloader to do here anyway.
say 'starting the server'
PHP_CLI_SERVER_WORKERS="$WORKERS" php artisan serve --host=0.0.0.0 --port=8000 --no-reload \
  > "$ROOT/backend/storage/logs/serve.log" 2>&1 &

for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null http://127.0.0.1:8000/ 2>/dev/null; then break; fi
  sleep 1
done

if ! curl -fsS -o /dev/null http://127.0.0.1:8000/; then
  say 'the server never answered:'
  cat "$ROOT/backend/storage/logs/serve.log" >&2
  exit 1
fi

# The worker count is the whole point of the flags above, and Laravel declines
# it with a warning rather than an error -- so a version bump that renames or
# drops --no-reload would quietly put the device jobs back on one worker and
# the timeouts back with them. Say so at the top of the log instead, where the
# next person reading a device failure will see it.
if grep -q 'PHP_CLI_SERVER_WORKERS' "$ROOT/backend/storage/logs/serve.log"; then
  say 'WARNING: the server refused PHP_CLI_SERVER_WORKERS and is single-worker.'
  say '         Expect launch-storm timeouts on the device jobs (KI-032).'
  grep 'PHP_CLI_SERVER_WORKERS' "$ROOT/backend/storage/logs/serve.log" >&2
else
  say "serving with $WORKERS workers"
fi

# --- 4. a session ----------------------------------------------------------
# A device cannot complete sign-in by itself — the development OTP provider
# writes the code to a log file on the server and nothing hands it back over
# HTTP. So it is read here, on the machine that has the log.
say 'signing a persona in'
cd "$ROOT/mobile"
dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart --raw "$NATIONAL"
