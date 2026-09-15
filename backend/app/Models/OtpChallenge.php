<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * One issued OTP and its security state.
 *
 * @property int $id
 * @property string $uuid
 * @property string $phone_e164
 * @property string $otp_hash
 * @property Carbon $expires_at
 * @property int $attempts
 * @property int $max_attempts
 * @property Carbon|null $consumed_at
 * @property Carbon|null $invalidated_at
 * @property string|null $invalidated_reason
 * @property int $resend_count
 * @property Carbon|null $last_sent_at
 * @property string|null $request_ip
 */
final class OtpChallenge extends Model
{
    protected $fillable = [
        'uuid', 'phone_e164', 'otp_hash', 'expires_at', 'attempts', 'max_attempts',
        'consumed_at', 'invalidated_at', 'invalidated_reason', 'resend_count',
        'last_sent_at', 'request_ip',
    ];

    /** The hash must never reach a response or an array dump. */
    protected $hidden = ['otp_hash'];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'consumed_at' => 'datetime',
            'invalidated_at' => 'datetime',
            'last_sent_at' => 'datetime',
            'attempts' => 'integer',
            'max_attempts' => 'integer',
            'resend_count' => 'integer',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $challenge): void {
            $challenge->uuid ??= (string) Str::uuid();
        });
    }

    public function isExpired(?Carbon $now = null): bool
    {
        return $this->expires_at->isBefore($now ?? now());
    }

    public function isConsumed(): bool
    {
        return $this->consumed_at !== null;
    }

    public function isInvalidated(): bool
    {
        return $this->invalidated_at !== null;
    }

    public function hasAttemptsLeft(): bool
    {
        return $this->attempts < $this->max_attempts;
    }

    /**
     * Usable means: not used, not invalidated, not expired, attempts remaining.
     * All four, because each corresponds to a different attack or mistake.
     */
    public function isUsable(?Carbon $now = null): bool
    {
        return ! $this->isConsumed()
            && ! $this->isInvalidated()
            && ! $this->isExpired($now)
            && $this->hasAttemptsLeft();
    }
}
