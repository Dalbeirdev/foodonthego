<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Enums\RestaurantStatus;
use App\Enums\RestaurantVerificationStatus;
use App\Models\Restaurant;
use App\Models\RestaurantMedia;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * The six documented discovery fixtures, for the Delhi → Jaipur pilot route.
 *
 * ## These are not restaurants
 *
 * Every name here begins with **"[TEST]"**, and that is not decoration. These
 * rows exist to prove that eligibility, corridor filtering and availability
 * behave, and a customer must never be able to mistake one for a partner. The
 * seeder refuses to run in production for the same reason the development
 * routing provider refuses to be constructed there.
 *
 * ## Where the coordinates come from
 *
 * They are computed, not invented: each fixture is placed at a stated fraction
 * along the straight line between the pilot origin and destination, offset
 * perpendicular to it by a stated distance. So "1.2 km off the route" is a fact
 * about the row rather than a claim in a comment, and the assertions that follow
 * are testing the algorithm rather than testing that somebody typed a plausible
 * number.
 *
 * They are **fixture positions**, not real restaurant addresses. Nothing here
 * claims a business exists at these points.
 */
final class DiscoveryTestRestaurantSeeder extends Seeder
{
    /** Green Park, New Delhi — the pilot trip's origin. */
    private const ORIGIN = [28.5590, 77.2070];

    /** Jaipur International Airport — the pilot trip's destination. */
    private const DESTINATION = [26.8242, 75.8122];

