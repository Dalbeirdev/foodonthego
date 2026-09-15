<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Every role FoodOnTheGo will ever authorise against, declared now so that later
 * modules extend a known set rather than inventing role strings as they go.
 *
 * Roles are stored as these string values, never as integers: a database row that
 * reads 'restaurant_manager' is self-describing, and re-ordering an enum can never
 * silently promote somebody.
 */
enum Role: string
{
    case Customer = 'customer';
    case RestaurantOwner = 'restaurant_owner';
    case RestaurantManager = 'restaurant_manager';
    case RestaurantStaff = 'restaurant_staff';
    case SupportAgent = 'support_agent';
    case Admin = 'admin';
    case SuperAdmin = 'super_admin';

    public function label(): string
    {
        return match ($this) {
            self::Customer => 'Customer',
            self::RestaurantOwner => 'Restaurant owner',
            self::RestaurantManager => 'Restaurant manager',
            self::RestaurantStaff => 'Restaurant staff',
            self::SupportAgent => 'Support agent',
            self::Admin => 'Administrator',
            self::SuperAdmin => 'Super administrator',
        };
    }

    /** Roles that belong to a restaurant rather than to the platform. */
    public function isRestaurantRole(): bool
    {
        return in_array($this, [self::RestaurantOwner, self::RestaurantManager, self::RestaurantStaff], true);
    }

    /** Roles that operate the platform itself. */
    public function isPlatformRole(): bool
    {
        return in_array($this, [self::SupportAgent, self::Admin, self::SuperAdmin], true);
    }

    /**
     * Which surface a role signs in to. A customer has no business in the admin
     * panel and an admin has no customer app, so the shells can be kept apart at
     * the routing layer as well as by permission.
     */
    public function surface(): string
    {
        return match (true) {
            $this === self::Customer => 'mobile',
            $this->isRestaurantRole() => 'restaurant',
            default => 'admin',
        };
    }

    /** @return array<int, string> */
    public static function values(): array
    {
        return array_map(static fn (self $role): string => $role->value, self::cases());
    }
}
