#!/usr/bin/env bash
#
# Everything CI checks that can be checked without CI's services.
#
# WHY THIS EXISTS. Two pushes in one session went red on a formatter — `dart
# format` once, `vendor/bin/pint` once — after the tests and the analyzer had
# been run and reported clean. Each cost a CI cycle on a branch whose whole
# point that week was keeping CI honest, and after the first one the stated fix
# was "remember to run the formatter", which is not a fix. This is.
#
# It deliberately does NOT stop at the first failure. A run that dies on Pint
# tells you nothing about the analyzer, and the second push is then as blind as
# the first; every check runs, and the summary at the end lists all of them.
#
# What it cannot cover, said plainly rather than skipped silently: anything
# needing MySQL or Redis (the backend's own test suite, PHPStan's database
# reflection) and anything needing a device. Those belong to CI, and this script
# names them as UNCHECKED rather than passing them by default.

set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

PASS=(); FAIL=(); SKIP=()

run() {                       # run <label> <dir> <command...>
  local label=$1 dir=$2; shift 2
  printf '\n\033[1m=== %s\033[0m\n' "$label"

  if [ ! -d "$ROOT/$dir" ]; then
    SKIP+=("$label — $dir is not present")
    echo "skipped: no $dir"
    return
  fi

  if ( cd "$ROOT/$dir" && "$@" ); then
    PASS+=("$label")
  else
    FAIL+=("$label")
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- mobile ----------------------------------------------------------------
if have flutter; then
  run 'mobile · format'  mobile dart format --output=none --set-exit-if-changed .
  run 'mobile · analyze' mobile flutter analyze --fatal-infos
  run 'mobile · test'    mobile flutter test
else
  SKIP+=('mobile — flutter is not on PATH (try: export PATH="$PATH:/opt/flutter/bin")')
fi

# --- backend ---------------------------------------------------------------
if [ -f backend/vendor/bin/pint ]; then
  run 'backend · style (Pint)' backend vendor/bin/pint --test
else
  SKIP+=('backend — vendor/ is absent; run composer install')
fi

if [ -f backend/vendor/bin/phpunit ]; then
  # By PATH, not by --filter. The first draft filtered on
  # 'ImageBuildDoesNotBootTheApp|StructuredLogging|Money|PhoneNormalizer' to pick
  # up "the tests that need no database" — but --filter matches METHOD names as
  # well as class names, so `test_money_stays_in_integer_minor_units_at_every_step`
  # matched "Money" and pulled in half the suite. Guessing which tests are
  # database-free is not worth doing; this names the one file that guards the
  # deploy and leaves the rest to CI, which has a database.
  run 'backend · the deploy Dockerfile guard' backend \
    vendor/bin/phpunit tests/Unit/ImageBuildDoesNotBootTheAppTest.php
fi
SKIP+=('backend — the test suite and PHPStan need MySQL and Redis; CI runs those')

# --- web -------------------------------------------------------------------
if [ -d web/node_modules ]; then
  run 'web · typecheck and test' web npm test --silent
else
  SKIP+=('web — node_modules is absent; run npm install in web/')
fi

# --- summary ---------------------------------------------------------------
printf '\n\033[1m=== preflight ===\033[0m\n'
for p in "${PASS[@]:-}"; do [ -n "$p" ] && printf '  \033[32mpass\033[0m  %s\n' "$p"; done
for s in "${SKIP[@]:-}"; do [ -n "$s" ] && printf '  \033[33mskip\033[0m  %s\n' "$s"; done
for f in "${FAIL[@]:-}"; do [ -n "$f" ] && printf '  \033[31mFAIL\033[0m  %s\n' "$f"; done

if [ "${#FAIL[@]}" -gt 0 ]; then
  printf '\n%d check(s) failed. Do not push.\n' "${#FAIL[@]}"
  exit 1
fi

printf '\nAll runnable checks passed. Skipped ones are listed above and are not a pass.\n'