    public function run(): void
    {
        if (app()->environment('production')) {
            throw new \RuntimeException(
                'Discovery test restaurants must never be seeded into production.',
            );
        }

        $this->clearPrevious();

        // A — squarely in the corridor, open, everything in order.
        //
        // Module 09 gave it the full profile a detail screen wants: the
        // operator's own words, a published business number, and three
        // photographs with captions. The URLs point at a data-URI placeholder
        // rather than at somebody's real restaurant: a stock photograph shown
        // under a business's name is a claim about premises nobody has seen.
        $this->create(
            name: '[TEST] Highway Spice Kitchen',
            fraction: 0.28,
            offsetMetres: 900,
            cuisines: ['North Indian', 'Vegetarian'],
            facilities: ['Parking', 'Restroom', 'Seating'],
            alwaysOpen: true,
            description: 'A highway kitchen on the Delhi-Jaipur road, serving '
                .'North Indian food to travellers since the bypass opened. '
                .'Parking for cars and coaches, and a covered seating area.',
            publicPhone: '+911412345678',
            media: [
                ['url' => self::placeholderImage('1'), 'alt' => 'The dining room, looking towards the highway'],
                ['url' => self::placeholderImage('2'), 'alt' => 'The covered seating area at the back'],
                ['url' => self::placeholderImage('3'), 'alt' => null],
            ],
        );

        // B — further off the road but still inside the corridor, open.
        $this->create(
            name: '[TEST] Rajasthan Highway Bites',
            fraction: 0.62,
            offsetMetres: 2_400,
            cuisines: ['Rajasthani', 'Fast Food'],
            facilities: ['Parking', 'Takeaway'],
            alwaysOpen: true,
            // A cheaper roadside stop, so the price filter and the price sort
            // have something to distinguish. Price level is metadata an
            // operator declares, so varying it here is fixture configuration
            // rather than fabricated measurement.
            priceLevel: 1,
        );

        // C — well outside the corridor. Must be rejected, and ideally before
        // any provider is troubled about it.
        $this->create(
            name: '[TEST] Far Away Kitchen',
            fraction: 0.50,
            offsetMetres: 60_000,
            cuisines: ['Cafe'],
            facilities: [],
            alwaysOpen: true,
        );

        // D — in the corridor, and suspended. Must never appear.
        $this->create(
            name: '[TEST] Suspended Dhaba',
            fraction: 0.45,
            offsetMetres: 800,
            cuisines: ['North Indian'],
            facilities: ['Parking'],
            alwaysOpen: true,
            status: RestaurantStatus::Suspended,
        );

        // E — in the corridor, onboarding never finished. Must never appear.
        $this->create(
            name: '[TEST] Pending Restaurant',
            fraction: 0.52,
            offsetMetres: 700,
            cuisines: ['South Indian'],
            facilities: ['Restroom'],
            alwaysOpen: true,
            verification: RestaurantVerificationStatus::Pending,
        );

        // F — in the corridor, eligible, and shut at every hour of every day.
        // Appears, and is honest about being closed.
        $this->create(
            name: '[TEST] Closed Route Cafe',
            fraction: 0.70,
            offsetMetres: 1_100,
            cuisines: ['Cafe', 'Bakery'],
            facilities: ['Seating'],
            priceLevel: 3,
            // A window that has already ended on every day of the week, so this
            // fixture reads CLOSED whenever the suite happens to run.
            hours: ['02:00:00', '03:00:00'],
        );

        // G — eligible and open, and behind the origin: reaching it means
        // turning round before the journey has started.
        //
        // A negative fraction, so it sits *before* the route begins. It has to
        // be close enough to still fall inside the corridor — a fixture parked
        // 30 km behind Delhi would be rejected by the bounding box and would
        // prove nothing about backtracking, which is exactly what the first
        // version of this seeder did.
        $this->create(
            name: '[TEST] Behind You Diner',
            fraction: -0.012,
            offsetMetres: 600,
            cuisines: ['North Indian'],
            facilities: ['Parking'],
            alwaysOpen: true,
        );

        // H — eligible, in the corridor, open by the clock and not cooking.
        $this->create(
            name: '[TEST] Paused Highway Grill',
            fraction: 0.36,
            offsetMetres: 1_000,
            cuisines: ['Chinese'],
            facilities: ['Parking', 'Restroom'],
            alwaysOpen: true,
            acceptingOrders: false,
        );

        // --- Module 09 -------------------------------------------------------
        //
        // Three fixtures whose whole purpose is the detail screen. Each exists
        // because a rule that is only exercised by a unit test is a rule nobody
        // can look at.

        // I — an overnight kitchen: 18:00 to 02:00, every day.
        //
        // The one that catches the classic bug. At one in the morning a naive
        // implementation reads today's rows, finds a window that starts at
        // 18:00, decides the restaurant is shut, and sends a night driver past
        // the only place open for eighty kilometres.
        $this->create(
            name: '[TEST] Night Owl Dhaba',
            fraction: 0.44,
            offsetMetres: 1_300,
            cuisines: ['North Indian'],
            facilities: ['Parking', 'Restroom'],
            priceLevel: 1,
            schedule: array_fill(0, 7, [['18:00:00', '02:00:00']]),
            description: 'Open through the night for drivers on the NH 48.',
            media: [
                ['url' => self::placeholderImage('4'), 'alt' => 'The counter, lit at night'],
            ],
        );

        // J — a split service, and one day shut.
        //
        // Lunch and dinner with the kitchen closed between, and no rows at all
        // for Monday. A closed day must read as "Closed", not as a gap in the
        // list that leaves the customer wondering.
        $this->create(
            name: '[TEST] Midday Break Kitchen',
            fraction: 0.56,
            offsetMetres: 1_600,
            cuisines: ['South Indian', 'Vegetarian'],
            facilities: ['Seating', 'Restroom'],
            priceLevel: 2,
            schedule: [
                // 0 is Monday, and it is absent: this kitchen is shut on Mondays.
                1 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
                2 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
                3 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
                4 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
                5 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
                6 => [['11:00:00', '15:00:00'], ['18:00:00', '23:00:00']],
            ],
            description: 'Vegetarian South Indian, lunch and dinner. Closed on Mondays.',
            media: [
                ['url' => self::placeholderImage('5'), 'alt' => 'Dosa on the griddle'],
                ['url' => self::placeholderImage('6'), 'alt' => null],
                // Uploaded and not yet moderated. Must never reach a customer,
                // and the detail test asserts that it does not.
                ['url' => self::placeholderImage('7'), 'alt' => 'Awaiting review', 'active' => false],
            ],
        );

        // K — everything optional, missing.
        //
        // No description, no photographs, no facilities, no price level. The
        // detail screen must omit four sections rather than render four empty
        // cards, and must never fill any of them in.
        $this->create(
            name: '[TEST] Bare Bones Stop',
            fraction: 0.66,
            offsetMetres: 2_000,
            cuisines: ['Fast Food'],
            facilities: [],
            alwaysOpen: true,
            priceLevel: null,
        );
    }

