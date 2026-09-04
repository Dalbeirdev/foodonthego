<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Rahul and Ananya, and the line between them.
 *
 * Restaurants are public information — anybody may know that a dhaba exists on
 * NH 48. A *journey* is not, and neither is the set of restaurants somebody was
 * shown for it: that set describes where they are going, when, and by which
 * road. So discovery is scoped to the trip's owner even though its contents are
 * not secret.
 */
final class TripRestaurantOwnershipTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private User $ananya;

    private string $rahulToken;

    private Trip $hers;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->rahulToken = CustomerFactory::tokenFor($this->rahul);

        $this->hers = RestaurantFixtures::tripWithSelectedRoute($this->ananya);

        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->rahulToken);
    }

    private function url(Trip $trip): string
    {
        return "/api/v1/customer/trips/{$trip->uuid}/restaurants";
    }

    public function test_rahul_cannot_discover_restaurants_on_ananyas_trip(): void
    {
        $this->asRahul()->getJson($this->url($this->hers))->assertNotFound();
    }

    public function test_the_refusal_is_indistinguishable_from_a_missing_trip(): void
    {
        $hers = $this->asRahul()->getJson($this->url($this->hers));
        $missing = $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.Str::uuid().'/restaurants');

        // Otherwise the endpoint is an oracle for which trip ids are real.
        $hers->assertNotFound();
        $missing->assertNotFound();
        $this->assertSame(
            $missing->json('error.code'),
            $hers->json('error.code'),
        );
    }

    public function test_no_refusal_leaks_a_word_about_her_journey(): void
    {
        $body = $this->asRahul()->getJson($this->url($this->hers))->content();

        $route = $this->hers->routes()->first();

        foreach ([
            $route->uuid,
            $route->encoded_polyline,
            (string) $this->hers->destination_name,
            'Highway Spice Kitchen',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body);
        }
    }

    public function test_a_trip_id_is_the_only_identifier_the_endpoint_accepts(): void
    {
        // There is no route id in the path, so there is nothing to substitute
        // for somebody else's — the route searched is whichever one the
        // customer selected on their own trip. This pins that shape: a
        // hand-built path carrying a route id is simply not a route.
        $mine = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $herRoute = $this->hers->routes()->first();

        $this->asRahul()
            ->getJson("/api/v1/customer/trips/{$mine->uuid}/restaurants/{$herRoute->uuid}")
            ->assertNotFound();
    }

    public function test_her_own_discovery_still_works(): void
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($this->ananya))
            ->getJson($this->url($this->hers))
            ->assertOk()
            ->assertJsonPath('data.restaurants.0.name', 'Highway Spice Kitchen');
    }

    public function test_a_revoked_session_reaches_no_discovery(): void
    {
        $mine = RestaurantFixtures::tripWithSelectedRoute($this->rahul);

        $this->asRahul()->getJson($this->url($mine))->assertOk();

        $this->rahul->tokens()->delete();

        $this->asRahul()->getJson($this->url($mine))->assertUnauthorized();
    }
}
