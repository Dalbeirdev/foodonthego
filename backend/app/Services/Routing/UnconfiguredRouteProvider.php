<?php

declare(strict_types=1);

namespace App\Services\Routing;

use App\Support\ProductionConfigGuard;
use Illuminate\Support\Facades\Log;

/**
 * The default, and the reason a misconfigured deployment cannot show a customer
 * a route it invented.
 *
 * It refuses every call, loudly, and {@see ProductionConfigGuard}
 * refuses to boot a production application that resolves to it. Between them
 * there is no arrangement of environment variables in which this product draws a
 * route without a real routing provider behind it.
 */
final class UnconfiguredRouteProvider implements RouteProvider
{
    public function name(): string
    {
        return 'unconfigured';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        Log::error('route.provider_unconfigured', [
            'hint' => 'Set ROUTE_PROVIDER and GOOGLE_ROUTES_API_KEY.',
        ]);

        throw new RouteProviderException(
            RouteFailureKind::NotAuthorised,
            'No routing provider is configured. Set ROUTE_PROVIDER and GOOGLE_ROUTES_API_KEY.',
        );
    }
}
