<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\RestaurantStatus;
use App\Enums\RestaurantVerificationStatus;
use App\Models\Restaurant;
use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Who a customer is allowed to see.
 *
 * The most security-shaped part of this module. A restaurant appearing that
 * should not is not a rendering bug — it is the platform recommending a business
 * it has suspended, or never checked, to somebody about to drive to it.
 */
final class RestaurantEligibilityTest extends TestCase
{
    use RefreshDatabase;

    private RestaurantDiscoveryEligibilityService $eligibility;

    protected function setUp(): void
    {
        parent::setUp();

        $this->eligibility = new RestaurantDiscoveryEligibilityService;
    }

    private function approved(array $overrides = []): Restaurant
    {
        return Restaurant::factory()
            ->discoverable()
            ->at(28.5, 77.2)
            ->create($overrides);
    }

    public function test_an_approved_verified_listed_restaurant_with_a_position_is_eligible(): void
    {
        $this->assertTrue($this->eligibility->isEligible($this->approved()));
    }

    public function test_a_suspended_restaurant_is_never_eligible(): void
    {
        $restaurant = $this->approved(['status' => RestaurantStatus::Suspended]);

        $this->assertFalse($this->eligibility->isEligible($restaurant));
        $this->assertSame('status', $this->eligibility->reasonIneligible($restaurant));
    }

    public function test_a_disabled_restaurant_is_never_eligible(): void
    {
        $this->assertFalse($this->eligibility->isEligible(
            $this->approved(['status' => RestaurantStatus::Disabled]),
        ));
    }

    public function test_a_draft_or_permanently_closed_restaurant_is_never_eligible(): void
    {
        foreach ([
            RestaurantStatus::Draft,
            RestaurantStatus::PendingVerification,
            RestaurantStatus::ClosedPermanently,
        ] as $status) {
            $this->assertFalse(
                $this->eligibility->isEligible($this->approved(['status' => $status])),
                "{$status->value} must not be discoverable",
            );
        }
    }

    public function test_an_unverified_restaurant_is_never_eligible(): void
    {
        $restaurant = $this->approved([
            'verification_status' => RestaurantVerificationStatus::Pending,
        ]);

        $this->assertFalse($this->eligibility->isEligible($restaurant));
        $this->assertSame('verification', $this->eligibility->reasonIneligible($restaurant));
    }

    public function test_a_rejected_restaurant_is_never_eligible(): void
    {
        $this->assertFalse($this->eligibility->isEligible($this->approved([
            'verification_status' => RestaurantVerificationStatus::Rejected,
        ])));
    }

    public function test_a_restaurant_switched_off_by_its_operator_is_not_eligible(): void
    {
        $restaurant = $this->approved(['is_discoverable' => false]);

        $this->assertFalse($this->eligibility->isEligible($restaurant));
        $this->assertSame('not_discoverable', $this->eligibility->reasonIneligible($restaurant));
    }

    public function test_a_restaurant_with_no_coordinates_is_not_route_discoverable(): void
    {
        // The rule that matters most in this list. A restaurant cannot be placed
        // on a route without a position, and deriving one from its address text
        // would put a marker on a map and a customer in a field.
        $restaurant = Restaurant::factory()->discoverable()->create([
            'latitude' => null,
            'longitude' => null,
        ]);

        $this->assertFalse($this->eligibility->isEligible($restaurant));
        $this->assertSame('no_position', $this->eligibility->reasonIneligible($restaurant));
    }

    public function test_half_a_coordinate_is_not_a_position(): void
    {
        $this->assertFalse($this->eligibility->isEligible(
            Restaurant::factory()->discoverable()->create([
                'latitude' => 28.5,
                'longitude' => null,
            ]),
        ));
    }

    public function test_a_deleted_restaurant_is_not_eligible(): void
    {
        $restaurant = $this->approved();
        $restaurant->delete();

        $this->assertFalse($this->eligibility->isEligible($restaurant));
    }

    public function test_being_closed_is_not_ineligibility(): void
    {
        // Availability and eligibility are different questions, and conflating
        // them would hide a restaurant that opens in twenty minutes from a
        // traveller two hours away.
        $restaurant = $this->approved();

        $this->assertTrue($this->eligibility->isEligible($restaurant));
    }

    public function test_being_paused_is_not_ineligibility(): void
    {
        $this->assertTrue($this->eligibility->isEligible(
            $this->approved(['is_accepting_orders' => false]),
        ));
    }

    public function test_the_sql_scope_and_the_service_never_disagree(): void
    {
        // Two expressions of one rule, and this is the price of having two. Every
        // combination is built, saved, and put to both: the scope decides what
        // the database returns, the service decides what the code believes, and
        // a divergence between them is how a suspended restaurant reaches a
        // screen.
        $combinations = 0;

        foreach (RestaurantStatus::cases() as $status) {
            foreach (RestaurantVerificationStatus::cases() as $verification) {
                foreach ([true, false] as $listed) {
                    foreach ([true, false] as $positioned) {
                        $restaurant = Restaurant::factory()->create([
                            'status' => $status,
                            'verification_status' => $verification,
                            'is_discoverable' => $listed,
                            'latitude' => $positioned ? 28.5 : null,
                            'longitude' => $positioned ? 77.2 : null,
                        ]);

                        $inScope = Restaurant::query()
                            ->discoverable()
                            ->whereKey($restaurant->getKey())
                            ->exists();

                        $this->assertSame(
                            $inScope,
                            $this->eligibility->isEligible($restaurant),
                            sprintf(
                                'scope and service disagree for %s / %s / listed=%s / positioned=%s',
                                $status->value,
                                $verification->value,
                                var_export($listed, true),
                                var_export($positioned, true),
                            ),
                        );

                        $combinations++;
                    }
                }
            }
        }

        $this->assertSame(72, $combinations);
    }
}
