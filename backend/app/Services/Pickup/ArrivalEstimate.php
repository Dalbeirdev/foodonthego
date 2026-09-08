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
     * The customer-facing shape, on the counter's clock.
     *
     * The zone is a parameter rather than a field because an arrival estimate
     * does not have one: it is a moment, and the moment is the same whichever
     * clock reads it. What it must not do is reach a response on a different
     * clock from the pickup window beside it — see the rule in
     * [PickupPlan::toApiArray].
     *
     * @return array<string, mixed>
     */
    public function toApiArray(string $timezone): array
    {
        $local = static fn (?CarbonImmutable $instant): ?string => $instant === null
            ? null
            : ($timezone === '' ? $instant : $instant->setTimezone($timezone))->toIso8601String();

        return [
            'estimated_arrival_at' => $local($this->arrivalAt),
            'travel_minutes' => $this->travelMinutes(),
            'basis' => $this->source,
            'calculated_at' => $local($this->calculatedAt),
            'is_fresh' => $this->isFresh,
        ];
    }
}
