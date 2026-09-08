<?php

declare(strict_types=1);

namespace App\Services\Checkout;

use App\Support\Money;

/**
 * What the customer owes, and what each part of it is for.
 *
 * Charges and discounts are kept apart rather than netted, because a customer
 * who cannot see what a discount took off cannot check it — and because a
 * negative charge and a positive discount are the same arithmetic with very
 * different meanings on a receipt.
 */
final readonly class CommercialBreakdown
{
    /**
     * @param  list<CommercialComponent>  $charges
     * @param  list<CommercialComponent>  $discounts
     */
    public function __construct(
        public Money $itemsSubtotal,
        public array $charges,
        public array $discounts,
        public Money $payableTotal,
    ) {}

    /** The components somebody has actually configured, charges and discounts alike. */
    public function configured(): array
    {
        return array_values(array_filter(
            [...$this->charges, ...$this->discounts],
            static fn (CommercialComponent $c): bool => $c->configured,
        ));
    }

    /**
     * The customer-facing shape.
     *
     * **Unconfigured components are absent, not zero.** A response listing
     * "tax: 0" would be the platform stating a tax decision it has not made.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'items_subtotal' => $this->itemsSubtotal->toApiArray(),
            'charges' => array_map(
                static fn (CommercialComponent $c): array => $c->toApiArray(),
                array_values(array_filter(
                    $this->charges,
                    static fn (CommercialComponent $c): bool => $c->configured,
                )),
            ),
            'discounts' => array_map(
                static fn (CommercialComponent $c): array => $c->toApiArray(),
                array_values(array_filter(
                    $this->discounts,
                    static fn (CommercialComponent $c): bool => $c->configured,
                )),
            ),
            'payable_total' => $this->payableTotal->toApiArray(),

            // Said explicitly rather than left to be inferred from an empty
            // list. "Nothing is configured" and "we forgot to send the charges"
            // look identical otherwise, and only one of them is a state a
            // client should render as a final price.
            'has_configured_adjustments' => $this->configured() !== [],
        ];
    }
}
