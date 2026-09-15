<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One facility the operator claims to offer.
 *
 * A claim rather than an observation, which is why it is stored and never
 * derived: a traveller choosing a stop because it says "Parking" is relying on
 * somebody having said so.
 */
final class RestaurantFacility extends Model
{
    public $timestamps = false;

    /** @var list<string> */
    protected $fillable = ['facility', 'position'];

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }
}
