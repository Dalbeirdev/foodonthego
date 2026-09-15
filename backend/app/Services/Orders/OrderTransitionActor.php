<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\OrderTransitionSource;
use App\Models\User;

/**
 * Who is moving an order, as the server knows it.
 *
 * A VALUE OBJECT RATHER THAN THREE ARGUMENTS, so that a caller cannot pass a
 * source that disagrees with the principal it came from. Every constructor here
 * is a named factory, and each one is a claim about where the authority came
 * from — which makes an unauthorised transition a thing you have to write
 * deliberately rather than a thing you can reach by getting an argument order
 * wrong.
 *
 * NOTHING HERE IS BUILT FROM A REQUEST BODY. `restaurant()` takes a User the
 * caller has already authenticated and a restaurant id the caller has already
 * checked the assignment for; it does not do the checking, and
 * OrderTransitionService refuses the transition if the restaurant does not
 * match the order's.
 */
final readonly class OrderTransitionActor
{
    private function __construct(
        public OrderTransitionSource $source,
        public ?string $actorType = null,
        public ?int $actorId = null,
        public ?int $restaurantId = null,
    ) {}

    /** The platform itself: placement, recovery, reconciliation. */
    public static function system(): self
    {
        return new self(OrderTransitionSource::System);
    }

    /** A payment outcome moved the order. */
    public static function payment(): self
    {
        return new self(OrderTransitionSource::Payment);
    }

    /**
     * An operator acting for one restaurant.
     *
     * The restaurant id is carried so the service can refuse a transition
     * against another tenant's order. Modules 18–19 will be the first callers;
     * the path is tested now, with controlled identities, so that it is not
     * being written for the first time under a deadline.
     */
    public static function restaurant(User $operator, int $restaurantId): self
    {
        return new self(
            OrderTransitionSource::Restaurant,
            $operator::class,
            (int) $operator->getKey(),
            $restaurantId,
        );
    }

    /** A platform administrator, acting deliberately and audibly. */
    public static function admin(User $administrator): self
    {
        return new self(
            OrderTransitionSource::Admin,
            $administrator::class,
            (int) $administrator->getKey(),
        );
    }

    /**
     * A development harness.
     *
     * Rows carrying this source should not exist in a production database,
     * which makes their absence something you can check for.
     */
    public static function testHarness(): self
    {
        return new self(OrderTransitionSource::TestHarness);
    }
}
