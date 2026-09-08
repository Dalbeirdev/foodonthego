<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\MenuItemDietaryType;
use App\Enums\MenuItemStockStatus;
use App\Models\Concerns\BelongsToTenant;
use App\Support\Money;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

/**
 * One thing a customer can order.
 *
 * The customer projection is an **allow-list**, like the restaurant's. There
 * are no cost prices, margins, suppliers or internal stock counts in this
 * schema yet, and when an operator dashboard adds them the projection below is
 * what keeps them off a customer's screen — a new column is invisible until
 * somebody names it here.
 */
final class MenuItem extends Model
{
    use BelongsToTenant;

    /** @var list<string> */
    protected $fillable = [];

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /** @return BelongsTo<MenuCategory, $this> */
    public function category(): BelongsTo
    {
        return $this->belongsTo(MenuCategory::class, 'menu_category_id');
    }

    /**
     * The sizes a customer may see, in the operator's order.
     *
     * Scoped on the relation, so a query that forgets the scope still cannot
     * offer a withdrawn size. Unavailable ones *are* included — they are shown
     * disabled, which is information, where hiding them is a customer
     * wondering whether they misremembered the menu.
     *
     * @return HasMany<MenuItemVariant, $this>
     */
    public function variants(): HasMany
    {
        return $this->hasMany(MenuItemVariant::class)
            ->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /** @return HasMany<MenuItemVariant, $this> */
    public function allVariants(): HasMany
    {
        return $this->hasMany(MenuItemVariant::class);
    }

    /**
     * The questions asked about this dish.
     *
     * @return BelongsToMany<MenuModifierGroup, $this>
     */
    public function modifierGroups(): BelongsToMany
    {
        return $this->belongsToMany(
            MenuModifierGroup::class,
            'menu_item_modifier_group',
            'menu_item_id',
            'menu_modifier_group_id',
        )
            ->where('menu_modifier_groups.is_active', true)
            ->withPivot('display_order')
            ->orderBy('menu_item_modifier_group.display_order')
            ->orderBy('menu_modifier_groups.id');
    }

    /**
     * The size a customer starts on, or null.
     *
     * Never "the first row": a default is something an operator configured, and
     * guessing one means a customer is quoted a price nobody chose to show
     * them. A dish whose configured default has since gone unavailable has no
     * default, and the screen asks.
     */
    public function defaultVariant(): ?MenuItemVariant
    {
        foreach ($this->variants as $variant) {
            if ($variant->is_default && $variant->isSelectable()) {
                return $variant;
            }
        }

        return null;
    }

    /** True when the customer must choose a size before ordering. */
    public function requiresVariantChoice(): bool
    {
        $selectable = $this->variants->filter(
            static fn (MenuItemVariant $v): bool => $v->isSelectable(),
        );

        if ($selectable->isEmpty()) {
            return false;
        }

        return $this->defaultVariant() === null;
    }

    /** @param Builder<self> $query */
    public function scopeVisible(Builder $query): void
    {
        $query->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /**
     * The price, or null if the row cannot be trusted.
     *
     * Null is the answer for a corrupt record, and the caller omits the item
     * rather than rendering a price nobody can defend. One bad row must not
     * take a whole menu down, and it must not become "₹0" either.
     */
    public function price(): ?Money
    {
        return Money::tryFromMinor($this->base_price_minor, $this->currency);
    }

    public function stockStatus(): MenuItemStockStatus
    {
        return MenuItemStockStatus::tryFrom((string) $this->stock_status)
            // A status this build has never heard of is not permission to sell.
            ?? MenuItemStockStatus::SoldOut;
    }

    public function dietaryType(): ?MenuItemDietaryType
    {
        return MenuItemDietaryType::tryFromValue($this->dietary_type);
    }

    /**
     * Item-level preparation metadata, or null.
     *
     * **Not** a pickup ETA, and deliberately not filled in from the
     * restaurant's `default_preparation_minutes`: that is a restaurant-wide
     * figure, and copying it onto a dish turns a general guess into a specific
     * claim. A negative or absurd stored value is treated as absent rather than
     * shown — the customer path never has to defend against nonsense it can
     * simply decline to repeat.
     */
    public function preparationMinutes(): ?int
    {
        $minutes = $this->preparation_minutes;

        if ($minutes === null) {
            return null;
        }

        $minutes = (int) $minutes;

        return $minutes > 0 && $minutes <= 240 ? $minutes : null;
    }

    /** Empty is absent. A description block with nothing in it is not a block. */
    public function customerDescription(): ?string
    {
        $description = trim((string) $this->description);

        return $description === '' ? null : $description;
    }

    /**
     * What a customer is allowed to see.
     *
     * An allow-list, named field by field. Returns null when the item cannot be
     * rendered honestly — today that means only a price that will not parse.
     *
     * The category is passed in rather than read off the relation. Items arrive
     * here through `$category->items`, so the inverse relation is not loaded and
     * reading it would be one query per item — the N+1 this endpoint is built to
     * avoid. Requiring the argument makes that mistake impossible rather than
     * merely unlikely.
     *
     * @return array<string, mixed>|null
     */
    public function toCustomerArray(MenuCategory $category): ?array
    {
        $price = $this->price();

        if ($price === null) {
            return null;
        }

        return [
            'id' => $this->uuid,
            'category_id' => $category->uuid,
            'name' => $this->name,
            'description' => $this->customerDescription(),

            // The amount and its currency, never a rendered string: what a
            // price looks like is a locale decision and the server does not
            // know the customer's.
            'price' => $price->toApiArray(),

            'image_url' => $this->image_url,
            // Falls back to the full image rather than to null: a client that
            // asked for a thumbnail and got nothing renders a hole.
            'thumbnail_url' => $this->thumbnail_url ?: $this->image_url,

            'preparation_minutes' => $this->preparationMinutes(),
            'dietary_type' => $this->dietaryType()?->value,
            'spice_level' => $this->spice_level === null ? null : (int) $this->spice_level,

            'stock_status' => $this->stockStatus()->value,
            'is_orderable' => $this->stockStatus()->isOrderable(),
        ];
    }

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'base_price_minor' => 'integer',
            'display_order' => 'integer',
        ];
    }

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
}
