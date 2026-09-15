<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What revalidation found wrong with a cart line.
 *
 * Deliberately **not** {@see ApiErrorCode}. A revalidation response is a 200:
 * the request succeeded, and what it says is that the world moved. Reusing the
 * error vocabulary would put codes a client handles in a catch block into a
 * body it is meant to render, and the day somebody wires the two together the
 * customer sees an error screen instead of a price change.
 *
 * The values are stable strings on the wire, like every other code in this API.
 * Adding a case is backwards compatible; a client that meets one it does not
 * know shows the accompanying message and refuses to proceed, which is the
 * right behaviour for a finding it cannot reason about.
 */
enum CartRevalidationFinding: string
{
    /** Costs more than when it was added. Both figures accompany it. */
    case PriceIncreased = 'PRICE_INCREASED';

    /** Costs less. Also reported: a customer should see a reduction, not just absorb it. */
    case PriceDecreased = 'PRICE_DECREASED';

    /** Sold out, withdrawn from the menu, or its category was. */
    case ItemUnavailable = 'ITEM_UNAVAILABLE';

    /** The chosen size is gone. */
    case VariantUnavailable = 'VARIANT_UNAVAILABLE';

    /** A chosen option is gone, or the group's rules changed under it. */
    case ModifierUnavailable = 'MODIFIER_UNAVAILABLE';

    /**
     * Whether this finding stops the customer ordering.
     *
     * A price that moved does not: the customer looks at it and decides. A
     * missing dish does, because there is nothing to decide about — the line
     * has to change before the cart means anything.
     */
    public function blocksOrdering(): bool
    {
        return match ($this) {
            self::PriceIncreased, self::PriceDecreased => false,
            self::ItemUnavailable, self::VariantUnavailable, self::ModifierUnavailable => true,
        };
    }

    /**
     * The finding an add-time refusal corresponds to.
     *
     * Revalidation runs a cart line through the same validator an add uses, so
     * what comes back is Module 11's error vocabulary. This is the one place
     * the two are mapped.
     *
     * The fallback arm is deliberate and deliberately pessimistic: a code
     * nobody has mapped means the line could not be priced, and the safe
     * reading of "could not be priced" is that the customer cannot order it —
     * never that it still costs what it did.
     */
    public static function forErrorCode(ApiErrorCode $code): self
    {
        return match ($code) {
            ApiErrorCode::ItemNotFound,
            ApiErrorCode::ItemUnavailable,
            ApiErrorCode::ItemSoldOut,
            ApiErrorCode::MenuNotAvailable => self::ItemUnavailable,

            ApiErrorCode::VariantRequired,
            ApiErrorCode::VariantInvalid,
            ApiErrorCode::VariantUnavailable => self::VariantUnavailable,

            // Min-not-met and max-exceeded are here because a restaurant can
            // change a group's rules after a line was added: a group that
            // becomes required leaves an existing line short of its minimum.
            // The customer's answer is the same either way — reopen the dish
            // and choose again — and the original code travels in the finding's
            // detail so the screen can say something accurate.
            ApiErrorCode::ModifierRequired,
            ApiErrorCode::ModifierInvalid,
            ApiErrorCode::ModifierUnavailable,
            ApiErrorCode::ModifierMinNotMet,
            ApiErrorCode::ModifierMaxExceeded => self::ModifierUnavailable,

            // Anything else means the line could not be priced at all. Reported
            // as an unavailable item, which is what it is from the customer's
            // side, and never as "it still costs what it did".
            default => self::ItemUnavailable,
        };
    }
}
