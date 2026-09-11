<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\RestaurantAvailability;
use App\Enums\RestaurantOrderingState;
use App\Enums\RestaurantStatus;
use PHPUnit\Framework\TestCase;

/**
 * Whether a customer can proceed towards ordering.
 *
 * A rollup of two independent facts, and the tests exist because the wrong
 * combination of them is the one mistake on this screen a customer pays for:
 * a live "View menu" button on a kitchen that has stopped cooking sends
 * somebody forty kilometres for nothing.
 */
final class RestaurantOrderingStateTest extends TestCase
{
    public function test_open_and_cooking_is_the_only_orderable_state(): void
    {
        foreach ([RestaurantAvailability::Open, RestaurantAvailability::ClosingSoon] as $availability) {
            $state = RestaurantOrderingState::resolve(RestaurantStatus::Approved, $availability);

            $this->assertSame(RestaurantOrderingState::OpenAccepting, $state);
            $this->assertTrue($state->canOrder());
        }
    }

    public function test_closing_soon_is_still_open(): void
    {
        // A restaurant twenty minutes from closing can still take an order from
        // somebody five minutes away. Treating it as shut would lose them both.
        $this->assertTrue(
            RestaurantOrderingState::resolve(
                RestaurantStatus::Approved,
                RestaurantAvailability::ClosingSoon,
            )->canOrder(),
        );
    }

    public function test_a_paused_kitchen_is_open_and_not_orderable(): void
    {
        $state = RestaurantOrderingState::resolve(
            RestaurantStatus::Approved,
            RestaurantAvailability::NotAcceptingOrders,
        );

        $this->assertSame(RestaurantOrderingState::OpenPaused, $state);
        $this->assertFalse($state->canOrder());
        // Still worth reading the menu: the pause may lift before the traveller
        // arrives.
        $this->assertTrue($state->permitsBrowsing());
    }

    public function test_shut_and_about_to_open_are_both_closed(): void
    {
        foreach ([RestaurantAvailability::Closed, RestaurantAvailability::OpeningSoon] as $availability) {
            $state = RestaurantOrderingState::resolve(RestaurantStatus::Approved, $availability);

            // "Opens soon" is a nicety on a card. It is not permission to order.
            $this->assertSame(RestaurantOrderingState::Closed, $state);
            $this->assertFalse($state->canOrder());
            $this->assertTrue($state->permitsBrowsing());
        }
    }

    public function test_unknown_hours_never_become_permission(): void
    {
        $state = RestaurantOrderingState::resolve(
            RestaurantStatus::Approved,
            RestaurantAvailability::Unknown,
        );

        // An absence, reported as one. The safe direction for a missing fact to
        // fall is towards "we don't know", never towards "yes, go ahead".
        $this->assertSame(RestaurantOrderingState::Unavailable, $state);
        $this->assertFalse($state->canOrder());
        $this->assertFalse($state->permitsBrowsing());
    }

    public function test_a_permanently_closed_business_is_never_open(): void
    {
        // Inside its old opening hours, which is exactly the case a naive
        // implementation gets wrong.
        $state = RestaurantOrderingState::resolve(
            RestaurantStatus::ClosedPermanently,
            RestaurantAvailability::Open,
        );

        $this->assertSame(RestaurantOrderingState::ClosedPermanently, $state);
        $this->assertFalse($state->canOrder());
        // And its menu describes something that no longer exists.
        $this->assertFalse($state->permitsBrowsing());
    }

    public function test_no_undiscoverable_status_can_produce_an_orderable_state(): void
    {
        foreach (RestaurantStatus::cases() as $status) {
            if ($status->permitsDiscovery()) {
                continue;
            }

            foreach (RestaurantAvailability::cases() as $availability) {
                $this->assertFalse(
                    RestaurantOrderingState::resolve($status, $availability)->canOrder(),
                    "{$status->value} + {$availability->value} produced an orderable state",
                );
            }
        }
    }

    public function test_every_availability_maps_somewhere(): void
    {
        // A case added later must not fall through a match and throw on a
        // customer's screen.
        foreach (RestaurantAvailability::cases() as $availability) {
            $this->assertInstanceOf(
                RestaurantOrderingState::class,
                RestaurantOrderingState::resolve(RestaurantStatus::Approved, $availability),
            );
        }
    }
}
