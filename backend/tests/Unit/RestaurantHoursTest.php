<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Models\Restaurant;
use App\Services\Discovery\RestaurantAvailabilityService;
use App\Services\Restaurant\RestaurantHoursService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The opening schedule, read the way a customer reads it.
 *
 * Every assertion here fixes the clock. A test about opening hours that depends
 * on the hour it runs is a test that fails once a day and gets deleted.
 */
final class RestaurantHoursTest extends TestCase
{
    use RefreshDatabase;

    private RestaurantHoursService $hours;

    protected function setUp(): void
    {
        parent::setUp();

        $this->hours = app(RestaurantHoursService::class);
    }

    /** @param array<int, list<array{0: string, 1: string}>> $schedule */
    private function restaurant(array $schedule, string $timezone = 'Asia/Kolkata'): Restaurant
    {
        $restaurant = Restaurant::factory()->discoverable()->create(['timezone' => $timezone]);

        foreach ($schedule as $day => $windows) {
            foreach ($windows as $window) {
                $restaurant->openingHours()->create([
                    'day_of_week' => $day,
                    'opens_at' => $window[0],
                    'closes_at' => $window[1],
                ]);
            }
        }

        return $restaurant->load('openingHours');
    }

    /** A moment in Indian local time, expressed as the UTC instant it is. */
    private function at(string $local, string $timezone = 'Asia/Kolkata'): CarbonImmutable
    {
        return CarbonImmutable::parse($local, $timezone)->utc();
    }

    // --- today ---------------------------------------------------------------

    public function test_today_is_the_restaurants_today_not_the_servers(): void
    {
        // 2026-09-07 is a Monday, so day_of_week 0.
        $restaurant = $this->restaurant([0 => [['08:00:00', '22:00:00']]]);

        // 23:30 UTC on Sunday is already 05:00 Monday in Kolkata.
        $today = $this->hours->today($restaurant, $this->at('2026-09-06 23:30', 'UTC'));

        $this->assertSame([[
            'opens_at' => '08:00:00',
            'closes_at' => '22:00:00',
            'is_overnight' => false,
        ]], $today);
    }

    public function test_a_split_service_is_two_windows_not_one_long_one(): void
    {
        $restaurant = $this->restaurant([
            0 => [['18:00:00', '23:00:00'], ['11:00:00', '15:00:00']],
        ]);

        $today = $this->hours->today($restaurant, $this->at('2026-09-07 12:00'));

        // Sorted by opening time, whatever order the rows came back in. A
        // kitchen that shuts between lunch and dinner is not open at four.
        $this->assertSame(['11:00:00', '18:00:00'], array_column($today, 'opens_at'));
    }

    public function test_a_window_that_opened_yesterday_is_not_todays_hours(): void
    {
        $restaurant = $this->restaurant([0 => [['18:00:00', '02:00:00']]]);

        // 01:00 on Tuesday. Monday's window is still running — but under the
        // heading "Today" a customer would read "18:00 – 02:00" as tonight.
        $today = $this->hours->today($restaurant, $this->at('2026-09-08 01:00'));

        $this->assertSame([], $today);
    }

    // --- the week ------------------------------------------------------------

    public function test_the_week_has_seven_days_including_the_shut_ones(): void
    {
        $restaurant = $this->restaurant([
            1 => [['09:00:00', '17:00:00']],
            2 => [['09:00:00', '17:00:00']],
        ]);

        $week = $this->hours->week($restaurant, $this->at('2026-09-07 10:00'));

        $this->assertCount(7, $week);
        $this->assertSame([0, 1, 2, 3, 4, 5, 6], array_column($week, 'day_of_week'));

        // A closed day is an empty list, not a missing row. "We are shut on
        // Mondays" is information; a gap is a question.
        $this->assertSame([], $week[0]['windows']);
        $this->assertCount(1, $week[1]['windows']);
    }

