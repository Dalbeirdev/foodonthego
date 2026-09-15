<?php

declare(strict_types=1);

namespace App\Services\Otp;

/**
 * What a provider gives back. Deliberately narrow: a reference for support to
 * quote, and nothing that could carry the code itself.
 */
final readonly class OtpDeliveryReceipt
{
    public function __construct(
        public string $provider,
        public ?string $providerReference = null,
    ) {}
}
