<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\RestaurantMedia;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What opening a restaurant costs.
 *
 * Two claims, both asserted rather than reasoned about: the query count does
 * not grow with the number of photographs, cuisines or facilities a restaurant
 * has, and it does not grow with the number of restaurants on the route.
 */
final class RestaurantDetailPerformanceTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    /** @return array{0: int, 1: float} queries, milliseconds */
    private function costOfOpening(string $uuid): array
    {
        DB::flushQueryLog();
        DB::enableQueryLog();

        $start = hrtime(true);

        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants/'.$uuid)
            ->assertOk();

        $ms = (hrtime(true) - $start) / 1e6;
        $queries = count(DB::getQueryLog());

        DB::disableQueryLog();

        return [$queries, $ms];
    }

    public function test_the_query_count_does_not_grow_with_the_photographs(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        // Warm the discovery cache, as a customer arriving from the list has.
        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();

        [$bare] = $this->costOfOpening($restaurant->uuid);

        for ($i = 0; $i < 20; $i++) {
            RestaurantMedia::add($restaurant, [
                'url' => 'https://cdn.example.test/'.$i.'.jpg',
                'position' => $i,
                'is_active' => true,
            ]);
        }

        for ($i = 0; $i < 10; $i++) {
            $restaurant->cuisines()->create(['cuisine' => "Cuisine {$i}", 'position' => 10 + $i]);
            $restaurant->facilities()->create(['facility' => "Facility {$i}", 'position' => 10 + $i]);
        }

        [$loaded] = $this->costOfOpening($restaurant->uuid);

        // Eager loading, not a loop. Twenty more photographs is twenty more
        // rows in one query, not twenty more queries.
        $this->assertSame($bare, $loaded);
    }

    public function test_the_query_count_does_not_grow_with_the_route(): void
    {
        $first = RestaurantFixtures::nearRoute(0.2, 800, 'First Stop');

        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();

        [$short] = $this->costOfOpening($first->uuid);

        Cache::flush();

        foreach (range(1, 15) as $n) {
            RestaurantFixtures::nearRoute(0.2 + $n * 0.04, 900, "Stop {$n}");
        }

        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();

        [$long] = $this->costOfOpening($first->uuid);

        // The corridor query returns more rows; it is still one query, and the
        // eager loads are still one each.
        $this->assertSame($short, $long);
    }

    public function test_opening_several_restaurants_costs_the_same_each_time(): void
    {

        $uuids = [];

        foreach (range(1, 5) as $n) {
            $uuids[] = RestaurantFixtures::nearRoute(0.1 + $n * 0.12, 800, "Stop {$n}")->uuid;
        }

        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();

        $counts = [];

        foreach ($uuids as $uuid) {
            [$queries] = $this->costOfOpening($uuid);
            $counts[] = $queries;
        }

        // A customer tapping through the list pays the same each time. The
        // corridor search behind them is cached and is not repeated.
        $this->assertSame([$counts[0]], array_values(array_unique($counts)));
    }
}
