<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Models\Restaurant;
use App\Models\RestaurantOpeningHour;
use App\Services\Discovery\RestaurantAvailabilityService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Every pickup window a restaurant could actually honour.
 *
 * The hard part is not the arithmetic, it is the calendar. Restaurants close for
 * the afternoon and reopen in the evening. Some serve until two in the morning,
 * which is a different day on the clock and the same day in the kitchen. A
 * window must fit **entirely** inside a serving period — offering one that
 * starts at 21:55 and ends at 22:05 for a place that shuts at ten is offering a
 * customer a locked door.
 *
 * Every comparison happens in the restaurant's own IANA timezone. Not an offset:
 * an offset is a fact about one moment, and a timezone is a rule. The India-first
 * launch would work either way, which is exactly why it is worth getting right
 * now rather than discovering it in a region that observes daylight saving.
 */
final class PickupWindowGenerator
{
    /**
     * Windows between the earliest feasible moment and the planning horizon.
     *
     * @return list<PickupWindow>
     */
    public function generate(
        Restaurant $restaurant,
        CarbonImmutable $earliestAt,
        CarbonImmutable $horizonAt,
    ): array {
        $zone = $this->zone($restaurant);

        $interval = max(1, (int) config('foodonthego.pickup.slot_interval_minutes'));
        $duration = max(1, (int) config('foodonthego.pickup.window_duration_minutes'));
        $cutoff = max(0, (int) config('foodonthego.pickup.last_order_before_close_minutes'));

        $hours = $restaurant->openingHours;

        if ($hours->isEmpty()) {
            // No hours on file is not "open all hours". A restaurant nobody has
            // given a schedule is a restaurant this module cannot make promises
            // about.
            return [];
        }

        $periods = $this->servingPeriods($hours, $earliestAt->setTimezone($zone), $horizonAt->setTimezone($zone), $cutoff);

        $windows = [];

        foreach ($periods as $period) {
            [$openAt, $lastPickupAt] = $period;

            // Start from whichever is later — the period opening, or the
            // earliest the food can be ready — then step forward on the slot
            // grid.
            $cursor = $this->alignForward(
                $earliestAt->setTimezone($zone)->max($openAt),
                $interval,
            );

            // The horizon binds the START of a window, not its end. A window
            // that begins four hours from now and runs ten minutes past the
            // line is within how far ahead the customer may plan; truncating it
            // would drop the last option for no reason anybody could see.
            while ($cursor <= $lastPickupAt && $cursor <= $horizonAt->setTimezone($zone)) {
                $endAt = $cursor->addMinutes($duration);

                // The whole window must fit. A window that runs past the last
                // pickup time is a window the counter will not be staffed for.
                if ($endAt <= $lastPickupAt) {
                    $windows[] = new PickupWindow($cursor, $endAt);
                }

                $cursor = $cursor->addMinutes($interval);
            }
        }

        usort(
            $windows,
            static fn (PickupWindow $a, PickupWindow $b): int => $a->startAt <=> $b->startAt,
        );

        // One window per start, however many opening rows produced it.
        //
        // Overlapping rows are legitimate data — somebody enters 09:00-14:00
        // and then 12:00-22:00 rather than editing the first — and every hour
        // they share generates the same window twice. Offering a customer
        // "1:00 PM" twice in a list of eight is a bug with no cause they could
        // ever guess at, and it silently halves how far ahead the options
        // reach.
        $unique = [];

        foreach ($windows as $window) {
            $unique[$window->startAt->getTimestamp().'-'.$window->endAt->getTimestamp()] = $window;
        }

        return array_values($unique);
    }

    /**
     * The restaurant's serving periods as absolute local instants.
     *
     * Built by walking the days the planning span touches rather than by
     * reasoning about "today", because a span that begins at 23:50 and ends at
     * 01:30 touches two calendar days and an overnight period belongs to the day
     * it OPENED on. Yesterday is included for exactly that reason: a period that
     * opened at 18:00 yesterday and closes at 02:00 today is live right now.
     *
     * @param  Collection<int, RestaurantOpeningHour>  $hours
     * @return list<array{0: CarbonImmutable, 1: CarbonImmutable}>
     */
    private function servingPeriods(
        Collection $hours,
        CarbonImmutable $from,
        CarbonImmutable $to,
        int $cutoffMinutes,
    ): array {
        $periods = [];

        $day = $from->subDay()->startOfDay();
        $last = $to->addDay()->startOfDay();

        while ($day <= $last) {
            foreach ($hours as $window) {
                if ((int) $window->day_of_week !== $this->dayOfWeek($day)) {
                    continue;
                }

                $opensAt = $this->at($day, (string) $window->opens_at);
                $closesAt = $this->at($day, (string) $window->closes_at);

                // 18:00–02:00 closes tomorrow. The comparison is on the clock
                // faces, so this catches every overnight period without anybody
                // having to flag one.
                if ($closesAt <= $opensAt) {
                    $closesAt = $closesAt->addDay();
                }

                $lastPickupAt = $closesAt->subMinutes($cutoffMinutes);

                if ($lastPickupAt <= $opensAt) {
                    continue;
                }

                // Only periods that overlap the span we are planning across.
                if ($lastPickupAt < $from || $opensAt > $to) {
                    continue;
                }

                $periods[] = [$opensAt, $lastPickupAt];
            }

            $day = $day->addDay();
        }

        usort($periods, static fn (array $a, array $b): int => $a[0] <=> $b[0]);

        return $periods;
    }

    /**
     * The next slot boundary at or after this moment.
     *
     * **Always forward.** Rounding back would offer a window beginning before
     * the food can be ready, which is the one direction that turns a helpful
     * suggestion into a broken promise.
     */
    private function alignForward(CarbonImmutable $moment, int $interval): CarbonImmutable
    {
        $minute = (int) $moment->format('i');
        $remainder = $minute % $interval;

        $aligned = $moment->setTime((int) $moment->format('H'), $minute, 0);

        if ($remainder !== 0 || (int) $moment->format('s') > 0) {
            $aligned = $aligned->addMinutes($interval - $remainder);
        }

        return $aligned;
    }

    private function at(CarbonImmutable $day, string $time): CarbonImmutable
    {
        [$h, $m, $s] = array_pad(array_map('intval', explode(':', $time)), 3, 0);

        return $day->setTime($h, $m, $s);
    }

    /**
     * 0 = Monday .. 6 = Sunday, matching the column's documented meaning and
     * {@see RestaurantAvailabilityService}.
     *
     * NOT Carbon's `dayOfWeek`, which counts Sunday as 0. Reading the column
     * that way shifts every restaurant's whole schedule by one day, so the same
     * row would say "open Monday" to pickup planning and "open Tuesday" to
     * discovery. There is one convention in this schema and this is it.
     */
    private function dayOfWeek(CarbonImmutable $day): int
    {
        return $day->dayOfWeekIso - 1;
    }

    private function zone(Restaurant $restaurant): string
    {
        $zone = (string) ($restaurant->timezone ?: '');

        try {
            CarbonImmutable::now($zone);

            return $zone;
        } catch (\Throwable) {
            // A restaurant carrying an unusable timezone is a data fault, and
            // guessing its region would be a wrong answer that looks right.
            return (string) config('foodonthego.discovery.default_timezone');
        }
    }
}
