<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use Illuminate\Support\Str;

/**
 * The two test customers Module 04 is specified around.
 *
 * Rahul owns things; Ananya exists so that every ownership test has a real
 * second account to attack across, rather than a fabricated id that a
 * `WHERE customer_id = ?` would filter out by accident rather than by rule.
 *
 * Both use numbers from the Indian range reserved for documentation, so no test
 * can reach a real handset.
 */
final class CustomerFactory
{
    public static function rahul(): User
    {
        return self::make('Rahul', 'Sharma', '+919999900101', 'rahul.test@foodonthego.example');
    }

    public static function ananya(): User
    {
        return self::make('Ananya', 'Mehta', '+919999900102', 'ananya.test@foodonthego.example');
    }

    public static function make(
        string $firstName,
        ?string $lastName,
        string $phoneE164,
        ?string $email = null,
        AccountStatus $status = AccountStatus::Active,
        Role $role = Role::Customer,
    ): User {
        return User::create([
            'uuid' => (string) Str::uuid(),
            'first_name' => $firstName,
            'last_name' => $lastName,
            'name' => trim($firstName.' '.($lastName ?? '')),
            'email' => $email,
            'phone_e164' => $phoneE164,
            'phone_verified_at' => now(),
            'role' => $role->value,
            'status' => $status->value,
        ]);
    }

    /** A real Sanctum token for [$customer], with the customer ability. */
    public static function tokenFor(User $customer): string
    {
        return $customer
            ->createToken('customer-mobile', [CustomerAuthService::CUSTOMER_ABILITY])
            ->plainTextToken;
    }
}
