# FoodOnTheGo — project memory

Route-based food pre-order and pickup. A customer plans a journey, discovers
restaurants along it, orders ahead, pays, and collects at a time the server says
is reachable.

## Current state

**Branch:** `claude/foodonthego-s0x2vt` · **PR:** [#1](https://github.com/Dalbeirdev/foodonthego/pull/1) (draft)
**Modules 01–17 complete. Module 18 (ETA Engine v1) is NOT started** — Module 17's
brief ends "STOP. DO NOT START MODULE 18. Wait for explicit approval." That still
stands; no Module 18 specification has been supplied.

### CI — last verified state

Commit `1026fe3`, verified 2026-09-10 against the GitHub API (not inferred):

| Run | Event | Result |
| --- | --- | --- |
| 34486169856 | `pull_request` | **success — 7/7** |
| 34486164760 | `push` | success |
| 34486164771 | `push` (deploy) | success |

An earlier commit's PR run shows `cancelled`. That is the documented behaviour —
**each push cancels the in-flight PR run** — not a failure.

The `pull_request` run is the authoritative one: **device jobs only run on
`pull_request` and `main`**, and each push cancels the in-flight PR run. All seven
jobs green — Backend, Web, Mobile Flutter, iOS build, iOS simulator, Android review
build, Android emulator.

Backend job step order, all green:
`Pint → Static analysis (PHPStan + Larastan) → Migrate → Test → composer audit`.

### Totals at `8170e28`

| Suite | Count |
| --- | --- |
| Backend (PHPUnit, real MySQL) | **1,305 passed**, 5,826 assertions |
| Flutter (widget + unit) | 986 passed |
| On-device (integration_test) | 29 per platform, both platforms green |
| Static analysis | PHPStan level 3, **0 errors** |

The suite includes an eight-process parallel race against one order (KI-029), and it
passes on GitHub's runners as well as locally — worth knowing before anyone assumes a
timing-sensitive test is too fragile for CI.

## Commands

```bash
# Backend (from backend/) — MySQL and Redis must be running
DB_USERNAME=root DB_PASSWORD=root php artisan test
vendor/bin/pint --test
composer analyse                      # PHPStan + Larastan, level 3

# Mobile (from mobile/) — export PATH="$PATH:/opt/flutter/bin"
flutter test && flutter analyze --fatal-infos

# Local infra, which does not survive a container restart
mysqld_safe &                         # root/root
redis-server --daemonize yes
```

## Things that will otherwise cost an hour

- **MySQL and Redis die on container restart.** A wall of failing tests is almost
  always this, not the code. Check `pgrep -x mysqld` first.
- **PHPStan caches aggressively** and does not always notice a changed model cast.
  `vendor/bin/phpstan clear-result-cache` if results look like the previous commit's.
  Cost an hour twice during adoption. CI uses no cache.
- **`phpstan/phpstan` cannot be installed in this dev container** — GitHub access is
  scoped to this repository and the package is published dist-only. This is not a
  project problem; CI installs it normally. See KI-003.
- **`php artisan serve` is single-worker** unless given both `PHP_CLI_SERVER_WORKERS`
  and `--no-reload`; Laravel declines the variable silently without the flag. This is
  what `scripts/ci-backend-up.sh` exists for (KI-032).

## Standing rules

- **Use actual values. Do not invent.** No commercial rule — tax, fee, commission,
  cancellation policy — is ever invented. Where nothing is configured, the response
  carries no row for it.
- **Never fabricate credentials.** `NOT YET IMPLEMENTED — DO NOT PROVIDE FAKE
  CREDENTIAL`. Never report localhost as a public review URL.
- **Never claim a device pass that did not run.** `PENDING — environment unavailable`.
- **The client never sends a price**, and there is no field in which one could arrive.
- **The app displays order state; it does not decide it.** No customer route writes a
  status, and a test walks the router to keep it that way.
- **One response, one clock.** Every instant in a response body is on the same clock.
- **A green result is worth nothing until a negative control has been seen to fail.**
  And a control that stays silent has told you something — find out what.
- **When a test fails, ask what the harness was doing before asking what the code was
  doing.** Five instances so far, all harness.

## Where the record lives

`docs/` is the project's real memory; this file is the index to it.

| | |
| --- | --- |
| `docs/12-module-status.md` | what is built |
| `docs/11-requirements-traceability.md` | requirement → code → test |
| `docs/13-known-issues.md` | the honest list, including what was closed and why |
| `docs/15-test-evidence.md` | verification totals and evidence runs |
| `docs/30-client-review-package.md` | the handover |

**Known issues decay.** Two entries were re-read recently and both had become wrong
about their own subject: KI-008 described one profile endpoint while the gap had grown
to cover payment, and KI-003 blamed the network for a restriction that was a repository
scope. An entry records the system as it was the day it was written.

## Git

Develop and push only on `claude/foodonthego-s0x2vt`; always
`git push -u origin <branch>`; retry network failures with exponential backoff.