    public function test_the_week_marks_which_day_is_today(): void
    {
        $restaurant = $this->restaurant([3 => [['09:00:00', '17:00:00']]]);

        // 2026-09-10 is a Thursday: day 3.
        $week = $this->hours->week($restaurant, $this->at('2026-09-10 10:00'));

        $this->assertSame([3], array_keys(array_filter(
            array_column($week, 'is_today'),
        )));
    }

    // --- open right now ------------------------------------------------------

    public function test_an_overnight_window_is_open_after_midnight(): void
    {
        $restaurant = $this->restaurant([0 => [['18:00:00', '02:00:00']]]);

        // The bug this fixture exists for: at 01:00 on Tuesday the window that
        // covers you opened on Monday.
        $window = $this->hours->currentWindow($restaurant, $this->at('2026-09-08 01:00'));

        $this->assertNotNull($window);
        $this->assertSame('18:00:00', $window['opens_at']);
        $this->assertSame('02:00:00', $window['closes_at']);
    }

    public function test_an_overnight_window_closes_tomorrow_not_in_the_past(): void
    {
        $restaurant = $this->restaurant([0 => [['18:00:00', '02:00:00']]]);

        $window = $this->hours->currentWindow($restaurant, $this->at('2026-09-07 20:00'));

        // 02:00 the following morning, not 02:00 today, which has been and gone.
        $this->assertSame(
            $this->at('2026-09-08 02:00')->toIso8601String(),
            CarbonImmutable::parse($window['closes_at_utc'])->toIso8601String(),
        );
    }

    public function test_the_gap_in_a_split_service_is_shut(): void
    {
        $restaurant = $this->restaurant([
            0 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
        ]);

        $this->assertNotNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 12:00')));
        $this->assertNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 16:30')));
        $this->assertNotNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 19:00')));
    }

    public function test_the_opening_minute_is_open_and_the_closing_minute_is_not(): void
    {
        $restaurant = $this->restaurant([0 => [['08:00:00', '22:00:00']]]);

        // Inclusive at the open, exclusive at the close. A restaurant is not
        // still open at the instant it closes, and a customer arriving exactly
        // then has arrived too late.
        $this->assertNotNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 08:00:00')));
        $this->assertNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 07:59:59')));
        $this->assertNotNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 21:59:59')));
        $this->assertNull($this->hours->currentWindow($restaurant, $this->at('2026-09-07 22:00:00')));
    }

    // --- next opening --------------------------------------------------------

    public function test_it_says_when_a_shut_restaurant_opens_again(): void
    {
        $restaurant = $this->restaurant([
            0 => [['08:00:00', '22:00:00']],
            1 => [['08:00:00', '22:00:00']],
        ]);

        $next = $this->hours->nextOpenAt($restaurant, $this->at('2026-09-07 23:00'));

        $this->assertNotNull($next);
        $this->assertSame('2026-09-08 08:00:00', $next->format('Y-m-d H:i:s'));
    }

    public function test_the_next_opening_today_beats_the_one_tomorrow(): void
    {
        $restaurant = $this->restaurant([
            0 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
        ]);

        $next = $this->hours->nextOpenAt($restaurant, $this->at('2026-09-07 16:00'));

        $this->assertSame('2026-09-07 18:00:00', $next->format('Y-m-d H:i:s'));
    }

    public function test_it_skips_the_days_the_restaurant_is_shut(): void
    {
        // Open only on Fridays (day 4).
        $restaurant = $this->restaurant([4 => [['09:00:00', '17:00:00']]]);

        // Asked on a Monday.
        $next = $this->hours->nextOpenAt($restaurant, $this->at('2026-09-07 10:00'));

        $this->assertSame('2026-09-11 09:00:00', $next->format('Y-m-d H:i:s'));
    }

    public function test_a_restaurant_open_only_today_wraps_to_next_week(): void
    {
        $restaurant = $this->restaurant([0 => [['09:00:00', '17:00:00']]]);

        // Monday evening, after closing. The next opening is next Monday, which
        // is seven days away — the reason the lookahead is eight and not seven.
        $next = $this->hours->nextOpenAt($restaurant, $this->at('2026-09-07 18:00'));

        $this->assertSame('2026-09-14 09:00:00', $next->format('Y-m-d H:i:s'));
    }

