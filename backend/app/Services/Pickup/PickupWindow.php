<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use Carbon\CarbonImmutable;

/**
 * One selectable interval. "4:10 PM – 4:20 PM".
 *
 * A window rather than an instant, because a kitchen is not a train timetable.
 * Promising 4:13 exactly would be a precision no restaurant has and no customer
 * believes, and the first time it slipped by two minutes the promise would be
 * the thing that felt broken.
 */
final readonly class PickupWindow
{
    public function __construct(
        public CarbonImmutable $startAt,
        public CarbonImmutable $endAt,
    ) {}

    public function contains(CarbonImmutable $moment): bool
    {
        return $moment >= $this->startAt && $moment <= $this->endAt;
    }

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'start_at' => $this->startAt->toIso8601String(),
            'end_at' => $this->endAt->toIso8601String(),
        ];
    }
}
