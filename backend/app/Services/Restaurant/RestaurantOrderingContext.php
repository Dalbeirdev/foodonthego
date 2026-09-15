<?php

declare(strict_types=1);

namespace App\Services\Restaurant;

use App\Enums\RestaurantOrderingState;
use App\Services\Discovery\DiscoveredRestaurant;

/**
 * A restaurant a customer has been proved entitled to see, and whether it can
 * take an order right now.
 *
 * The eligibility half of {@see RestaurantDetail}, without the profile. The
 * menu screen needs exactly this and nothing else: it renders a name, an
 * ordering state and a list of dishes. Loading the photographs, cuisines,
 * facilities and a fortnight of opening hours to answer a menu request would be
 * four queries and a page of arithmetic thrown away, on the screen a customer
 * opens most often.
 */
final readonly class RestaurantOrderingContext
{
    public function __construct(
        public DiscoveredRestaurant $discovered,
        public RestaurantOrderingState $ordering,
    ) {}
}
