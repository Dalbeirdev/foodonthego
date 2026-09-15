<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * The lifecycle of an account.
 *
 * Authentication checks this **after** a successful OTP verification and before
 * issuing a token. Verifying a one-time code proves control of a phone number; it
 * says nothing about whether the account behind it is allowed to trade. A
 * suspended customer who can still receive SMS must not be able to sign in.
 */
enum AccountStatus: string
{
    case Active = 'active';
    case Suspended = 'suspended';
    case Disabled = 'disabled';
    case Deleted = 'deleted';

    /** Only an active account may hold a session. */
    public function canAuthenticate(): bool
    {
        return $this === self::Active;
    }

    /**
     * The error a blocked account receives. `Deleted` deliberately reports as
     * disabled: confirming that an account once existed and was deleted is
     * information the caller has not earned.
     */
    public function blockedErrorCode(): ApiErrorCode
    {
        return match ($this) {
            self::Suspended => ApiErrorCode::AccountSuspended,
            default => ApiErrorCode::AccountDisabled,
        };
    }

    public function label(): string
    {
        return ucfirst($this->value);
    }

    /** @return array<int, string> */
    public static function values(): array
    {
        return array_map(static fn (self $status): string => $status->value, self::cases());
    }
}
