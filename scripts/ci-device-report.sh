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

LOG="${1:?usage: ci-device-report.sh <log> <exit-code> [label]}"
CODE="${2:?usage: ci-device-report.sh <log> <exit-code> [label]}"
LABEL="${3:-device}"

echo "=============================================================="
echo "flutter test exited $CODE"

if [ ! -f "$LOG" ]; then
  echo "NO LOG: $LOG was never written."
  # Annotated too, and this branch matters MORE than the others, not less. A log
  # that was never written is the KI-020 signature — the run died before Flutter
  # produced anything. Returning silently would make the most serious outcome
  # the only one that leaves no trace, and an absent annotation is indis-
  # tinguishable from nobody having looked. Found by a control that checked this
  # path and got nothing back.
  printf '::notice title=%s device tests::NO LOG — %s was never written (flutter test exited %s)\n' \
    "$LABEL" "$LOG" "$CODE"
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

# THE COUNT, AS AN ANNOTATION, WHICH IS THE ONLY PLACE IT CAN BE READ BACK.
#
# Everything above is printed for a human scrolling the job log. That works on
# iOS, where this step is the last thing to print. It does NOT work on Android:
# a second `android-emulator-runner` step follows this one to install and launch
# the review APK, booting a whole second emulator, and the job's own cleanup
# then adds a hundred lines of service-container logs. The report ends up far
# outside any log tail that can practically be fetched, which is why no Android
# device count had ever been read (KI-038).
#
# An annotation does not care where it sits in the log. The GitHub API serves it
# from /check-runs/<id>/annotations whatever ran afterwards.
#
# This is not a guess about whether that works. Flutter's own GitHub reporter
# already emits `::error::` on failure, and the resulting annotation IS readable
# on both platforms — including on Android, where it was emitted from inside the
# emulator action's `sh -c`. That is the proof that workflow commands from in
# there reach GitHub at all. What Flutter does NOT annotate is success: it
# prints `🎉 N tests passed.` as plain text. So failing counts have always been
# readable and passing counts never were, which is exactly backwards, since the
# passing count is the one worth recording.
#
# Hence one notice, on every run, pass or fail, under a stable title.
summary=$(grep -oE '[0-9]+ tests? passed(, [0-9]+ failed)?' "$LOG" | tail -n 1 || true)

if [ -z "$summary" ]; then
  # Said out loud rather than skipped. A missing summary means the run did not
  # reach Flutter's reporter — a crash, a hang, a device that never booted — and
  # an absent annotation would read as "nobody looked".
  summary='NO TEST SUMMARY IN THE LOG — the run did not reach the reporter'
fi

# Single line on purpose: a raw newline truncates an annotation message, and
# encoding one as %0A buys nothing for a one-line count.
printf '::notice title=%s device tests::%s (flutter test exited %s)\n' \
  "$LABEL" "$summary" "$CODE"
