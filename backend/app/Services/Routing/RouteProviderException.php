<?php

declare(strict_types=1);

namespace App\Services\Routing;

/**
 * A routing provider failed.
 *
 * [kind] is what the caller branches on, because the customer's next move
 * differs for each: retry, wait, or nothing they can do. The message is for the
 * log — a provider's own words name our project, our key state and our quota,
 * and none of that reaches a client.
 */
final class RouteProviderException extends \RuntimeException
{
    public function __construct(
        public readonly RouteFailureKind $kind,
        string $message,
    ) {
        parent::__construct($message);
    }
}
