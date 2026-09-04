<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Whether the platform has checked who this restaurant is.
 *
 * Separate from {@see RestaurantStatus} because the two can disagree in both
 * directions, and because they are owned by different processes: verification is
 * a compliance outcome, status is a commercial one. Showing a customer a
 * restaurant whose onboarding was never completed is the sort of mistake that is
 * only noticed after somebody has driven to it.
 */
enum RestaurantVerificationStatus: string
{
    case Pending = 'PENDING';
    case Verified = 'VERIFIED';
    case Rejected = 'REJECTED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    public function permitsDiscovery(): bool
    {
        return $this === self::Verified;
    }
}
