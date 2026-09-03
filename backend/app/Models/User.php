<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\Role;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Str;

final class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasFactory;

    use Notifiable;
    use SoftDeletes;

    protected $fillable = ['uuid', 'name', 'email', 'phone', 'password', 'role', 'is_active'];

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
            'is_active' => 'boolean',
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

    public function hasRole(Role ...$roles): bool
    {
        return in_array($this->role, $roles, true);
    }
}
