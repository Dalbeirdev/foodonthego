<?php

declare(strict_types=1);

namespace App\Services\Payments;

/**
 * The provider's own order object, as this project cares about it.
 *
 * Four fields, not the provider's whole response. An interface that returned the
 * raw payload would let provider-shaped assumptions leak into services that have
 * no business knowing which provider is in use.
 */
final readonly class GatewayOrder
{
    public function __construct(
        public string $id,
        public int $amountMinor,
        public string $currency,
        public string $status,
    ) {}
}
