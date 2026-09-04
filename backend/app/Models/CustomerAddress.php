<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\AddressType;
use App\Services\Address\CustomerAddressService;
use Database\Factories\CustomerAddressFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * A place a customer has saved.
 *
 * Note what is *not* fillable: `customer_id`, `uuid`, `is_default`. Ownership
 * comes from the authenticated actor, the uuid is assigned here, and the default
 * flag is only ever changed through {@see CustomerAddressService},
 * which holds the lock that keeps one default per customer. A request body can
 * carry any of those three names and none of them will land.
 */
final class CustomerAddress extends Model
{
    /** @use HasFactory<CustomerAddressFactory> */
    use HasFactory;

    protected $fillable = [
        'type', 'label',
        'address_line_1', 'address_line_2', 'landmark',
        'city', 'state', 'postal_code', 'country_code',
        'formatted_address', 'latitude', 'longitude', 'place_id',
    ];

    /**
     * `default_for_customer` is a generated column — the database computes it and
     * rejects a write to it. Hidden so it never reaches a response, where it would
     * be a raw customer id.
     */
    protected $hidden = ['default_for_customer'];

    protected function casts(): array
    {
        return [
            'type' => AddressType::class,
            'is_default' => 'boolean',
            // Strings, not floats. A coordinate that round-trips through a float
            // loses precision in the last place, and "close to where you meant"
            // is not a useful property for a pickup point.
            'latitude' => 'string',
            'longitude' => 'string',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $address): void {
            $address->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<User, $this> */
    public function customer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    /**
     * The list order: default first, then newest.
     *
     * Deliberately deterministic. A list that reorders between two loads makes
     * people tap the wrong row.
     */
    public function scopeInDisplayOrder(Builder $query): Builder
    {
        return $query->orderByDesc('is_default')->orderByDesc('id');
    }

    /** @param  Builder<self>  $query */
    public function scopeOwnedBy(Builder $query, User $customer): Builder
    {
        return $query->where('customer_id', $customer->getKey());
    }

    /**
     * The API shape. An explicit allow-list, not `toArray()`.
     *
     * Coordinates are returned as they are stored — null until something actually
     * geocodes this address. A client must treat null as "unknown", never as 0,0,
     * which is a real place in the Gulf of Guinea.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'id' => $this->uuid,
            'type' => $this->type->value,
            'label' => $this->label,
            'address_line_1' => $this->address_line_1,
            'address_line_2' => $this->address_line_2,
            'landmark' => $this->landmark,
            'city' => $this->city,
            'state' => $this->state,
            'postal_code' => $this->postal_code,
            'country_code' => $this->country_code,
            'formatted_address' => $this->formatted_address,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'place_id' => $this->place_id,
            'is_default' => $this->is_default,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
