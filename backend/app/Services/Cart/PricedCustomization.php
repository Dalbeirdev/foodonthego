<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Support\Money;

/**
 * What a configuration costs, with the arithmetic shown.
 *
 * The breakdown is not decoration. A customer looking at ₹778 should be able to
 * see where it came from — the size, each paid option, the unit price, the
 * quantity — because a total nobody can check is a total nobody trusts, and
 * because the day this disagrees with a till receipt the breakdown is what
 * settles it.
 */
final readonly class PricedCustomization
{
    /**
     * @param  list<array{name: string, group: string, amount: Money}>  $additions
     */
    public function __construct(
        public Money $base,
        public array $additions,
        public Money $unitPrice,
        public int $quantity,
        public Money $lineTotal,
        public ?string $baseLabel = null,
    ) {}

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        return [
            'base' => [
                'label' => $this->baseLabel,
                'amount' => $this->base->toApiArray(),
            ],
            'additions' => array_map(
                static fn (array $addition): array => [
                    'group' => $addition['group'],
                    'name' => $addition['name'],
                    'amount' => $addition['amount']->toApiArray(),
                ],
                $this->additions,
            ),
            'unit_price' => $this->unitPrice->toApiArray(),
            'quantity' => $this->quantity,
            'line_total' => $this->lineTotal->toApiArray(),
        ];
    }
}
