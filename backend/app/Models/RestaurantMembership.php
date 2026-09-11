<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\TenantRole;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One person's assignment to one restaurant.
 *
 * The tenant boundary as a row. Nothing reaches a restaurant without one of
 * these — or a platform grant, which is the same idea for people who work for
 * the platform rather than for a restaurant.
 *
 * Empty `$fillable`, like every model here: an assignment is created by a
 * service from checked arguments, never from a request body. A mass-assignable
 * `tenant_role` is a promotion endpoint nobody meant to write.
 */
final class RestaurantMembership extends Model
{
    protected $table = 'restaurant_user';

    /** @var list<string> */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'tenant_role' => TenantRole::class,
            'granted_at' => 'immutable_datetime',
            'revoked_at' => 'immutable_datetime',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $membership): void {
            $membership->uuid ??= (string) Str::uuid();
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

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return BelongsTo<User, $this> */
    public function grantedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'granted_by_user_id');
    }

    /**
     * Assignments that currently grant something.
     *
     * A revoked row still exists — that is the point of revoking rather than
     * deleting — and must never be read as access. Every query that asks "may
     * they" goes through this scope, so the filter cannot be forgotten in one
     * place and remembered in another.
     */
    public function scopeActive(Builder $query): void
    {
        $query->where('status', 'active');
    }

    public function isActive(): bool
    {
        return $this->status === 'active';
    }
}
