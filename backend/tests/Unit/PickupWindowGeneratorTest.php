<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Models\Restaurant;
use App\Services\Pickup\PickupWindow;
use App\Services\Pickup\PickupWindowGenerator;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Which pickup windows a restaurant could actually honour.
 *
 * Every case fixes its moment explicitly and states it in UTC, because the whole
 * point of this generator is that "open" is a claim about the restaurant's clock
 * and a test written in local time would pass or fail depending on when it ran.
 */
final class PickupWindowGeneratorTest extends TestCase
{
    use RefreshDatabase;

    private PickupWindowGenerator $generator;

    protected function setUp(): void
    {
        parent::setUp();

        $this->generator = new PickupWindowGenerator;
    }

    private function restaurant(string $timezone = 'Asia/Kolkata'): Restaurant
    {
        return Restaurant::factory()->discoverable()->at(28.5, 77.2)
            ->inTimezone($timezone)->create();
    }

    /** @return list<string> local "H:i-H:i" for readability in failures */
    private function windows(Restaurant $restaurant, CarbonImmutable $earliest, int $horizonMinutes = 240): array
    {
        $found = $this->generator->generate(
            $restaurant->load('openingHours'),
            $earliest,
            $earliest->addMinutes($horizonMinutes),
        );

        return array_map(
            static fn (PickupWindow $w): string => $w->startAt->setTimezone($restaurant->timezone)->format('H:i')
                .'-'.$w->endAt->setTimezone($restaurant->timezone)->format('H:i'),
            $found,
        );
    }

    public function test_ordinary_hours_produce_windows_on_the_slot_grid(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '22:00:00');

        // 06:30 UTC is 12:00 in Kolkata — the middle of service.
        $windows = $this->windows($restaurant, CarbonImmutable::parse('2026-09-07T06:30:00Z'));

        $this->assertSame('12:00-12:10', $windows[0]);
        $this->assertSame('12:10-12:20', $windows[1]);

        // Ten-minute grid, and nothing past the horizon.
        $this->assertSame('16:00-16:10', $windows[array_key_last($windows)]);
    }

    public function test_a_window_that_would_overrun_closing_is_not_offered(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '22:00:00');

        // 16:15 UTC is 21:45 in Kolkata: fifteen minutes of service left.
        $windows = $this->windows($restaurant, CarbonImmutable::parse('2026-09-07T16:15:00Z'));

        // 21:50-22:00 fits exactly. 22:00-22:10 does not, and a window whose
        // end is past closing is a locked door.
        $this->assertContains('21:50-22:00', $windows);
        $this->assertNotContains('22:00-22:10', $windows);

        foreach ($windows as $w) {
            $this->assertLessThanOrEqual('22:00', explode('-', $w)[1]);
        }
    }

    public function test_no_window_falls_inside_the_afternoon_closure(): void
    {
        $restaurant = $this->restaurant();
        // 11:00-15:00 then 18:00-23:00, every day.
        RestaurantFixtures::openDaily($restaurant, '11:00:00', '15:00:00');
        RestaurantFixtures::openDaily($restaurant, '18:00:00', '23:00:00');

        // 09:00 UTC is 14:30 in Kolkata — half an hour of lunch service left.
        $windows = $this->windows($restaurant, CarbonImmutable::parse('2026-09-07T09:00:00Z'), 300);

        $this->assertContains('14:30-14:40', $windows);
        $this->assertContains('14:50-15:00', $windows);

        // The gap. Nothing between three and six.
        foreach ($windows as $w) {
            $start = explode('-', $w)[0];
            $this->assertFalse(
                $start >= '15:00' && $start < '18:00',
                "a window at {$start} falls inside the afternoon closure",
            );
        }

        $this->assertContains('18:00-18:10', $windows);
    }

    public function test_overnight_hours_produce_windows_after_midnight(): void
    {
        $restaurant = $this->restaurant();
        // 18:00 until 02:00 — a genuine dhaba schedule.
        RestaurantFixtures::openDaily($restaurant, '18:00:00', '02:00:00');

        // 19:30 UTC is 01:00 in Kolkata, on the following day. The restaurant
        // opened yesterday evening and is very much still serving.
        $windows = $this->windows($restaurant, CarbonImmutable::parse('2026-09-07T19:30:00Z'), 120);

        $this->assertNotEmpty($windows, 'a restaurant open until 2am serves at 1am');
        $this->assertSame('01:00-01:10', $windows[0]);
        $this->assertContains('01:50-02:00', $windows);
        $this->assertNotContains('02:00-02:10', $windows);
    }

    public function test_a_closed_day_offers_nothing(): void
    {
        $restaurant = $this->restaurant();

        // Monday only. 2026-09-08 is a Tuesday.
        RestaurantFixtures::openOn($restaurant, 1, '09:00:00', '22:00:00');

        $windows = $this->windows($restaurant, CarbonImmutable::parse('2026-09-08T06:30:00Z'));

        $this->assertSame([], $windows);
    }

    public function test_a_restaurant_with_no_hours_on_file_offers_nothing(): void
    {
        $restaurant = $this->restaurant();

        // Not "open all hours". A restaurant nobody has given a schedule is one
        // this module cannot make promises about.
        $this->assertSame([], $this->windows($restaurant, CarbonImmutable::parse('2026-09-07T06:30:00Z')));
    }

    public function test_the_first_window_is_rounded_forward_never_back(): void
    {
        $restaurant = $this->restaurant();
        RestaurantFixtures::openDaily($restaurant, '09:00:00', '22:00:00');

        // 06:33:20 UTC is 12:03:20 in Kolkata. Rounding back to 12:00 would
        // offer a window starting before the food can be ready.
        $windows = $this->windows($restaurant, CarbonImmutable::parse('2026-09-07T06:33:20Z'));

        $this->assertSame('12:10-12:20', $windows[0]);
    }

    public function test_windows_are_generated_in_a_dst_observing_timezone(): void
    {
        // India does not observe daylight saving, so the architecture is proved
        // somewhere that does. 2026-03-29 is the UK spring-forward: at 01:00
        // UTC the local clock jumps from 00:59:59 GMT to 02:00:00 BST, so the
        // wall times 01:00-01:59 never happen that day.
        //
        // This assertion originally named 02:00-02:59 as the missing hour and
        // failed, correctly — the hour after the jump exists perfectly well.
        // The generator was right and the test was wrong about which hour
        // vanishes, which is an easy thing to get backwards and the reason for
        // writing it down here.
        $restaurant = $this->restaurant('Europe/London');
        RestaurantFixtures::openDaily($restaurant, '00:00:00', '23:59:59');

        $windows = $this->windows(
            $restaurant,
            CarbonImmutable::parse('2026-03-29T00:40:00Z'),
            120,
        );

        $this->assertNotEmpty($windows);

        // The span must actually cross the jump, or this test is checking an
        // ordinary morning and would pass against any implementation.
        $this->assertContains('00:40-00:50', $windows, 'a window before the jump');
        $this->assertContains('02:00-02:10', $windows, 'a window after it');

        // No window may claim a local time inside the hour that never happened.
        foreach ($windows as $w) {
            $start = explode('-', $w)[0];
            $this->assertFalse(
                $start >= '01:00' && $start < '02:00',
                "a window at {$start} falls inside the skipped DST hour",
            );
        }
    }
}
