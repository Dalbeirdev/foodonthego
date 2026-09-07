<?php

declare(strict_types=1);

namespace Tests\Support;

use Illuminate\Support\Facades\DB;

/**
 * Measures a request's query count once the session has stopped warming up.
 *
 * The performance tests all ask the same question — "does this cost more when
 * there is more of it?" — by measuring two requests and comparing the counts.
 * That comparison is only meaningful if both requests are equally warm, and
 * they are not: the first requests of a session populate things that have
 * nothing to do with the thing under test, among them the token lookup, the
 * rate limiter's bucket and the ordering context's cache entry.
 *
 * Each of these tests dealt with that by making one un-measured request first.
 * One is not always enough. How much is still cold at the second request
 * depends on what ran before the test in the same process, so the counts drift
 * by exactly one, in either direction, depending on test order — which is why
 * the suite passed on a developer's machine for eleven modules and failed on
 * CI's first run, and why the same failure pointed at the larger menu on one
 * machine and the smaller one on another.
 *
 * Repeating until two consecutive counts agree measures the thing rather than
 * the session. It weakens no assertion: an N+1 moves a count by the number of
 * rows, never by one, so a settled count catches it exactly as before.
 */
trait SettlesQueryCounts
{
    /**
     * Both sides of a comparison must be settled, not just the first.
     *
     * Settling only the baseline was tried and was not enough: the drift is not
     * confined to the start of a session, so the *second* measurement can be
     * the one that costs an extra query. Comparing two settled measurements is
     * what makes the comparison about the data rather than about which request
     * happened to warm what.
     *
     * @param  callable(): array{0: int, 1: float}  $measure  a per-test helper
     *                                                        returning queries and milliseconds
     * @return array{0: int, 1: float}
     */
    protected function settledCost(callable $measure, int $attempts = 12): array
    {
        $previous = null;
        $agreements = 0;

        for ($i = 0; $i < $attempts; $i++) {
            $measurement = $measure();

            // Three in a row, not two. Two was tried and still flaked: the
            // drift is occasional rather than confined to the first request,
            // so a single pair can agree by luck and the next measurement
            // still differ.
            $agreements = $measurement[0] === $previous ? $agreements + 1 : 0;

            if ($agreements >= 2) {
                return $measurement;
            }

            $previous = $measurement[0];
        }

        // Never settled. Returning the last measurement keeps the assertion the
        // test's own, rather than failing here with a message about warm-up
        // that would hide what the test was actually checking.
        return $measurement;
    }

    protected function settledQueryCount(callable $measure, int $attempts = 12): int
    {
        return $this->settledCost($measure, $attempts)[0];
    }

    /**
     * How many of a request's queries touched the tables under test.
     *
     * Settling made the whole-request counts *mostly* stable and that is not
     * good enough for an assertion: a test that passes four runs in five is a
     * test nobody will trust the fifth time.
     *
     * The drift was never in the thing being measured. A menu is two queries
     * whether it holds one dish or five hundred; what moves by one is the
     * session preamble around it — the trip, its selected route, the staleness
     * check, the ordering context — depending on what an earlier test in the
     * same process left resolved. Counting only the queries that name the
     * tables under test measures the claim the test actually makes, and is
     * deterministic by construction rather than by repetition.
     *
     * It is not a weaker assertion. An N+1 over rows shows up here exactly as
     * before, because an N+1 queries the same table once per row.
     *
     * @param  callable(): mixed  $measure  a per-test helper that issues the request
     * @param  list<string>  $tables
     */
    protected function queriesTouching(callable $measure, array $tables): int
    {
        $measure();

        $touched = 0;

        foreach (DB::getQueryLog() as $entry) {
            $sql = strtolower((string) ($entry['query'] ?? ''));

            foreach ($tables as $table) {
                if (str_contains($sql, '`'.$table.'`')) {
                    $touched++;

                    break;
                }
            }
        }

        return $touched;
    }
}
