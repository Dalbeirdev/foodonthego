<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Money;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One answer to a group's question.
 *
 * The price is a **delta** — what choosing it adds — and it is never negative.
 * See the migration.
 */
final class MenuModifierOption extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    protected static function booted(): void
    {
        self::creating(static function (self $option): void {
            $option->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<MenuModifierGroup, $this> */
    public function group(): BelongsTo
    {
        return $this->belongsTo(MenuModifierGroup::class, 'menu_modifier_group_id');
    }

    /** What choosing this adds, or null if the row cannot be trusted. */
    public function priceDelta(): ?Money
    {
        return Money::tryFromMinor($this->price_delta_minor, $this->currency);
    }

    public function isSelectable(): bool
    {
        return (bool) $this->is_active && (bool) $this->is_available;
    }

    public function isFree(): bool
    {
        return (int) $this->price_delta_minor === 0;
    }

    /**
     * Whether the screen should start with this one chosen.
     *
     * **A paid option is never a default**, whatever the column says. Starting
     * a customer at "Extra Cheese +₹40" and letting them discover it at the
     * total is a dark pattern, and this is the line that makes it one somebody
     * has to deliberately write rather than one they can configure by accident.
     */
    public function isDefault(): bool
    {
        return (bool) $this->is_default && $this->isFree() && $this->isSelectable();
    }

    /**
     * @return array<string, mixed>|null null when the delta will not parse
     */
    public function toCustomerArray(): ?array
    {
        $delta = $this->priceDelta();

        if ($delta === null) {
            return null;
        }

        return [
            'id' => $this->uuid,
            'name' => $this->name,
            'description' => $this->customerDescription(),
            'price_delta' => $delta->toApiArray(),
            'is_default' => $this->isDefault(),
            'is_available' => (bool) $this->is_available,
        ];
    }

    private function customerDescription(): ?string
    {
        $description = trim((string) $this->description);

        return $description === '' ? null : $description;
    }
}
