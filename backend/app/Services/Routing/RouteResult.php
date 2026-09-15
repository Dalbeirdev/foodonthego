<?php

declare(strict_types=1);

namespace App\Services\Routing;

/**
 * Everything a provider returned for one request.
 *
 * An empty list is a legitimate, successful answer: the provider looked and
 * there is no driving route between these two places. That is a different thing
 * from a failure, and the two get different statuses, different messages and
 * different buttons — so they get different types here rather than an empty
 * array and a flag.
 */
final readonly class RouteResult
{
    /** @param list<RouteOption> $options */
    public function __construct(
        public array $options,
        public string $provider,
    ) {}

    public function isEmpty(): bool
    {
        return $this->options === [];
    }
}
