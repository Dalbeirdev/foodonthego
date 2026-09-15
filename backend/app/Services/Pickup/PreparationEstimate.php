<?php

declare(strict_types=1);

namespace App\Services\Pickup;

/**
 * How long the kitchen needs for this cart, and where that number came from.
 *
 * The provenance travels with the figure because a preparation estimate built
 * entirely on platform fallbacks is a very different thing from one an operator
 * actually set, and only one of them is worth trusting. Nothing shows a customer
 * the difference; it exists so that whoever debugs a wrong pickup time can see
 * in one field whether the data was ever there.
 */
final readonly class PreparationEstimate
{
    /**
     * @param  list<array{line: string, minutes: int, source: string}>  $lines
     */
    public function __construct(
        public int $minutes,
        public array $lines,
        /** True when any line fell past its own and its restaurant's figure. */
        public bool $usedPlatformFallback,
    ) {}

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        // The per-line breakdown is deliberately NOT on the wire. A customer
        // does not need to know which dish is the slow one, and an operator's
        // preparation times are their business rather than a competitor's.
        // The total is what the screen explains; the detail is for logs.
        return ['preparation_minutes' => $this->minutes];
    }
}
