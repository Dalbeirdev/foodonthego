<?php

declare(strict_types=1);

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

/**
 * One section of a restaurant's menu.
 *
 * `$fillable` is empty, like every other model in this schema. Categories will
 * arrive from an operator dashboard a later module builds, and that dashboard
 * will assign what it is allowed to assign by name.
 */
final class MenuCategory extends Model
{
    use BelongsToTenant;

    /** @var list<string> */
    protected $fillable = [];

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /**
     * The items a customer may see, in the operator's order.
     *
     * Scoped at the relation. A query that forgets `->visible()` still cannot
     * reach a withdrawn item, which is the direction a forgotten line should
     * fall.
     *
     * @return HasMany<MenuItem, $this>
     */
    public function items(): HasMany
    {
        return $this->hasMany(MenuItem::class)
            ->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /** Every item, withdrawn ones included. For the operator side, later. */
    public function allItems(): HasMany
    {
        return $this->hasMany(MenuItem::class);
    }

    /** @param Builder<self> $query */
    public function scopeVisible(Builder $query): void
    {
        $query->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /**
     * Whether this category is being served at a given local time.
     *
     * A category with no window is served all day, which is almost all of them.
     * A window that wraps midnight — supper from 22:00 to 02:00 — is handled
     * the same way opening hours are, because a menu section that vanished at
     * midnight would be a bug a night driver found first.
     */
    public function isServedAt(string $localTime): bool
    {
        $from = $this->available_from;
        $until = $this->available_until;

        if ($from === null || $until === null) {
            return true;
        }

        $from = substr((string) $from, 0, 8);
        $until = substr((string) $until, 0, 8);
        $now = substr($localTime, 0, 8);

        return $from <= $until
            ? $now >= $from && $now < $until
            : $now >= $from || $now < $until;
    }

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'display_order' => 'integer',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $category): void {
            $category->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }
}
