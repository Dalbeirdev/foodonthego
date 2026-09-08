#!/bin/sh
# What a device test run actually did, said in the step that ran it.
#
# Four runs were spent not knowing which assertion failed, and the fifth knew
# ("26 tests passed, 1 failed") without saying which one. Every attempt to put
# that answer in a later step has been unreadable from where I read logs: a job
# log comes back to me as its tail, and anything a later step prints has landed
# outside it or, on the last run, not appeared in the log at all despite the
# step being recorded as a success.
#
# So the report is printed by the step that runs the tests, as the last thing
# it does, and it is bounded. The full log is kept as an artifact for anyone
# who wants the rest.
#
# POSIX sh on purpose. The Android job runs its script through the emulator
# action's `sh -c`, which is dash on these runners, and a bashism here would
# die before an emulator booted — that has already happened once.
set -u

LOG="${1:?usage: ci-device-report.sh <log> <exit-code>}"
CODE="${2:?usage: ci-device-report.sh <log> <exit-code>}"

echo "=============================================================="
echo "flutter test exited $CODE"

if [ ! -f "$LOG" ]; then
  echo "NO LOG: $LOG was never written."
  exit 0
fi

echo "log: $(wc -l < "$LOG") lines, $(wc -c < "$LOG") bytes"
echo "=============================================================="

# Which test failed, by name. The device reporter prints one line per test
# prefixed with a tick or a cross, so the cross lines are the answer and there
# is no need to reconstruct it from a stack trace.
echo '--- tests that did not pass'
failed=$(grep -nE '^(❌|✕|✗)' "$LOG" || true)
if [ -n "$failed" ]; then
  printf '%s\n' "$failed"
else
  echo '(no per-test failure marker found)'
fi

# The assertion itself, and the widget-tree dump matchers leave behind.
echo '--- assertions'
detail=$(grep -nE '\[E\]|Expected:|Actual:|Which:|Timed out waiting for|On screen instead:|EXCEPTION CAUGHT|The following .* was thrown' "$LOG" || true)
if [ -n "$detail" ]; then
  printf '%s\n' "$detail" | head -n 60
else
  echo '(nothing matched — the failure is not a Dart assertion)'
fi

echo '--- how it ended'
tail -n 40 "$LOG"
echo "=============================================================="
