<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * A restaurant's business standing on the platform.
 *
 * Deliberately separate from {@see RestaurantVerificationStatus} and from the
 * customer-facing toggle, because the three answer different questions and a
 * single "active" flag would collapse them: a restaurant can be perfectly
 * verified and still suspended, or approved and simply not switched on yet.
 *
 * Only {@see Approved} is ever discoverable. The rest are listed so that the
 * reason a restaurant is absent is recorded rather than inferred — an operator
 * asking "why can nobody see us" needs an answer, and "not approved" and
 * "suspended" are very different conversations.
 */
enum RestaurantStatus: string
{
    /** Being filled in. Has never been submitted. */
    case Draft = 'DRAFT';

    /** Submitted, waiting on the platform. */
    case PendingVerification = 'PENDING_VERIFICATION';

    /** Cleared to trade. */
    case Approved = 'APPROVED';

    /** Cleared once, stopped by the platform. Reversible. */
    case Suspended = 'SUSPENDED';

    /** Switched off by the platform or the operator. Reversible. */
    case Disabled = 'DISABLED';

    /** Gone. Not reversible, and not a state a customer should ever meet. */
    case ClosedPermanently = 'CLOSED_PERMANENTLY';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    /**
     * Whether this status alone permits a customer to see the restaurant.
     *
     * An allow-list, not a deny-list. A status added later is invisible until
     * somebody decides it should be visible, which is the safe direction for a
     * mistake to fall.
     */
    public function permitsDiscovery(): bool
    {
        return $this === self::Approved;
    }
}
