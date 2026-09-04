<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\RestaurantAvailability;
use App\Models\Restaurant;
use App\Models\RestaurantOpeningHour;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Log;

/**
 * Whether a customer can actually stop here, right now.
 *
 * Two independent facts, resolved in one order that never varies: the clock says
 * the doors are open, and the restaurant says it is taking orders. A restaurant
 * that is open and paused is reported as paused, because sending somebody forty
 * kilometres for food nobody will cook is the worst thing this module could do.
 *
 * Every comparison happens in the **restaurant's** timezone, from **server**
 * time. Not the device's clock, which a customer can set to anything, and not
 * the server's timezone, which would open a Goa restaurant on Delhi's schedule
 * the day this product leaves one time zone.
 */
final class RestaurantAvailabilityService
{
    /**
     * How long before opening counts as "opening soon", and how long before
     * closing counts as "closing soon".
     *
     * Thirty minutes for both, and the two numbers are the same by coincidence
     * rather than by rule — they answer different questions, so they are named
     * separately and can move apart.
     */
    private const OPENING_SOON_MINUTES = 30;

    private const CLOSING_SOON_MINUTES = 30;

    public function availabilityOf(Restaurant $restaurant, CarbonImmutable $now): RestaurantAvailability
    {
        $local = $this->localNow($restaurant, $now);

        // Loaded, not queried: discovery eager-loads opening hours for every
        // candidate in one query, and a lazy read here would be one query per
        // restaurant on a screen that shows twenty.
        $windows = $restaurant->relationLoaded('openingHours')
            ? $restaurant->openingHours
            : $restaurant->openingHours()->get();

        if ($windows->isEmpty()) {
            // No hours on file is not a claim that the restaurant is shut, and
            // it is certainly not a claim that it is open. It is an absence, and
            // it is reported as one.
            return RestaurantAvailability::Unknown;
        }

        $openNow = $windows->contains(
            fn (RestaurantOpeningHour $window): bool => $this->covers($window, $local),
        );

        if ($openNow) {
            // The pause beats the clock. Deliberately checked after the hours
            // rather than before, so a paused restaurant that is also shut reads
            // as "Closed" — the earlier and more useful fact.
            if (! $restaurant->is_accepting_orders) {
                return RestaurantAvailability::NotAcceptingOrders;
            }

            return $this->closesWithin($windows, $local, self::CLOSING_SOON_MINUTES)
                ? RestaurantAvailability::ClosingSoon
                : RestaurantAvailability::Open;
        }

        return $this->opensWithin($windows, $local, self::OPENING_SOON_MINUTES)
            ? RestaurantAvailability::OpeningSoon
            : RestaurantAvailability::Closed;
    }

    /**
     * Server time, moved into the restaurant's own zone.
     *
     * A restaurant carrying an unusable timezone is a data fault, not a reason
     * to guess: it falls back to the configured default and says so in the log,
     * because silently reading Asia/Kolkata for a restaurant in Goa is a wrong
     * answer that looks exactly like a right one.
     */
    private function localNow(Restaurant $restaurant, CarbonImmutable $now): CarbonImmutable
    {
        $zone = $restaurant->timezone ?: '';

        try {
            return $now->setTimezone($zone);
        } catch (\Throwable) {
            Log::warning('discovery.restaurant_timezone_invalid', [
                'restaurant_uuid' => $restaurant->uuid,
                'timezone' => $zone,
            ]);

            return $now->setTimezone((string) config('foodonthego.discovery.default_timezone'));
        }
    }

    /**
     * Whether a window covers this local moment.
     *
     * The overnight case is the whole reason this is a method. A window of 18:00
     * to 02:00 belongs to the day it *opens*, so at 01:00 on Tuesday the window
     * that covers you is Monday's. Reading only today's rows would report a
     * roadside dhaba shut at exactly the hour a night driver needs it.
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

        // Opened today and still running towards midnight.
        if ($window->day_of_week === $today && $time >= $this->time($window->opens_at)) {
            return true;
        }

        // Opened yesterday and still running after midnight.
        return $window->day_of_week === $yesterday && $time < $this->time($window->closes_at);
    }

    /** @param Collection<int, RestaurantOpeningHour> $windows */
    private function closesWithin($windows, CarbonImmutable $local, int $minutes): bool
    {
        foreach ($windows as $window) {
            if (! $this->covers($window, $local)) {
                continue;
            }

            $closesAt = $this->nextOccurrence($local, $this->time($window->closes_at));

            if ($local->diffInMinutes($closesAt, absolute: false) <= $minutes) {
                return true;
            }
        }

        return false;
    }

    /** @param Collection<int, RestaurantOpeningHour> $windows */
    private function opensWithin($windows, CarbonImmutable $local, int $minutes): bool
    {
        $today = $this->dayOfWeek($local);

        foreach ($windows as $window) {
            if ($window->day_of_week !== $today) {
                continue;
            }

            $opensAt = $this->nextOccurrence($local, $this->time($window->opens_at));

            $until = $local->diffInMinutes($opensAt, absolute: false);

            if ($until >= 0 && $until <= $minutes) {
                return true;
            }
        }

        return false;
    }

    /** The next time today's clock reads this, today or tomorrow. */
    private function nextOccurrence(CarbonImmutable $local, string $time): CarbonImmutable
    {
        [$hour, $minute, $second] = array_map('intval', explode(':', $time));

        $candidate = $local->setTime($hour, $minute, $second);

        return $candidate->lessThan($local) ? $candidate->addDay() : $candidate;
    }

    /** 0 = Monday .. 6 = Sunday, matching the column's documented meaning. */
    private function dayOfWeek(CarbonInterface $local): int
    {
        return $local->dayOfWeekIso - 1;
    }

    /** MySQL hands back "18:00:00"; a cast or a driver may hand back more. */
    private function time(string $value): string
    {
        return substr($value, 0, 8);
    }
}
