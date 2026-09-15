<?php

declare(strict_types=1);

namespace App\Models;

use App\Services\Discovery\RestaurantAvailabilityService;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One opening window, in the restaurant's own local time.
 *
 * `day_of_week` is 0 for Monday through 6 for Sunday. A window whose close is
 * not after its open runs past midnight — 18:00 to 02:00 — and
 * {@see RestaurantAvailabilityService} treats it as one
 * rather than discarding it as bad data.
 */
final class RestaurantOpeningHour extends Model
{
    public $timestamps = false;

    /** @var list<string> */
    protected $fillable = ['day_of_week', 'opens_at', 'closes_at'];

    protected function casts(): array
    {
        return ['day_of_week' => 'integer'];
    }

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /** Whether this window runs past midnight into the following day. */
    public function isOvernight(): bool
    {
        return $this->closes_at <= $this->opens_at;
    }
}
