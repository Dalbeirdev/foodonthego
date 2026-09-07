<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use Carbon\CarbonImmutable;

/**
 * When the customer would reach the restaurant, and how much that is worth.
 *
 * The freshness fields are not decoration. An arrival time with no indication of
 * how it was reached or when is a number a screen will present as current
 * forever, and the whole difficulty of this module is that travel estimates go
 * off.
 */
final readonly class ArrivalEstimate
{
    public function __construct(
        public CarbonImmutable $arrivalAt,
        public int $travelSeconds,
        /** Which implementation produced this — 'planned_route' today. */
        public string $source,
        /** When the underlying travel data was calculated, not when this was read. */
        public ?CarbonImmutable $calculatedAt,
        public bool $isFresh,
    ) {}

    public function travelMinutes(): int
    {
        return (int) round($this->travelSeconds / 60);
    }

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'estimated_arrival_at' => $this->arrivalAt->toIso8601String(),
            'travel_minutes' => $this->travelMinutes(),
            'basis' => $this->source,
            'calculated_at' => $this->calculatedAt?->toIso8601String(),
            'is_fresh' => $this->isFresh,
        ];
    }
}
