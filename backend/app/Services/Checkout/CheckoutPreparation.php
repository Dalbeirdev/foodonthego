<?php

declare(strict_types=1);

namespace App\Services\Checkout;

use App\Enums\CheckoutQuoteStatus;
use App\Models\CheckoutQuote;
use App\Services\Pickup\PreCheckoutValidation;

/**
 * The answer to "may this be paid for, and for how much".
 *
 * Carries the quote **and** the validation that produced it, because a refusal
 * with the reasons attached is something a screen can act on and a bare error
 * is something a customer has to guess at.
 *
 * `readyForPayment` is computed here from the server's own state and is not a
 * field any request can carry. A client renders it; it must never derive one.
 */
final readonly class CheckoutPreparation
{
    public function __construct(
        public ?CheckoutQuote $quote,
        public CheckoutQuoteStatus $status,
        public PreCheckoutValidation $validation,
        public CommercialBreakdown $breakdown,
    ) {}

    public function readyForPayment(): bool
    {
        return $this->quote !== null
            && $this->status->isUsable()
            && $this->validation->readyForCheckout();
    }
}
