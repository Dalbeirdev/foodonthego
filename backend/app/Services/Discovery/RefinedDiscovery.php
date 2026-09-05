<?php

declare(strict_types=1);

namespace App\Services\Discovery;

/**
 * One page of a filtered discovery, and enough context to explain it.
 *
 * The two counts are the point. `total` is how many restaurants match what the
 * customer asked for; `eligibleTotal` is how many are on this route at all. An
 * empty screen with `eligibleTotal = 0` means "there is nothing on this road
 * yet"; an empty screen with `eligibleTotal = 6` means "your filters removed
 * everything", and those need different words and different buttons.
 */
final readonly class RefinedDiscovery
{
    /** @param list<DiscoveredRestaurant> $restaurants */
    public function __construct(
        public DiscoveryResult $discovery,
        public DiscoveryQuery $query,
        public array $restaurants,
        public int $total,
        public int $eligibleTotal,
        /** @var array<string, mixed> */
        public array $facets,
    ) {}

    public function hasMore(): bool
    {
        return $this->query->page * $this->query->perPage < $this->total;
    }

    public function lastPage(): int
    {
        return max(1, (int) ceil($this->total / $this->query->perPage));
    }

    /** Restaurants exist on this route; the filters removed all of them. */
    public function isFilteredEmpty(): bool
    {
        return $this->total === 0 && $this->eligibleTotal > 0 && $this->query->isRefined();
    }

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        $base = $this->discovery->toApiArray();

        return [
            'route' => $base['route'],
            'restaurants' => array_map(
                static fn (DiscoveredRestaurant $d): array => $d->toApiArray(),
                $this->restaurants,
            ),
            'meta' => [
                ...$base['meta'],

                // What this page is.
                'returned' => count($this->restaurants),
                'total' => $this->total,
                'page' => $this->query->page,
                'per_page' => $this->query->perPage,
                'last_page' => $this->lastPage(),
                'has_more' => $this->hasMore(),

                // How many were on the route before the customer refined it, so
                // an empty screen can tell the two empty states apart.
                'eligible_total' => $this->eligibleTotal,
                'filtered_empty' => $this->isFilteredEmpty(),

                // The query as the server understood it. A client that sent
                // `facilities=restroom,parking` gets back `[parking, restroom]`
                // and can see its own request normalised — which is the fastest
                // way to notice a parameter that was silently dropped.
                'applied' => $this->query->toApiArray(),
            ],

            // The options worth offering for *this* route, with counts.
            'filters' => $this->facets,
        ];
    }
}
