<?php

declare(strict_types=1);

namespace App\Services\Places;

/**
 * The boundary between this product and whoever knows where places are.
 *
 * Three operations, because those are the three questions the trip planner asks
 * and no more. Adding "nearby search" or "photos" here because a provider offers
 * them is how an interface becomes a vendor's SDK with extra steps.
 *
 * Implementations must throw {@see PlaceLookupException} rather than returning
 * an empty result when they *failed*: "no places match" and "the provider is
 * down" produce very different screens, and a caller cannot tell them apart from
 * an empty array.
 */
interface PlaceProvider
{
    /**
     * Autocomplete for a partial query.
     *
     * @param  string|null  $sessionToken  Groups the keystrokes of one search with the
     *                                     details call that ends it, so the provider bills
     *                                     them as a session rather than individually.
     * @return list<PlaceSuggestion>
     *
     * @throws PlaceLookupException
     */
    public function search(string $query, ?string $sessionToken = null): array;

    /**
     * Resolves one suggestion into something with a position.
     *
     * @throws PlaceLookupException
     */
    public function details(string $placeId, ?string $sessionToken = null): PlaceDetails;

    /**
     * Names a coordinate, for the current-location flow.
     *
     * Returns null when the provider has no name for the point. That is not a
     * failure: the coordinates are authoritative for a device fix, and "Current
     * location" is a perfectly good label to show over them.
     *
     * @throws PlaceLookupException
     */
    public function reverseGeocode(float $latitude, float $longitude): ?PlaceDetails;

    /** For diagnostics and the health of a deployment; never shown to a customer. */
    public function name(): string;
}
