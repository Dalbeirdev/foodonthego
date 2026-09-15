<?php

declare(strict_types=1);

namespace App\Services\Otp;

use RuntimeException;

/**
 * The provider could not send.
 *
 * Thrown only when delivery **definitely** did not happen, because the caller
 * treats it as "do not tell the customer a code is on its way". A provider that
 * accepted the request and may yet deliver must not throw this.
 */
final class OtpDeliveryFailed extends RuntimeException
{
    public function __construct(
        public readonly string $provider,
        string $reason,
        public readonly ?string $providerCode = null,
    ) {
        parent::__construct($reason);
    }
}
