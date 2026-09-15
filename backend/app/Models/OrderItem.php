<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

/**
 * One dish on an order, as it was, at the price it was.
 *
 * The `*_snapshot` columns are the authority. `menuItem()` exists for
 * provenance and may be null once the menu row is gone; nothing renders a
 * receipt through it.
 */
final class OrderItem extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'unit_price_minor' => 'integer',
            'line_total_minor' => 'integer',
            'quantity' => 'integer',
            'display_order' => 'integer',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $item): void {
            $item->uuid ??= (string) Str::uuid();
        });
    }

    /** @return BelongsTo<Order, $this> */
    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    /** @return BelongsTo<MenuItem, $this> */
    public function menuItem(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class);
    }

    /** @return HasMany<OrderItemModifier, $this> */
    public function modifiers(): HasMany
    {
        return $this->hasMany(OrderItemModifier::class)->orderBy('display_order')->orderBy('id');
    }
}
