<?php

declare(strict_types=1);

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Carbon;

abstract class TestCase extends BaseTestCase
{
    /**
     * The moment every test runs at, unless it says otherwise.
     *
     * Noon in Asia/Kolkata, on a Monday. Chosen because it is nowhere near an
     * opening time, a closing time, a midnight rollover or either
     * thirty-minute soon-threshold in the seeded fixtures — so a test about
     * cuisines or facilities or ownership is not quietly also a test about what
     * time the runner started.
     */
    private const NOW = '2026-09-07 06:30:00';

    /**
     * Time does not move during a test, and does not depend on when CI ran.
     *
     * **This was added after the fourth clock-dependent failure**, on the third
     * CI red caused by a commit that touched no backend code at all. Every one
     * was the same shape: a fixture seeded opening hours, an assertion about
     * something else entirely depended on the restaurant being shut, and the
     * runner happened to start inside the window. Three greps for the pattern
     * each missed one, because the assertions do not look alike — one compared
     * an availability string, one an ordering state, one a *list of restaurant
     * names* with no time in it anywhere.
     *
     * A test that passes at noon and fails at 02:08 is not a flaky test. It is
     * a test with an unstated dependency, and freezing the clock is what states
     * it.
     *
     * **This does not weaken the time-related coverage, and must not be allowed
     * to.** The bugs found this way were real — a twenty-four-hour dhaba
     * announcing "closing soon" every night was found precisely because CI ran
     * at 23:32 local. But finding them depended on a lottery: the right test
     * running in the right half hour. The replacement is deliberate rather than
     * lucky — tests pinned to the exact instants that matter, including the two
     * that broke this suite, in RestaurantAvailabilityTest and
     * TripRestaurantApiTest. A boundary worth checking is worth checking on
     * every run, not one run in forty-eight.
     *
     * A test that needs a different moment calls `Carbon::setTestNow()` itself
     * and says why; Laravel clears it after each test.
     */
    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow(self::NOW);
    }
}
