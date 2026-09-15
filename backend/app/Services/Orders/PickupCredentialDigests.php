<?php

declare(strict_types=1);

namespace App\Services\Orders;

/**
 * What the database is allowed to hold: HMACs, never the credential itself.
 */
final readonly class PickupCredentialDigests
{
    public function __construct(
        public string $codeHash,
        public string $tokenHash,
    ) {}
}
