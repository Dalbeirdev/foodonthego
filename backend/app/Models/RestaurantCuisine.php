<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One declared cuisine. Stored as the operator wrote it, never inferred. */
final class RestaurantCuisine extends Model
{
    public $timestamps = false;

    /** @var list<string> */
    protected $fillable = ['cuisine', 'position'];

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }
}
