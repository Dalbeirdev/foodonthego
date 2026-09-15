<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Services\Places\PlaceDetails;
use App\Services\Places\PlaceLookupException;
use App\Services\Places\PlaceProvider;
use App\Services\Places\PlaceSuggestion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;

/**
 * Place search, resolution and reverse geocoding — mediated by this server.
 *
 * The app never talks to the place provider. The key stays here (see
 * `config/foodonthego.php`), the customer's own session gates every call, and
 * the provider can be swapped without an app release.
 *
 * Authenticated, deliberately. Place search is not a public service: an open
 * endpoint on a server holding a metered key is somebody else's free geocoder.
 */
final class PlaceController
{
    public function __construct(private readonly PlaceProvider $places) {}

    /**
     * Autocomplete.
     *
     * A short cache, keyed by the query and the region bias and never by the
     * customer, so a retyped search does not cost twice. It is *not* a history:
     * nothing customer-specific goes in, so nothing customer-specific can come
     * back out under another account.
     */
    public function search(Request $request): JsonResponse
    {
        $data = $this->validated($request, [
            'q' => ['required', 'string', 'min:2', 'max:120'],
            // Minted by the client when a search screen opens and sent again with
            // the details call, so the provider bills one session rather than one
            // request per keystroke.
            'session_token' => ['nullable', 'string', 'max:64'],
        ]);

        $query = trim((string) $data['q']);
        $token = $data['session_token'] ?? null;

        $cacheKey = 'places:search:'.hash('sha256', mb_strtolower($query));
        $ttl = (int) config('foodonthego.places.cache_seconds');

        /** @var list<array<string, mixed>> $results */
        $results = Cache::remember($cacheKey, $ttl, function () use ($query, $token): array {
            return array_map(
                static fn (PlaceSuggestion $s): array => $s->toApiArray(),
                $this->lookup(fn (): array => $this->places->search($query, $token)),
            );
        });

        return ApiResponse::ok($results);
    }

    /** Resolves one suggestion into something with a position. */
    public function show(Request $request, string $place): JsonResponse
    {
        $data = $this->validated($request, [
            'session_token' => ['nullable', 'string', 'max:64'],
        ]);

        $details = $this->lookup(
            fn (): PlaceDetails => $this->places->details($place, $data['session_token'] ?? null),
        );

        return ApiResponse::ok($details->toApiArray());
    }

    /**
     * Names a coordinate, for the current-location flow.
     *
     * A null answer is a success: the coordinates came from the device and are
     * authoritative, so a place with no name is still a perfectly usable starting
     * point labelled "Current location".
     */
    public function reverseGeocode(Request $request): JsonResponse
    {
        $data = $this->validated($request, [
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $details = $this->lookup(fn (): ?PlaceDetails => $this->places->reverseGeocode(
            (float) $data['latitude'],
            (float) $data['longitude'],
        ));

        return ApiResponse::ok($details?->toApiArray());
    }

    /**
     * Runs a provider call and converts its failures into the API contract.
     *
     * Nothing from the provider's message reaches the client: an upstream error
     * names our project, our key state and our quota.
     *
     * @template T
     *
     * @param  callable(): T  $call
     * @return T
     *
     * @throws ApiException
     */
    private function lookup(callable $call): mixed
    {
        try {
            return $call();
        } catch (PlaceLookupException) {
            // Logged here as well as in the adapter, because this is the layer
            // every provider passes through: a failure has to be visible in
            // operations whichever one is configured. No query text — what
            // somebody searched for is a statement about where they are going.
            Log::warning('places.lookup_failed', [
                'provider' => $this->places->name(),
            ]);

            throw new ApiException(
                ApiErrorCode::PlaceLookupFailed,
                'We could not load places right now.',
            );
        }
    }

    /**
     * @param  array<string, mixed>  $rules
     * @return array<string, mixed>
     *
     * @throws ApiException
     */
    private function validated(Request $request, array $rules): array
    {
        $validator = Validator::make($request->all(), $rules);

        if ($validator->fails()) {
            throw new ApiException(
                ApiErrorCode::ValidationFailed,
                'That search could not be understood.',
                ['fields' => $validator->errors()->toArray()],
            );
        }

        return $validator->validated();
    }
}
