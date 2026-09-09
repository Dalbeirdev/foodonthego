<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\RestaurantAvailability;
use App\Models\Restaurant;
use App\Services\Discovery\RestaurantAvailabilityService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Whether a traveller can actually stop here.
 *
 * Every case fixes the moment explicitly and states it in UTC, because the whole
 * point of this service is that "open" is a claim about the *restaurant's* clock
 * and a test written in local time would pass or fail depending on when it ran.
 */
final class RestaurantAvailabilityTest extends TestCase
{
    use RefreshDatabase;

    private RestaurantAvailabilityService $availability;

    protected function setUp(): void
    {
        parent::setUp();

        $this->availability = new RestaurantAvailabilityService;
    }

    private function restaurant(string $timezone = 'Asia/Kolkata', array $overrides = []): Restaurant
    {
        return Restaurant::factory()
            ->discoverable()
            ->at(28.5, 77.2)
            ->inTimezone($timezone)
            ->create($overrides);
    }

    /** 12:00 UTC is 17:30 in Kolkata. */
    private function noonUtc(): CarbonImmutable
    {
        return CarbonImmutable::parse('2026-09-07T12:00:00Z');
    }

    public function test_a_restaurant_open_now_reads_as_open(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '22:00:00');

        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_a_restaurant_shut_now_reads_as_closed(): void
    {
        $restaurant = $this->restaurant();
        // 06:00-09:00 local; it is 17:30 local.
        RestaurantFixtures::openDaily($restaurant, '06:00:00', '09:00:00');

        $this->assertSame(
            RestaurantAvailability::Closed,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_the_restaurants_timezone_decides_not_the_servers(): void
    {
        // The same instant, the same opening hours, two different zones. In
        // Kolkata it is 17:30 and the restaurant is open; in London it is 13:00
        // and it is not.
        $kolkata = $this->restaurant('Asia/Kolkata');
        RestaurantFixtures::openDaily($kolkata, '17:00:00', '23:00:00');

        $london = $this->restaurant('Europe/London');
        RestaurantFixtures::openDaily($london, '17:00:00', '23:00:00');

        $now = $this->noonUtc();

        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf($kolkata->load('openingHours'), $now),
        );

        $this->assertSame(
            RestaurantAvailability::Closed,
            $this->availability->availabilityOf($london->load('openingHours'), $now),
        );
    }

    public function test_an_overnight_window_covers_the_small_hours(): void
    {
        // 18:00 to 02:00. At 01:00 local the restaurant is open, and the row
        // that says so belongs to *yesterday* — the case that reports a night
        // dhaba shut at exactly the hour a driver needs it.
        $restaurant = $this->restaurant();
        RestaurantFixtures::openDaily($restaurant, '18:00:00', '02:00:00');

        // 19:30 UTC is 01:00 the next day in Kolkata.
        $lateNight = CarbonImmutable::parse('2026-09-07T19:30:00Z');

        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $lateNight),
        );
    }

    public function test_an_overnight_window_is_shut_in_the_afternoon(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openDaily($restaurant, '18:00:00', '02:00:00');

        // 09:00 UTC is 14:30 in Kolkata.
        $afternoon = CarbonImmutable::parse('2026-09-07T09:00:00Z');

        $this->assertSame(
            RestaurantAvailability::Closed,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $afternoon),
        );
    }

    public function test_a_paused_restaurant_is_never_reported_as_open(): void
    {
        // The single most important assertion in this file. The doors are open,
        // the kitchen is not taking work, and telling a traveller forty
        // kilometres away that this is "Open" sends them to a closed counter.
        $restaurant = $this->restaurant(overrides: ['is_accepting_orders' => false]);
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '22:00:00');

        $this->assertSame(
            RestaurantAvailability::NotAcceptingOrders,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_a_paused_restaurant_that_is_also_shut_reads_as_closed(): void
    {
        // The earlier and more useful fact wins: it is shut, and the pause is
        // beside the point.
        $restaurant = $this->restaurant(overrides: ['is_accepting_orders' => false]);
        RestaurantFixtures::openDaily($restaurant, '06:00:00', '09:00:00');

        $this->assertSame(
            RestaurantAvailability::Closed,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_a_restaurant_about_to_open_says_so(): void
    {
        $restaurant = $this->restaurant();
        // Opens 17:45 local; it is 17:30.
        RestaurantFixtures::openDaily($restaurant, '17:45:00', '23:00:00');

        $this->assertSame(
            RestaurantAvailability::OpeningSoon,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_a_restaurant_about_to_close_says_so(): void
    {
        $restaurant = $this->restaurant();
        // Closes 17:50 local; it is 17:30.
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '17:50:00');

        $this->assertSame(
            RestaurantAvailability::ClosingSoon,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_a_restaurant_open_around_the_clock_is_never_closing_soon(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openAllWeek($restaurant);

        // 18:02:13 UTC is 23:32:13 in Kolkata — inside the last half hour of
        // the day, which is where the closing-soon window used to catch this
        // fixture. This exact instant turned CI red on a docs-only commit, and
        // would have done so for half an hour every night.
        //
        // The restaurant is not closing. Tomorrow's window opens the moment
        // tonight's ends, and a driver told "Closing soon" at 23:40 would drive
        // past a place that is open all night.
        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf(
                $restaurant->load('openingHours'),
                CarbonImmutable::parse('2026-09-07 18:02:13', 'UTC'),
            ),
        );
    }

    public function test_a_restaurant_open_around_the_clock_is_open_through_midnight(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openAllWeek($restaurant);
        $loaded = $restaurant->load('openingHours');

        // The sibling of the test above, and the second time this fixture has
        // failed on the clock. It used to write `23:59:59` as a stand-in for
        // midnight; `covers()` asks `$time < closes_at`, so for the whole of
        // the 23:59:59 second the restaurant was CLOSED. CI run 160's Android
        // device job ran from 23:46 to 00:06 in Asia/Kolkata, crossed that
        // second, and a checkout test that had passed minutes earlier was
        // refused with RESTAURANT_NOT_ACCEPTING_ORDERS.
        //
        // Every second across the boundary, not just the guilty one: a test
        // that checked only 23:59:59 would pass against a fixture that had
        // simply moved the hole somewhere else.
        foreach ([
            '2026-09-07 18:29:57',  // 23:59:57 IST
            '2026-09-07 18:29:58',  // 23:59:58
            '2026-09-07 18:29:59',  // 23:59:59  <- the second that broke CI
            '2026-09-07 18:30:00',  // 00:00:00, the next day in Kolkata
            '2026-09-07 18:30:01',  // 00:00:01
        ] as $utc) {
            $now = CarbonImmutable::parse($utc, 'UTC');

            $this->assertSame(
                RestaurantAvailability::Open,
                $this->availability->availabilityOf($loaded, $now),
                sprintf(
                    'a restaurant open around the clock must be open at %s IST',
                    $now->setTimezone('Asia/Kolkata')->format('H:i:s'),
                ),
            );
        }
    }

    public function test_back_to_back_windows_do_not_read_as_closing(): void
    {
        $restaurant = $this->restaurant();

        // Lunch hands straight over to dinner at 14:00.
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '14:00:00');
        RestaurantFixtures::openDaily($restaurant, '14:00:00', '23:00:00');

        // 08:15 UTC is 13:45 local: fifteen minutes from the end of the lunch
        // window, and not fifteen minutes from being shut.
        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf(
                $restaurant->load('openingHours'),
                CarbonImmutable::parse('2026-09-07 08:15:00', 'UTC'),
            ),
        );
    }

    public function test_no_opening_hours_is_unknown_rather_than_open_or_closed(): void
    {
        $restaurant = $this->restaurant();

        // An absence, reported as one. Guessing "open" would send people to a
        // locked door; guessing "closed" would hide a restaurant that is trading.
        $this->assertSame(
            RestaurantAvailability::Unknown,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_a_split_service_day_is_shut_between_sittings(): void
    {
        $restaurant = $this->restaurant();

        foreach (range(0, 6) as $day) {
            $restaurant->openingHours()->create([
                'day_of_week' => $day,
                'opens_at' => '11:00:00',
                'closes_at' => '15:00:00',
            ]);
            $restaurant->openingHours()->create([
                'day_of_week' => $day,
                'opens_at' => '19:00:00',
                'closes_at' => '23:00:00',
            ]);
        }

        // 17:30 local falls between lunch and dinner.
        $this->assertSame(
            RestaurantAvailability::Closed,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );

        // 20:00 local is dinner. 14:30 UTC.
        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf(
                $restaurant->load('openingHours'),
                CarbonImmutable::parse('2026-09-07T14:30:00Z'),
            ),
        );
    }

    public function test_an_unusable_timezone_falls_back_rather_than_throwing(): void
    {
        $restaurant = $this->restaurant('Not/AZone');
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '22:00:00');

        // A data fault must not take a discovery request down with it.
        $this->assertSame(
            RestaurantAvailability::Open,
            $this->availability->availabilityOf($restaurant->load('openingHours'), $this->noonUtc()),
        );
    }

    public function test_only_open_and_closing_soon_count_as_actionable(): void
    {
        $this->assertTrue(RestaurantAvailability::Open->isActionable());
        $this->assertTrue(RestaurantAvailability::ClosingSoon->isActionable());

        foreach ([
            RestaurantAvailability::Closed,
            RestaurantAvailability::OpeningSoon,
            RestaurantAvailability::NotAcceptingOrders,
            RestaurantAvailability::Unknown,
        ] as $availability) {
            $this->assertFalse($availability->isActionable(), $availability->value);
        }
    }
}
