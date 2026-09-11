<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Money;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One option a customer chose on one cart line, and what it cost.
 */
final class CartItemModifier extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    /** @return BelongsTo<CartItem, $this> */
    public function cartItem(): BelongsTo
    {
        return $this->belongsTo(CartItem::class);
    }

    /** @return BelongsTo<MenuModifierGroup, $this> */
    public function group(): BelongsTo
    {
        return $this->belongsTo(MenuModifierGroup::class, 'menu_modifier_group_id');
    }

    /** @return BelongsTo<MenuModifierOption, $this> */
    public function option(): BelongsTo
    {
        return $this->belongsTo(MenuModifierOption::class, 'menu_modifier_option_id');
    }

    public function priceDelta(): ?Money
    {
        return Money::tryFromMinor($this->price_delta_minor, $this->currency);
    }

    /** @return array<string, mixed> */
    public function toCustomerArray(): array
    {
        return [
            'group_name' => $this->group_name_snapshot,
            'option_name' => $this->option_name_snapshot,
            'price_delta' => $this->priceDelta()?->toApiArray(),
        ];
    }
}
