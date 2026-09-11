<?php

declare(strict_types=1);

namespace App\Exceptions\Orders;

use App\Enums\PaymentStatus;
use DomainException;

/**
 * The order was not placed, and the reason is not the customer's fault.
 *
 * Every one of these means a captured or attempted payment exists whose
 * relationship to an order is unresolved. That is an operations problem, not a
 * "please try again" — the customer must never be told to pay a second time on
 * the strength of any of them.
 */
final class OrderCreationRefused extends DomainException
{
    private function __construct(
        public readonly string $reasonCode,
        string $message,
    ) {
        parent::__construct($message);
    }

    public static function paymentNotCaptured(PaymentStatus $status): self
    {
        return new self(
            'PAYMENT_NOT_CAPTURED',
            "An order may only be placed from a captured payment; this one is {$status->value}.",
        );
    }

    /**
     * The amounts are in the message because an operator resolving this needs
     * both numbers, and they are not a secret — the customer was shown one of
     * them at checkout and charged the other.
     */
    public static function amountMismatch(int $owed, int $captured): self
    {
        return new self(
            'PAYMENT_AMOUNT_MISMATCH',
            "The captured amount ({$captured}) does not match the order total ({$owed}).",
        );
    }

    public static function currencyMismatch(string $owed, string $captured): self
    {
        return new self(
            'PAYMENT_CURRENCY_MISMATCH',
            "The captured currency ({$captured}) does not match the order currency ({$owed}).",
        );
    }
}