    public function test_an_open_restaurant_is_not_told_when_it_opens(): void
    {
        $restaurant = $this->restaurant([0 => [['08:00:00', '22:00:00']]]);

        // "Opens at 8" is not a useful thing to say to somebody in the doorway.
        $this->assertNull($this->hours->nextOpenAt($restaurant, $this->at('2026-09-07 12:00')));
    }

    public function test_no_hours_on_file_means_no_opening_time_rather_than_a_guess(): void
    {
        $restaurant = $this->restaurant([]);

        $this->assertNull($this->hours->nextOpenAt($restaurant, $this->at('2026-09-07 12:00')));
        $this->assertSame([], $this->hours->today($restaurant, $this->at('2026-09-07 12:00')));
    }

    // --- timezone ------------------------------------------------------------

    public function test_the_restaurants_timezone_decides_not_the_servers(): void
    {
        $restaurant = $this->restaurant([0 => [['08:00:00', '22:00:00']]]);

        // 04:00 UTC on Monday is 09:30 in Kolkata — open. A server reading its
        // own clock would call it shut.
        $this->assertNotNull(
            $this->hours->currentWindow($restaurant, $this->at('2026-09-07 04:00', 'UTC')),
        );

        // 18:00 UTC is 23:30 in Kolkata — shut.
        $this->assertNull(
            $this->hours->currentWindow($restaurant, $this->at('2026-09-07 18:00', 'UTC')),
        );
    }

    public function test_a_timezone_that_observes_dst_is_handled_by_the_library(): void
    {
        // India does not observe DST, and this platform is not staying in India
        // forever. New York on the day the clocks go back.
        $restaurant = $this->restaurant([6 => [['01:00:00', '03:00:00']]], 'America/New_York');

        // 05:30 UTC on Sunday 1 November 2026 is 01:30 in New York — inside the
        // window, on the repeated hour.
        $window = $this->hours->currentWindow(
            $restaurant,
            CarbonImmutable::parse('2026-11-01 05:30', 'UTC'),
        );

        $this->assertNotNull($window);
    }

    public function test_an_unusable_timezone_falls_back_rather_than_crashing(): void
    {
        $restaurant = $this->restaurant([0 => [['08:00:00', '22:00:00']]], 'Mars/Olympus_Mons');

        // The configured default, and a warning in the log. Silently reading
        // Asia/Kolkata for a restaurant in Goa is a wrong answer that looks
        // exactly like a right one, so it is recorded either way.
        $this->assertNotNull(
            $this->hours->currentWindow($restaurant, $this->at('2026-09-07 12:00')),
        );
    }

    // --- agreement with the discovery service --------------------------------

    public function test_the_two_services_agree_about_being_open(): void
    {
        $availability = app(RestaurantAvailabilityService::class);

        $restaurant = $this->restaurant([
            0 => [['11:00:00', '15:00:00'], ['18:00:00', '02:00:00']],
            1 => [['09:00:00', '17:00:00']],
        ]);

        // Two implementations of "does this window cover this moment" exist —
        // one cheap enough for twenty restaurants, one that can afford to look
        // a fortnight ahead. They must not drift apart.
        foreach ([
            '2026-09-07 10:00', '2026-09-07 12:00', '2026-09-07 16:00',
            '2026-09-07 19:00', '2026-09-07 23:30', '2026-09-08 01:00',
            '2026-09-08 03:00', '2026-09-08 10:00', '2026-09-09 12:00',
        ] as $moment) {
            $now = $this->at($moment);

            $openByHours = $this->hours->currentWindow($restaurant, $now) !== null;
            $openByAvailability = $availability->availabilityOf($restaurant, $now)->isActionable();

            $this->assertSame(
                $openByHours,
                $openByAvailability,
                "the two services disagree at {$moment}",
            );
        }
    }
}
