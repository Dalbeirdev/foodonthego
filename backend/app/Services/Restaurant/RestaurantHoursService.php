<?php

declare(strict_types=1);

namespace App\Services\Restaurant;

use App\Models\Restaurant;
use App\Models\RestaurantOpeningHour;
use App\Services\Discovery\RestaurantAvailabilityService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Log;

/**
 * The opening schedule, as a customer needs to read it.
 *
 * {@see RestaurantAvailabilityService} answers "can I
 * stop here now". This answers the questions that come next: what are today's
 * hours, what does the week look like, and — when the answer to the first is
 * "you can't" — when does it open again.
 *
 * Two services rather than one because they are used at different moments and
 * at different costs. Availability runs for twenty restaurants on a discovery
 * screen and must stay cheap. This runs for one restaurant on a detail screen
 * and can afford to walk a fortnight looking for the next open minute.
 *
 * Everything is computed in the restaurant's own timezone from server time.
 * Never the device clock, which a customer can set to anything.
 */
final class RestaurantHoursService
{
    /**
     * How far ahead to look for the next opening.
     *
     * Eight days rather than seven: a restaurant open only on Mondays, asked on
     * a Monday evening after closing, has its next opening 6 days and some
     * hours away — and the extra day covers the wrap without special-casing it.
     */
    private const LOOKAHEAD_DAYS = 8;

    /**
     * Today's windows, in the order they run.
     *
     * "Today" is the restaurant's today. A window that opened yesterday evening
     * and is still running at 01:00 is **not** in this list: it belongs to
     * yesterday, and a customer reading "18:00 – 02:00" under the heading
     * "Today" at one in the morning would reasonably expect it to start again
     * this evening. {@see currentWindow()} is what answers "and are you open
     * right now".
     *
     * @return list<array{opens_at: string, closes_at: string, is_overnight: bool}>
     */
    public function today(Restaurant $restaurant, CarbonImmutable $now): array
    {
        $local = $this->localNow($restaurant, $now);

        return $this->windowsFor($this->windows($restaurant), $this->dayOfWeek($local));
    }

    /**
     * The whole week, Monday first, including the days it is shut.
     *
     * A closed day is a row with an empty window list, not a missing row. "We
     * are shut on Mondays" is information; a gap in a list is a question.
     *
     * @return list<array{day_of_week: int, is_today: bool, windows: list<array{opens_at: string, closes_at: string, is_overnight: bool}>}>
     */
    public function week(Restaurant $restaurant, CarbonImmutable $now): array
    {
        $windows = $this->windows($restaurant);
        $today = $this->dayOfWeek($this->localNow($restaurant, $now));

        $week = [];

        for ($day = 0; $day <= 6; $day++) {
            $week[] = [
                'day_of_week' => $day,
                'is_today' => $day === $today,
                'windows' => $this->windowsFor($windows, $day),
            ];
        }

        return $week;
    }

    /**
     * Whether the restaurant is open at this moment, and until when.
     *
     * Returns null when it is shut. The `closes_at` is a real instant rather
     * than a wall-clock string, so an overnight window closing at 02:00 gives
     * tomorrow's two in the morning and not a time that has already passed.
     *
     * @return array{opens_at: string, closes_at: string, closes_at_utc: string}|null
     */
    public function currentWindow(Restaurant $restaurant, CarbonImmutable $now): ?array
    {
        $local = $this->localNow($restaurant, $now);

        foreach ($this->windows($restaurant) as $window) {
            if (! $this->covers($window, $local)) {
                continue;
            }

            return [
                'opens_at' => $this->time($window->opens_at),
                'closes_at' => $this->time($window->closes_at),
                'closes_at_utc' => $this->nextOccurrence($local, $this->time($window->closes_at))
                    ->utc()
                    ->toIso8601String(),
            ];
        }

        return null;
    }

