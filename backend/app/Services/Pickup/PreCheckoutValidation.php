<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Enums\PickupSelectionStatus;
use App\Enums\PreCheckoutIssue;
use App\Services\Cart\CartRevalidation;

/**
 * Whether this cart is ready to be paid for, and what is stopping it.
 *
 * **`readyForCheckout` is computed here and nowhere else.** It is not a flag a
 * client sets, not a field a request can carry, and not something a screen may
 * decide by looking at the issue list itself — a client that reasoned its own
 * way to "ready" would be one release away from disagreeing with the server
 * about whether a customer may be charged.
 *
 * Nothing in this module acts on the answer. Module 14 will revalidate the
 * whole lot again before a payment exists, because the gap between this
 * response and that one is exactly long enough for a kitchen to close.
 */
final readonly class PreCheckoutValidation
{
    /**
     * @param  list<array{issue: PreCheckoutIssue, message: string}>  $issues
     */
    public function __construct(
        public CartRevalidation $revalidation,
        public PickupPlan $plan,
        public PickupSelectionStatus $selectionStatus,
        public array $issues,
    ) {}

    public function readyForCheckout(): bool
    {
        foreach ($this->issues as $issue) {
            if ($issue['issue']->blocksCheckout()) {
                return false;
            }
        }

        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'ready_for_checkout' => $this->readyForCheckout(),
            'selection_status' => $this->selectionStatus->value,
            'issues' => array_map(
                static fn (array $issue): array => [
                    'code' => $issue['issue']->value,
                    'message' => $issue['message'],
                    'blocking' => $issue['issue']->blocksCheckout(),
                ],
                $this->issues,
            ),
        ];
    }
}