    /**
     * A one-pixel PNG as a data URI.
     *
     * Fixture photographs have to come from somewhere, and every alternative is
     * worse. A stock photograph shown under a business's name is a claim about
     * premises nobody has seen; a link to a real restaurant's website borrows
     * their bandwidth and their picture; a broken URL makes every fixture
     * exercise the failure path instead of the normal one.
     *
     * The suffix only varies the string, so the gallery has distinguishable
     * entries in a log or a diff.
     */
    private static function placeholderImage(string $suffix): string
    {
        return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
            .'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
            .'#'.$suffix;
    }

    /** Removes anything this seeder created before, so re-running is safe. */
    private function clearPrevious(): void
    {
        $ids = Restaurant::query()
            ->where('name', 'like', '[TEST]%')
            ->pluck('id');

        if ($ids->isEmpty()) {
            return;
        }

        DB::table('restaurant_media')->whereIn('restaurant_id', $ids)->delete();
        DB::table('restaurant_cuisines')->whereIn('restaurant_id', $ids)->delete();
        DB::table('restaurant_facilities')->whereIn('restaurant_id', $ids)->delete();
        DB::table('restaurant_opening_hours')->whereIn('restaurant_id', $ids)->delete();

        Restaurant::query()->whereIn('id', $ids)->forceDelete();
    }

    /**
     * @param  list<string>  $cuisines
     * @param  list<string>  $facilities
     * @param  ?array{0: string, 1: string}  $hours
     * @param  ?array<int, list<array{0: string, 1: string}>>  $schedule
     * @param  list<array{alt: ?string, url: string}>  $media
     */
    private function create(
        string $name,
        float $fraction,
        float $offsetMetres,
        array $cuisines,
        array $facilities,
        bool $alwaysOpen = false,
        ?array $hours = null,
        RestaurantStatus $status = RestaurantStatus::Approved,
        RestaurantVerificationStatus $verification = RestaurantVerificationStatus::Verified,
        bool $acceptingOrders = true,
        ?int $priceLevel = 2,
        ?array $schedule = null,
        ?string $description = null,
        ?string $publicPhone = null,
        array $media = [],
    ): void {
        [$latitude, $longitude] = $this->offsetFromRoute($fraction, $offsetMetres);

        $this->createAt(
            name: $name,
            latitude: $latitude,
            longitude: $longitude,
            cuisines: $cuisines,
            facilities: $facilities,
            alwaysOpen: $alwaysOpen,
            hours: $hours,
            status: $status,
            verification: $verification,
            acceptingOrders: $acceptingOrders,
            priceLevel: $priceLevel,
            schedule: $schedule,
            description: $description,
            publicPhone: $publicPhone,
            media: $media,
        );
    }

