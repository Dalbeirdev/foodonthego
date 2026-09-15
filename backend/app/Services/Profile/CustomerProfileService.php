<?php

declare(strict_types=1);

namespace App\Services\Profile;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Updates the parts of a customer's account the customer owns.
 *
 * The list is short on purpose. A customer may change their name and their email
 * address. Everything else about their account — the verified phone number, the
 * role, the status, the verification timestamps — is either identity or
 * privilege, and neither is self-service.
 *
 * The enforcement is layered rather than trusted to one place: the form request
 * declares no rule for those fields, this method reads only three keys by name,
 * and `User::$fillable` would refuse the rest anyway. Any one of the three would
 * be enough; all three means a change to one of them is not a vulnerability.
 */
final class CustomerProfileService
{
    /**
     * @param  array<string, mixed>  $input  Validated request data.
     */
    public function update(User $customer, array $input): User
    {
        $changed = [];

        return DB::transaction(function () use ($customer, $input, &$changed): User {
            if (array_key_exists('first_name', $input)) {
                $customer->first_name = trim((string) $input['first_name']);
                $changed[] = 'first_name';
            }

            if (array_key_exists('last_name', $input)) {
                // Blank clears it rather than storing "". Somebody removing a
                // surname they never had is not the same as having an empty one,
                // and every later `last_name !== null` check depends on that.
                $lastName = trim((string) ($input['last_name'] ?? ''));
                $customer->last_name = $lastName === '' ? null : $lastName;
                $changed[] = 'last_name';
            }

            if (array_key_exists('email', $input)) {
                $email = trim((string) ($input['email'] ?? ''));
                $newEmail = $email === '' ? null : $email;

                // Changing the address un-verifies it. There is no email
                // verification module yet, so this is always null in practice —
                // written now so that adding one later cannot leave a customer
                // with a "verified" flag attached to an address they swapped in
                // afterwards.
                if ($newEmail !== $customer->email) {
                    $customer->email_verified_at = null;
                }

                $customer->email = $newEmail;
                $changed[] = 'email';
            }

            // Kept in step with first/last name. The legacy single `name` column
            // still backs `displayName()` for accounts created before Module 03,
            // and letting it go stale would show two different names in two
            // different places.
            $customer->name = trim(
                ($customer->first_name ?? '').' '.($customer->last_name ?? ''),
            );

            $customer->save();

            // Field names, never values: a log line recording that somebody
            // changed their email is operationally useful, one recording the
            // address itself is a copy of their personal data on disk.
            Log::info('profile.updated', [
                'actor_id' => $customer->uuid,
                'fields' => $changed,
            ]);

            return $customer;
        });
    }
}
