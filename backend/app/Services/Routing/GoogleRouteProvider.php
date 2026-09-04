<?php

declare(strict_types=1);

namespace App\Services\Routing;

use App\Support\Route\PolylineCodec;
use App\Support\Route\PolylineException;
use Carbon\CarbonImmutable;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Log;

/**
 * Google Routes API (v2) — `computeRoutes`.
 *
 * The current API rather than the legacy Directions API, which is in its
 * deprecation window. Routes v2 is also the one that separates traffic-aware
 * duration from static duration explicitly, and this module depends on that
 * distinction being made by the provider rather than guessed at here.
 *
 * ### The two durations
 * With `routingPreference: TRAFFIC_AWARE`, `duration` is the traffic-aware
 * estimate and `staticDuration` is the same route with no traffic model at all.
 * They map to `trafficDurationSeconds` and `durationSeconds` respectively — that
 * way round. Reading `duration` as the base figure would make every route look
 * as though traffic were costing exactly nothing.
 *
 * With `TRAFFIC_UNAWARE` there is no traffic estimate, so
 * `trafficDurationSeconds` is null rather than a copy of the other one.
 *
 * ### The key
 * Sent in `X-Goog-Api-Key`, never in the query string: a key in a URL reaches
 * access logs, proxy logs and referrer headers. This is a **server** key,
 * IP-restricted, and it never leaves the backend.
 */
final class GoogleRouteProvider implements RouteProvider
{
    private const URL = 'https://routes.googleapis.com/directions/v2:computeRoutes';

    /**
     * Exactly the fields this application reads.
     *
     * Not a convenience: Routes v2 bills by the field mask, and the difference
     * between asking for these six and asking for everything is a different SKU
     * on the invoice. Adding a field here is a costed decision.
     */
    private const FIELD_MASK = 'routes.distanceMeters,routes.duration,routes.staticDuration,'
        .'routes.polyline.encodedPolyline,routes.description,routes.viewport';

    public function __construct(
        private readonly HttpFactory $http,
        private readonly string $apiKey,
        private readonly int $timeoutSeconds,
        private readonly int $maxAlternatives,
        private readonly string $languageCode,
    ) {}

    public function name(): string
    {
        return 'google';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        $payload = $this->payload($request);

        try {
            $response = $this->http
                ->timeout($this->timeoutSeconds)
                ->withHeaders([
                    'X-Goog-Api-Key' => $this->apiKey,
                    'X-Goog-FieldMask' => self::FIELD_MASK,
                    'Content-Type' => 'application/json',
                ])
                ->post(self::URL, $payload);
        } catch (ConnectionException $e) {
            // Covers both a refused connection and a client-side timeout; the
            // message distinguishes them for the log and neither reaches a
            // customer as prose.
            throw new RouteProviderException(
                str_contains(strtolower($e->getMessage()), 'timed out')
                    ? RouteFailureKind::Timeout
                    : RouteFailureKind::Unavailable,
                'Google Routes transport failure: '.$e->getMessage(),
            );
        }

        $this->assertAcceptable($response);

        return $this->read($response);
    }

    /** @return array<string, mixed> */
    private function payload(RouteRequest $request): array
    {
        $payload = [
            'origin' => $this->waypoint($request->originLatitude, $request->originLongitude),
            'destination' => $this->waypoint($request->destinationLatitude, $request->destinationLongitude),
            'travelMode' => $request->travelMode,
            'computeAlternativeRoutes' => $request->withAlternatives,
            // OVERVIEW rather than HIGH_QUALITY: this geometry draws a national
            // route on a phone and seeds a corridor search. Street-level fidelity
            // would be a much larger payload for a line nobody can see at that
            // zoom.
            'polylineQuality' => 'OVERVIEW',
            'polylineEncoding' => 'ENCODED_POLYLINE',
            'languageCode' => $this->languageCode,
            'units' => 'METRIC',
            // No avoid-tolls, avoid-highways or avoid-ferries. Forcing any of
            // them would silently give every customer a worse route than the one
            // they would have chosen; they belong to a preferences screen that
            // does not exist yet.
        ];

        if ($request->trafficAware) {
            $payload['routingPreference'] = 'TRAFFIC_AWARE';
            // Anchors the traffic model. Google requires this to be now or later,
            // so a route planned now asks about now.
            $payload['departureTime'] = ($request->departureTime ?? CarbonImmutable::now())
                ->toIso8601ZuluString();
        } else {
            $payload['routingPreference'] = 'TRAFFIC_UNAWARE';
        }

        return $payload;
    }

    /** @return array<string, mixed> */
    private function waypoint(float $latitude, float $longitude): array
    {
        return ['location' => ['latLng' => [
            'latitude' => $latitude,
            'longitude' => $longitude,
        ]]];
    }

