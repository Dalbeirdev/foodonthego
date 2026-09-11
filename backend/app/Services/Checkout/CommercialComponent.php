<?php

declare(strict_types=1);

namespace App\Services\Checkout;

use App\Support\Money;

/**
 * One line of a commercial breakdown, and whether anybody chose it.
 *
 * The `configured` flag is the whole point of this class. "Not configured" and
 * "configured as zero" are different facts:
 *
 *   - a restaurant with a null tax rate has **no tax rule**
 *   - a restaurant with a rate of nought has **a rule that says nought**
 *
 * A screen showing "Tax  0.00" for the first case tells a customer a decision
 * was made when none was. So an unconfigured component is omitted from the
 * response entirely, and this flag is what lets the assembler know which is
 * which without the client having to infer it from a zero.
 */
final readonly class CommercialComponent
{
    public function __construct(
        /** Stable code the client branches on: TAX, PACKAGING_FEE, PLATFORM_FEE, DISCOUNT. */
        public string $code,
        public Money $amount,
        public bool $configured,
        /**
         * Where the figure came from, for operators reading logs — never for a
         * customer. A rate or a source name is an internal fact.
         */
        public ?string $basis = null,
    ) {}

    /**
     * The customer-facing shape.
     *
     * No basis, no rate, no source. A customer needs to know what they are
     * paying; the rate that produced it is the platform's business and a
     * competitor's interest.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'code' => $this->code,
            'amount' => $this->amount->toApiArray(),
        ];
    }
}
