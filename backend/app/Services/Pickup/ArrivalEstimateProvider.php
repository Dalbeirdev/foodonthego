<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Models\Restaurant;
use App\Models\Trip;
use Carbon\CarbonImmutable;

/**
 * Where an arrival time comes from.
 *
 * **This interface is the ETA boundary**, and it exists so the boundary is a
 * seam in the code rather than a paragraph in a document.
 *
 * Module 13 ships one implementation, which reads the planned route and assumes
 * the customer sets off now. A later module will ship a second that reads live
 * GPS progress, refreshed traffic and actual position. Pickup planning consumes
 * this interface and nothing else, so that swap changes one binding and no
 * arithmetic.
 *
 * Returning null is a legitimate answer: no usable route, no position on it, no
 * estimate. The planner refuses to invent windows rather than guessing.
 */
interface ArrivalEstimateProvider
{
    public function estimate(
        Trip $trip,
        Restaurant $restaurant,
        CarbonImmutable $now,
    ): ?ArrivalEstimate;
}