    /**
     * @param  list<string>  $cuisines
     * @param  list<string>  $facilities
     * @param  ?array{0: string, 1: string}  $hours
     * @param  ?array<int, list<array{0: string, 1: string}>>  $schedule
     * @param  list<array{alt: ?string, url: string}>  $media
     */
    private function createAt(
        string $name,
        float $latitude,
        float $longitude,
        array $cuisines,
        array $facilities,
        bool $alwaysOpen = false,
        ?array $hours = null,
        RestaurantStatus $status = RestaurantStatus::Approved,
        RestaurantVerificationStatus $verification = RestaurantVerificationStatus::Verified,
        bool $acceptingOrders = true,
        ?int $priceLevel = 2,
        ?array $schedule = null,
        ?string $description = null,
        ?string $publicPhone = null,
        array $media = [],
    ): void {
        $restaurant = new Restaurant;

        $restaurant->forceFill([
            'uuid' => (string) Str::uuid(),
            'name' => $name,
            'latitude' => round($latitude, 7),
            'longitude' => round($longitude, 7),
            'formatted_address' => 'Fixture position, NH 48 corridor',
            'city' => 'Fixture',
            'region' => 'Fixture',
            'country_code' => 'IN',
            'timezone' => 'Asia/Kolkata',
            'status' => $status,
            'verification_status' => $verification,
            'is_discoverable' => true,
            'is_accepting_orders' => $acceptingOrders,
            'price_level' => $priceLevel,
            // Null. There is no reviews module, so there is no rating, and a
            // fixture that carried one would be the exact fabrication the
            // module forbids.
            'rating_average' => null,
            'rating_count' => 0,
            'internal_notes' => 'Discovery fixture. Not a real business.',
            'owner_phone' => '+910000000000',
            // Module 09. Both nullable and both frequently null, because the
            // "this restaurant told us nothing" case has to be a real fixture
            // rather than a branch nobody exercises.
            'description' => $description,
            'public_phone' => $publicPhone,
        ])->save();

        foreach ($media as $position => $image) {
            RestaurantMedia::add($restaurant, [
                'url' => $image['url'],
                'thumbnail_url' => $image['thumbnail'] ?? null,
                'alt_text' => $image['alt'] ?? null,
                'position' => $position,
                'is_active' => $image['active'] ?? true,
            ]);
        }

        foreach ($cuisines as $position => $cuisine) {
            $restaurant->cuisines()->create(['cuisine' => $cuisine, 'position' => $position]);
        }

        foreach ($facilities as $position => $facility) {
            $restaurant->facilities()->create(['facility' => $facility, 'position' => $position]);
        }

        // A per-day schedule wins where one is given: it is the only way to
        // express a split service, an overnight window, or a day the kitchen
        // is shut, and those three are exactly what Module 09's hours section
        // has to get right.
        if ($schedule !== null) {
            foreach ($schedule as $day => $windows) {
                foreach ($windows as $window) {
                    $restaurant->openingHours()->create([
                        'day_of_week' => $day,
                        'opens_at' => $window[0],
                        'closes_at' => $window[1],
                    ]);
                }
            }

            return;
        }

        $window = $alwaysOpen ? ['00:00:00', '23:59:59'] : $hours;

        if ($window !== null) {
            foreach (range(0, 6) as $day) {
                $restaurant->openingHours()->create([
                    'day_of_week' => $day,
                    'opens_at' => $window[0],
                    'closes_at' => $window[1],
                ]);
            }
        }
    }

    /**
     * A point a given fraction along the origin-destination line, pushed
     * sideways by a given distance.
     *
     * The offset is genuinely perpendicular: the along-route direction is
     * rotated ninety degrees before it is applied, with the longitude component
     * scaled by the cosine of the latitude so that a metre is a metre in both
     * axes. Offsetting in latitude alone — the obvious shortcut — would put the
     * fixture at an angle to the route and make its stated distance wrong.
     *
     * @return array{0: float, 1: float}
     */
    private function offsetFromRoute(float $fraction, float $offsetMetres): array
    {
        $latitude = self::ORIGIN[0] + (self::DESTINATION[0] - self::ORIGIN[0]) * $fraction;
        $longitude = self::ORIGIN[1] + (self::DESTINATION[1] - self::ORIGIN[1]) * $fraction;

        $cos = cos(deg2rad($latitude));

        // The route's direction, in metres.
        $dx = (self::DESTINATION[1] - self::ORIGIN[1]) * $cos;
        $dy = self::DESTINATION[0] - self::ORIGIN[0];

        $length = sqrt($dx * $dx + $dy * $dy);

        // Rotate ninety degrees: (dx, dy) becomes (-dy, dx).
        $perpX = -$dy / $length;
        $perpY = $dx / $length;

        $degreesPerMetre = rad2deg(1 / 6_371_008.8);

        return [
            $latitude + $perpY * $offsetMetres * $degreesPerMetre,
            $longitude + ($perpX * $offsetMetres * $degreesPerMetre) / $cos,
        ];
    }
}
