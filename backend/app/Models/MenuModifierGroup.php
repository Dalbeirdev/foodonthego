<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

/**
 * A question the kitchen asks about a dish.
 *
 * Add-ons are these too — "Add extras · Optional · choose up to 3" — because a
 * second model doing the same job would mean a second validator, a second
 * pricing path and a second snapshot table to keep in step.
 */
final class MenuModifierGroup extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    protected static function booted(): void
    {
        self::creating(static function (self $group): void {
            $group->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /**
     * The options a customer may see, in the operator's order.
     *
     * Scoped on the relation itself, so a query that forgets the scope still
     * cannot reach a withdrawn option.
     *
     * @return HasMany<MenuModifierOption, $this>
     */
    public function options(): HasMany
    {
        return $this->hasMany(MenuModifierOption::class)
            ->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /** @return HasMany<MenuModifierOption, $this> */
    public function allOptions(): HasMany
    {
        return $this->hasMany(MenuModifierOption::class);
    }

    /** @param Builder<self> $query */
    public function scopeVisible(Builder $query): void
    {
        $query->where('is_active', true);
    }

    public function minSelect(): int
    {
        return (int) $this->min_select;
    }

    /**
     * The most a customer may choose here.
     *
     * Never below the minimum: a group configured `min=2 max=1` is
     * unsatisfiable, and rather than refuse every add-to-cart on that dish the
     * ceiling is raised to meet the floor. The alternative is a screen nobody
     * can get past because of a typo in an operator dashboard.
     */
    public function maxSelect(): int
    {
        return max((int) $this->max_select, $this->minSelect());
    }

    public function isRequired(): bool
    {
        // Derived rather than trusted. The column exists for querying, and a
        // row where the two disagree should behave the way the numbers say.
        return $this->minSelect() >= 1;
    }

    /** A single choice — drawn as radios rather than checkboxes. */
    public function isSingleSelect(): bool
    {
        return $this->maxSelect() === 1;
    }

    /**
     * What a customer is allowed to see.
     *
     * The rules are on the wire as numbers as well as prose, so the client can
     * enforce them without parsing English — and so a future locale does not
     * have to translate a rule to make it work.
     *
     * @return array<string, mixed>
     */
    public function toCustomerArray(): array
    {
        $options = [];

        foreach ($this->options as $option) {
            $rendered = $option->toCustomerArray();

            if ($rendered !== null) {
                $options[] = $rendered;
            }
        }

        return [
            'id' => $this->uuid,
            'name' => $this->name,
            'description' => $this->customerDescription(),
            'min_select' => $this->minSelect(),
            'max_select' => $this->maxSelect(),
            'is_required' => $this->isRequired(),
            'is_single_select' => $this->isSingleSelect(),
            'options' => $options,
        ];
    }

    private function customerDescription(): ?string
    {
        $description = trim((string) $this->description);

        return $description === '' ? null : $description;
    }
}