    private function assertAcceptable(Response $response): void
    {
        if ($response->successful()) {
            return;
        }

        $status = $response->status();

        $kind = match (true) {
            $status === 429 => RouteFailureKind::RateLimited,
            $status === 401 || $status === 403 => RouteFailureKind::NotAuthorised,
            $status >= 500 => RouteFailureKind::Unavailable,
            default => RouteFailureKind::InvalidResponse,
        };

        // The provider's own message names our project, our key state and our
        // quota. It goes here, against the request id, and no further.
        Log::warning('route.provider_rejected', [
            'provider' => $this->name(),
            'status' => $status,
            'kind' => $kind->value,
        ]);

        throw new RouteProviderException($kind, "Google Routes returned HTTP {$status}.");
    }

    private function read(Response $response): RouteResult
    {
        try {
            $body = $response->json();
        } catch (\Throwable) {
            throw new RouteProviderException(
                RouteFailureKind::InvalidResponse,
                'Google Routes returned a body that is not JSON.',
            );
        }

        if (! is_array($body)) {
            throw new RouteProviderException(
                RouteFailureKind::InvalidResponse,
                'Google Routes returned a body that is not an object.',
            );
        }

        // No `routes` key at all is how Routes v2 says "there is no route
        // between these places". That is an answer, not a fault, and it travels
        // as an empty result rather than as an exception.
        $routes = $body['routes'] ?? [];

        if (! is_array($routes)) {
            throw new RouteProviderException(
                RouteFailureKind::InvalidResponse,
                'Google Routes returned a non-array `routes`.',
            );
        }

        $options = [];
        $index = 0;

        foreach ($routes as $route) {
            if (! is_array($route)) {
                continue;
            }

            $option = $this->option($route, $index);

            // A single unusable alternative does not sink the whole answer —
            // provided at least one route survives, which the caller checks.
            if ($option !== null) {
                $options[] = $option;
                $index++;
            }

            if ($index >= $this->maxAlternatives) {
                break;
            }
        }

        return new RouteResult($options, $this->name());
    }

    /** @param array<string, mixed> $route */
    private function option(array $route, int $index): ?RouteOption
    {
        $encoded = $route['polyline']['encodedPolyline'] ?? null;
        $distance = $route['distanceMeters'] ?? null;

        if (! is_string($encoded) || $encoded === '' || ! is_int($distance)) {
            return null;
        }

        $duration = self::seconds($route['staticDuration'] ?? null);
        $trafficDuration = self::seconds($route['duration'] ?? null);

        // `staticDuration` is absent under TRAFFIC_UNAWARE, where `duration` is
        // itself the traffic-free figure. Falling back keeps the base duration
        // populated without ever inventing one.
        if ($duration === null) {
            $duration = $trafficDuration;
            $trafficDuration = null;
        }

        if ($duration === null) {
            return null;
        }

        try {
            $points = PolylineCodec::decode($encoded);
        } catch (PolylineException) {
            return null;
        }

        return new RouteOption(
            index: $index,
            distanceMeters: $distance,
            durationSeconds: $duration,
            // Only when it is genuinely a different figure. Google returns the
            // two identically under some conditions, and reporting "traffic is
            // adding zero seconds" is a claim about the roads we cannot support.
            trafficDurationSeconds: $trafficDuration !== null && $trafficDuration !== $duration
                ? $trafficDuration
                : null,
            encodedPolyline: $encoded,
            bounds: $this->bounds($route, $points),
            summary: self::text($route['description'] ?? null),
        );
    }

    /**
     * The provider's viewport when it sent one, and the geometry's own box when
     * it did not.
     *
     * @param  array<string, mixed>  $route
     * @param  list<array{0: float, 1: float}>  $points
     */
    private function bounds(array $route, array $points): RouteBounds
    {
        $viewport = $route['viewport'] ?? null;

        if (is_array($viewport)
            && isset($viewport['high']['latitude'], $viewport['high']['longitude'])
            && isset($viewport['low']['latitude'], $viewport['low']['longitude'])
        ) {
            $bounds = new RouteBounds(
                north: (float) $viewport['high']['latitude'],
                south: (float) $viewport['low']['latitude'],
                east: (float) $viewport['high']['longitude'],
                west: (float) $viewport['low']['longitude'],
            );

            if ($bounds->isSane()) {
                return $bounds;
            }
        }

        return RouteBounds::around($points);
    }

    /** Routes v2 sends durations as `"16200s"`. */
    private static function seconds(mixed $value): ?int
    {
        if (! is_string($value) || ! preg_match('/^(\d+(?:\.\d+)?)s$/', $value, $matches)) {
            return null;
        }

        return (int) round((float) $matches[1]);
    }

    private static function text(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : mb_substr($trimmed, 0, 180);
    }
}