    /**
     * The next moment the doors open, or null.
     *
     * Null means one of three things and the caller must not distinguish them
     * by guessing: no hours are on file, the restaurant is open right now, or
     * nothing opens within the lookahead. Each is a reason to say nothing
     * rather than to print a time.
     *
     * A restaurant that is currently *open* returns null, because "opens at" is
     * not a useful thing to tell somebody standing in the doorway.
     */
    public function nextOpenAt(Restaurant $restaurant, CarbonImmutable $now): ?CarbonImmutable
    {
        $windows = $this->windows($restaurant);

        if ($windows->isEmpty() || $this->currentWindow($restaurant, $now) !== null) {
            return null;
        }

        $local = $this->localNow($restaurant, $now);

        for ($offset = 0; $offset < self::LOOKAHEAD_DAYS; $offset++) {
            $day = $local->addDays($offset);
            $dayOfWeek = $this->dayOfWeek($day);

            // Earliest first, so the first candidate that is still ahead of us
            // is the answer rather than merely *an* answer.
            $candidates = $windows
                ->filter(fn (RestaurantOpeningHour $w): bool => $w->day_of_week === $dayOfWeek)
                ->map(fn (RestaurantOpeningHour $w): string => $this->time($w->opens_at))
                ->sort()
                ->values();

            foreach ($candidates as $opensAt) {
                [$hour, $minute, $second] = array_map('intval', explode(':', $opensAt));

                $opening = $day->setTime($hour, $minute, $second);

                if ($opening->greaterThan($local)) {
                    return $opening;
                }
            }
        }

        return null;
    }

    // --- internals -----------------------------------------------------------

    /** @return Collection<int, RestaurantOpeningHour> */
    private function windows(Restaurant $restaurant): Collection
    {
        // Loaded, not queried. The detail endpoint eager-loads hours; a lazy
        // read here would turn one request into four.
        return $restaurant->relationLoaded('openingHours')
            ? $restaurant->openingHours
            : $restaurant->openingHours()->get();
    }

    /**
     * @param  Collection<int, RestaurantOpeningHour>  $windows
     * @return list<array{opens_at: string, closes_at: string, is_overnight: bool}>
     */
    private function windowsFor(Collection $windows, int $day): array
    {
        return $windows
            ->filter(fn (RestaurantOpeningHour $w): bool => $w->day_of_week === $day)
            ->sortBy(fn (RestaurantOpeningHour $w): string => $this->time($w->opens_at))
            ->map(fn (RestaurantOpeningHour $w): array => [
                'opens_at' => $this->time($w->opens_at),
                'closes_at' => $this->time($w->closes_at),
                'is_overnight' => $w->isOvernight(),
            ])
            ->values()
            ->all();
    }

    /**
     * Whether a window covers this local moment.
     *
     * The same rule {@see RestaurantAvailabilityService}
     * applies, and deliberately the same shape: an overnight window belongs to
     * the day it *opens*, so at 01:00 on Tuesday the window covering you is
     * Monday's. The two implementations agree because
     * `RestaurantHoursTest::test_the_two_services_agree_about_being_open`
     * compares them across a week of hours rather than because anyone
     * remembered to keep them in step.
     */
    private function covers(RestaurantOpeningHour $window, CarbonImmutable $local): bool
    {
        $time = $local->format('H:i:s');
        $today = $this->dayOfWeek($local);
        $yesterday = ($today + 6) % 7;

        if (! $window->isOvernight()) {
            return $window->day_of_week === $today
                && $time >= $this->time($window->opens_at)
                && $time < $this->time($window->closes_at);
        }

        if ($window->day_of_week === $today && $time >= $this->time($window->opens_at)) {
            return true;
        }

        return $window->day_of_week === $yesterday && $time < $this->time($window->closes_at);
    }

    private function nextOccurrence(CarbonImmutable $local, string $time): CarbonImmutable
    {
        [$hour, $minute, $second] = array_map('intval', explode(':', $time));

        $candidate = $local->setTime($hour, $minute, $second);

        return $candidate->lessThanOrEqualTo($local) ? $candidate->addDay() : $candidate;
    }

    /** Server time, moved into the restaurant's own zone. */
    public function localNow(Restaurant $restaurant, CarbonImmutable $now): CarbonImmutable
    {
        $zone = $restaurant->timezone ?: '';

        try {
            return $now->setTimezone($zone);
        } catch (\Throwable) {
            Log::warning('restaurant.timezone_invalid', [
                'restaurant_uuid' => $restaurant->uuid,
                'timezone' => $zone,
            ]);

            return $now->setTimezone((string) config('foodonthego.discovery.default_timezone'));
        }
    }

    /** 0 = Monday .. 6 = Sunday, matching the column's documented meaning. */
    private function dayOfWeek(CarbonImmutable $local): int
    {
        return $local->dayOfWeekIso - 1;
    }

    /** MySQL hands back "18:00:00"; a cast or a driver may hand back more. */
    private function time(string $value): string
    {
        return substr($value, 0, 8);
    }
}
