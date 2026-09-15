<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Money;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One size or form of a dish.
 *
 * The price is **absolute**: "Large ₹329" is what the dish costs, not what it
 * costs extra. See the migration for why.
 */
final class MenuItemVariant extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    protected static function booted(): void
    {
        self::creating(static function (self $variant): void {
            $variant->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<MenuItem, $this> */
    public function item(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class, 'menu_item_id');
    }

    /** @param Builder<self> $query */
    public function scopeVisible(Builder $query): void
    {
        $query->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /** The selling price, or null if the row cannot be trusted. */
    public function price(): ?Money
    {
        return Money::tryFromMinor($this->price_minor, $this->currency);
    }

    /**
     * Whether a customer may choose this one right now.
     *
     * Two conditions and not one: `is_active` is the operator having withdrawn
     * the size, `is_available` is the kitchen having run out of it today. An
     * inactive variant is not shown at all; an unavailable one is shown
     * disabled, so a customer who came for the large one learns why rather than
     * wondering whether they misremembered.
     */
    public function isSelectable(): bool
    {
        return (bool) $this->is_active && (bool) $this->is_available;
    }

    /** How long the kitchen says this size takes, if it said anything. */
    public function preparationMinutes(): ?int
    {
        $minutes = $this->preparation_minutes;

        if ($minutes === null) {
            return null;
        }

        $value = (int) $minutes;

        return ($value > 0 && $value <= 240) ? $value : null;
    }

    /**
     * What a customer is allowed to see.
     *
     * @return array<string, mixed>|null null when the price will not parse
     */
    public function toCustomerArray(): ?array
    {
        $price = $this->price();

        if ($price === null) {
            return null;
        }

        return [
            'id' => $this->uuid,
            'name' => $this->name,
            'description' => $this->customerDescription(),
            'price' => $price->toApiArray(),
            'preparation_minutes' => $this->preparationMinutes(),
            'is_default' => (bool) $this->is_default,
            'is_available' => (bool) $this->is_available,
        ];
    }

    private function customerDescription(): ?string
    {
        $description = trim((string) $this->description);

        return $description === '' ? null : $description;
    }
}
