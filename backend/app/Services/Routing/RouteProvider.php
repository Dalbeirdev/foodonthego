<?php

declare(strict_types=1);

namespace App\Services\Routing;

/**
 * Calculating a route.
 *
 * One method, because one thing is being asked. Alternatives are a property of
 * the request rather than a second method: "give me a route" and "give me a
 * route and its alternatives" are the same provider call with a different flag,
 * and splitting them would mean two adapters to keep in step.
 */
interface RouteProvider
{
    /**
     * @throws RouteProviderException when the provider fails or answers unusably.
     *                                An empty {@see RouteResult} is *not* a failure — it is the provider
     *                                saying there is no route, which is an answer.
     */
    public function calculate(RouteRequest $request): RouteResult;

    /** For logs and for the `provider` column. */
    public function name(): string;
}
