<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\CartStatus;
use App\Models\Cart;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Testing\TestResponse;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What happens to a cart when the journey it belongs to ends.
 *
 * This file exists because of KI-014, which was not found by reading the code.
 * It was found by the first on-device run that got as far as adding to a cart,
 * and it had been sitting in Module 11 the whole time: a customer who cancelled
 * a journey holding a cart could never add to a cart again, on any journey, and
 * no screen could reach the cart that was blocking them because it sat on a
 * cancelled trip.
 */
final class CartLifecycleApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Restaurant $restaurant;

    /** @var array<string, mixed> */
    private array $menu;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $this->menu = MenuFixtures::configurableItem($this->restaurant);
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function journey(): Trip
    {
        return RestaurantFixtures::tripWithSelectedRoute($this->rahul);
    }

    /** @return array<string, mixed> */
    private function body(): array
    {
        return [
            'item_id' => $this->menu['item']->uuid,
            'variant_id' => $this->menu['large']->uuid,
            'modifier_groups' => [
                [
                    'group_id' => $this->menu['spice']->uuid,
                    'option_ids' => [$this->menu['mild']->uuid],
                ],
            ],
            'quantity' => 1,
        ];
    }

    private function addTo(Trip $trip): TestResponse
    {
        return $this->asRahul()->postJson(
            '/api/v1/customer/trips/'.$trip->uuid
                .'/restaurants/'.$this->restaurant->uuid.'/cart/items',
            $this->body(),
        );
    }

    /**
     * KI-014, as four requests.
     *
     * Exactly the sequence recorded in docs/13-known-issues.md, reproduced
     * against a real backend before it was fixed. The fourth request used to be
     * a 409 CART_TRIP_CONFLICT naming a cart on a journey the customer had
     * already cancelled, and there was no way out of it in Module 11.
     */
    public function test_a_customer_who_cancels_a_journey_can_still_use_a_cart_afterwards(): void
    {
        $first = $this->journey();

        $this->addTo($first)->assertCreated();

        $this->asRahul()
            ->postJson('/api/v1/customer/trips/'.$first->uuid.'/discard')
            ->assertOk();

        $second = $this->journey();

        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$second->uuid.'/cart')
            ->assertOk()
            ->assertJsonPath('data.cart', null);

        // The request that had no answer.
        $this->addTo($second)->assertCreated();
    }

    public function test_discarding_a_journey_closes_its_cart_rather_than_deleting_it(): void
    {
        $trip = $this->journey();

        $this->addTo($trip)->assertCreated();

        /** @var Cart $cart */
        $cart = Cart::query()->where('trip_id', $trip->id)->firstOrFail();
        $this->assertSame(CartStatus::Active, $cart->status);
        $lines = $cart->items()->count();
        $this->assertSame(1, $lines);

        $this->asRahul()
            ->postJson('/api/v1/customer/trips/'.$trip->uuid.'/discard')
            ->assertOk();

        $cart->refresh();

        // Closed, not gone: Module 13's orders will point at these rows, and a
        // customer's selections are not the platform's to destroy.
        $this->assertSame(CartStatus::Closed, $cart->status);
        $this->assertSame($lines, $cart->items()->count());
    }

    public function test_a_second_journey_keeps_its_own_cart_when_the_first_is_discarded(): void
    {
        $kept = $this->journey();

        $this->addTo($kept)->assertCreated();

        /** @var Cart $keptCart */
        $keptCart = Cart::query()->where('trip_id', $kept->id)->firstOrFail();

        $abandoned = $this->journey();

        $this->asRahul()
            ->postJson('/api/v1/customer/trips/'.$abandoned->uuid.'/discard')
            ->assertOk();

        // Discarding a journey with no cart of its own must not reach across to
        // somebody else's — including this customer's other journey.
        $keptCart->refresh();
        $this->assertSame(CartStatus::Active, $keptCart->status);
    }
}
