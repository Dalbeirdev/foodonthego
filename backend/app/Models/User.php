<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Services\Tenancy\TenantAccessService;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Str;
use Laravel\Sanctum\HasApiTokens;

final class User extends Authenticatable
{
    // Sanctum's personal access tokens. Customers authenticate by bearer token
    // and never by session, so this trait is the whole credential mechanism.
    use HasApiTokens;

    /** @use HasFactory<UserFactory> */
    use HasFactory;

    use Notifiable;
    use SoftDeletes;

    protected $fillable = [
        'uuid', 'name', 'first_name', 'last_name', 'email', 'phone', 'phone_e164',
        'password', 'role', 'status', 'is_active', 'phone_verified_at', 'email_verified_at',
    ];

    /**
     * `password` and `remember_token` are hidden from every array/JSON conversion,
     * so a hash cannot reach a response or a log line by somebody serialising the
     * model without thinking about it.
     */
    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'phone_verified_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'password' => 'hashed',
            'role' => Role::class,
            'status' => AccountStatus::class,
            'is_active' => 'boolean',
            'last_login_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        // Assigned here rather than left to callers, so no code path can create a
        // user without the public identifier the API needs.
        self::creating(static function (self $user): void {
            $user->uuid ??= (string) Str::uuid();
        });
    }

    /** The API never exposes the auto-increment id. */
    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /**
     * The restaurants this account is assigned to, revoked rows included.
     *
     * Never the basis for an authorisation decision on its own — that goes
     * through {@see TenantAccessService}, which also
     * checks the surface and the account's standing. This is for showing
     * somebody their own list.
     */
    /** @return HasMany<RestaurantMembership, $this> */
    public function restaurantMemberships(): HasMany
    {
        return $this->hasMany(RestaurantMembership::class);
    }

    /** @return HasMany<PlatformTenantGrant, $this> */
    public function platformTenantGrants(): HasMany
    {
        return $this->hasMany(PlatformTenantGrant::class);
    }

    public function hasRole(Role ...$roles): bool
    {
        return in_array($this->role, $roles, true);
    }

    /** The name to show. Falls back to the legacy single `name` column. */
    public function displayName(): string
    {
        $composed = trim(($this->first_name ?? '').' '.($this->last_name ?? ''));

        return $composed !== '' ? $composed : (string) ($this->name ?? '');
    }

    /**
     * The customer profile shape returned by `/api/v1/customer/me`.
     *
     * An explicit allow-list, not `toArray()`. A model serialised wholesale is how
     * an internal column ends up in a response the first time somebody adds one.
     *
     * @return array<string, mixed>
     */
    public function toCustomerProfile(): array
    {
        return [
            'id' => $this->uuid,
            'first_name' => $this->first_name,
            'last_name' => $this->last_name,
            'full_name' => $this->displayName(),
            'phone' => $this->phone_e164,
            'email' => $this->email,
            'phone_verified' => $this->phone_verified_at !== null,
            'email_verified' => $this->email_verified_at !== null,
            'status' => $this->status->value,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
