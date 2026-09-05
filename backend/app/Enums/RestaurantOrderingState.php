<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Whether a customer can proceed towards ordering, and why not if not.
 *
 * A rollup of two facts a customer should not have to combine themselves:
 * {@see RestaurantStatus} (is this business trading at all) and
 * {@see RestaurantAvailability} (are its doors open and its kitchen taking
 * orders). Five cases, because those are the five different things a detail
 * screen has to say and the five different states its main button has to be in.
 *
 * This does **not** replace `availability`. Module 07 and Module 08 speak that
 * vocabulary and go on speaking it; a detail response carries both, and this is
 * the derived one. Two names for one concept would be a bug; one name for two
 * concepts is worse.
 *
 * Deliberately not a boolean. "Cannot order" covers a restaurant that is shut
 * until tomorrow, one that is open but has paused its kitchen, and one that has
 * closed for good — three different sentences and three different next moves
 * for the customer.
 */
enum RestaurantOrderingState: string
{
    /** Trading, open, and taking orders. The only case with a live CTA. */
    case OpenAccepting = 'OPEN_ACCEPTING';

    /** The lights are on and the kitchen has stopped. Reversible, today. */
    case OpenPaused = 'OPEN_PAUSED';

    /** Outside its opening hours. Opens again; the detail screen says when. */
    case Closed = 'CLOSED';

    /** Gone for good. Never a live CTA, and never "opens at". */
    case ClosedPermanently = 'CLOSED_PERMANENTLY';

    /**
     * No opening hours on file, or a state this build cannot interpret.
     *
     * Not a claim that the restaurant is shut — an absence, reported as one.
     * The safe direction for a missing fact to fall is towards "we don't know",
     * never towards "yes, go ahead".
     */
    case Unavailable = 'UNAVAILABLE';

    /**
     * Named `resolve` rather than `from`: a backed enum already has a `from`,
     * and shadowing it is a fatal error rather than an override.
     */
    public static function resolve(
        RestaurantStatus $status,
        RestaurantAvailability $availability,
    ): self {
        // The business state beats the clock. A permanently closed restaurant
        // inside its old opening hours is not "open".
        if ($status === RestaurantStatus::ClosedPermanently) {
            return self::ClosedPermanently;
        }

        if (! $status->permitsDiscovery()) {
            return self::Unavailable;
        }

        return match ($availability) {
            RestaurantAvailability::Open,
            RestaurantAvailability::ClosingSoon => self::OpenAccepting,
            RestaurantAvailability::NotAcceptingOrders => self::OpenPaused,
            RestaurantAvailability::Closed,
            RestaurantAvailability::OpeningSoon => self::Closed,
            RestaurantAvailability::Unknown => self::Unavailable,
        };
    }

    /** Whether a customer may proceed towards a menu and an order. */
    public function canOrder(): bool
    {
        return $this === self::OpenAccepting;
    }

    /**
     * Whether the menu may be browsed even though nothing can be ordered.
     *
     * True for a restaurant that is merely shut or paused — a traveller two
     * hours away deciding where to stop wants to read the menu now and order
     * when they arrive. False once a business has closed for good, where the
     * menu describes something that no longer exists.
     *
     * Module 10 owns the menu; this is the flag it will read, defined here so
     * the rule is settled before the screen that depends on it is built.
     */
    public function permitsBrowsing(): bool
    {
        return $this !== self::ClosedPermanently && $this !== self::Unavailable;
    }
}
