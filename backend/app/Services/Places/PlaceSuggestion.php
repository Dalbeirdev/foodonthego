<?php

declare(strict_types=1);

namespace App\Services\Places;

/**
 * One autocomplete result, in the app's own shape.
 *
 * Deliberately not the provider's JSON. A widget that reads
 * `structuredFormat.mainText.text` is a widget coupled to Google, and swapping
 * providers would then be a change to every screen rather than to one adapter.
 *
 * A suggestion carries no coordinates. Autocomplete answers "which place did you
 * mean"; {@see PlaceDetails} answers "where is it". Pretending otherwise is how
 * an app ends up routing to the centroid of a search term.
 */
final readonly class PlaceSuggestion
{
    public function __construct(
        public string $placeId,
        /** "Jaipur International Airport" */
        public string $primaryText,
        /** "Sanganer, Jaipur, Rajasthan" */
        public string $secondaryText,
    ) {}

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        return [
            'place_id' => $this->placeId,
            'primary_text' => $this->primaryText,
            'secondary_text' => $this->secondaryText,
        ];
    }
}
