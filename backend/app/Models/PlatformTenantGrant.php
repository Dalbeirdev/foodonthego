<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\TenantRole;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * What a platform person may reach across tenants, recorded explicitly.
 *
 * With no row, a super administrator reaches nothing. That is deliberate: the
 * alternative is a rule that lives in an `if` somewhere and grants everything to
 * anybody who ever holds the role, including the account somebody phished.
 */
final class PlatformTenantGrant extends Model
{
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
        self::creating(static function (self $grant): void {
            $grant->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function scopeActive(Builder $query): void
    {
        $query->where('status', 'active');
    }

    /** Every tenant, present and future. */
    public function isPlatformWide(): bool
    {
        return $this->scope === 'all';
    }
}
