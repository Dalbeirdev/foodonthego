<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Money;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

/**
 * One configured dish in a cart.
 *
 * Every price on this row was calculated by the server from rows it read
 * itself. Nothing in a request body reaches these columns.
 */
final class CartItem extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    protected static function booted(): void
    {
        self::creating(static function (self $item): void {
            $item->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<Cart, $this> */
    public function cart(): BelongsTo
    {
        return $this->belongsTo(Cart::class);
    }

    /** @return BelongsTo<MenuItem, $this> */
    public function menuItem(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class, 'menu_item_id');
    }

    /** @return BelongsTo<MenuItemVariant, $this> */
    public function variant(): BelongsTo
    {
        return $this->belongsTo(MenuItemVariant::class, 'menu_item_variant_id');
    }

    /** @return HasMany<CartItemModifier, $this> */
    public function modifiers(): HasMany
    {
        return $this->hasMany(CartItemModifier::class)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    public function unitPrice(): ?Money
    {
        return Money::tryFromMinor($this->unit_price_minor, $this->currency);
    }

    public function lineTotal(): ?Money
    {
        return Money::tryFromMinor($this->line_total_minor, $this->currency);
    }

    /**
     * What the customer sees on this line.
     *
     * The names are the snapshots, not the live rows: a restaurant that renames
     * a dish tomorrow must not rewrite what a customer chose today.
     *
     * @return array<string, mixed>
     */
    public function toCustomerArray(): array
    {
        $unit = $this->unitPrice();
        $total = $this->lineTotal();

        return [
            'id' => $this->uuid,
            'item_id' => $this->menuItem?->uuid,
            'name' => $this->item_name_snapshot,
            'variant_name' => $this->variant_name_snapshot,
            'quantity' => (int) $this->quantity,
            'unit_price' => $unit?->toApiArray(),
            'line_total' => $total?->toApiArray(),
            'special_instructions' => $this->special_instructions,
            'modifiers' => $this->modifiers
                ->map(static fn (CartItemModifier $m): array => $m->toCustomerArray())
                ->all(),
        ];
    }
}
