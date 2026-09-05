<?php

declare(strict_types=1);

namespace App\Services\Restaurant;

use App\Enums\RestaurantOrderingState;
use App\Services\Discovery\DiscoveredRestaurant;
use Carbon\CarbonImmutable;

/**
 * One restaurant, as a customer travelling a particular route sees it.
 *
 * Two halves, deliberately assembled from two different places.
 *
 * The **profile** — name, description, photographs, cuisines, facilities,
 * hours — comes from the restaurant row. It changes when an operator edits it,
 * which is rarely.
 *
 * The **route context** — how far ahead, what the detour costs — comes from the
 * discovery result Module 07 already computed and cached. It is not
 * recalculated here, and opening this screen calls no routing provider. That is
 * the module's cost guarantee and it is structural: this class receives a
 * {@see DiscoveredRestaurant} and has no way to ask a provider anything.
 */
final readonly class RestaurantDetail
{
    /**
     * @param  array<string, mixed>  $todayHours
     * @param  list<array<string, mixed>>  $weeklyHours
     * @param  array<string, mixed>|null  $currentWindow
     */
    public function __construct(
        public DiscoveredRestaurant $discovered,
        public RestaurantOrderingState $ordering,
        public array $todayHours,
        public array $weeklyHours,
        public ?array $currentWindow,
        public ?CarbonImmutable $nextOpenAt,
        public string $timezone,
        public CarbonImmutable $generatedAt,
        public bool $routeFromCache,
    ) {}

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        $restaurant = $this->discovered->restaurant;

        // The discovery projection is reused verbatim rather than rebuilt, so a
        // card and this screen cannot disagree about a detour. Everything the
        // detail screen adds is layered on top of it.
        $base = $this->discovered->toApiArray();

        return [
            ...$base,

            // --- profile ------------------------------------------------------
            'description' => $this->text($restaurant->description),
            'public_phone' => $this->text($restaurant->public_phone),
            'media' => $restaurant->media
                ->map(static fn ($image): array => $image->toCustomerArray())
                ->values()
                ->all(),

            // --- can I order ---------------------------------------------------
            // `availability` is already in $base and keeps Module 07's meaning.
            // This is the derived rollup, and the two are different questions.
            'ordering' => [
                'state' => $this->ordering->value,
                'can_order' => $this->ordering->canOrder(),
                'can_browse_menu' => $this->ordering->permitsBrowsing(),
            ],

            // --- when are you open ---------------------------------------------
            'hours' => [
                'timezone' => $this->timezone,
                'today' => $this->todayHours,
                'week' => $this->weeklyHours,
                'current_window' => $this->currentWindow,
                // An instant, not a wall clock: the client formats it in the
                // restaurant's zone and never has to guess which day it means.
                'next_open_at' => $this->nextOpenAt?->utc()->toIso8601String(),
            ],

            // --- freshness ------------------------------------------------------
            // So an offline screen can say how old what it is showing is,
            // rather than implying the open sign is live.
            'generated_at' => $this->generatedAt->utc()->toIso8601String(),
            'route_from_cache' => $this->routeFromCache,
        ];
    }

    /** Empty is absent. A section with nothing in it is not a section. */
    private function text(?string $value): ?string
    {
        $trimmed = trim((string) $value);

        return $trimmed === '' ? null : $trimmed;
    }
}
