<?php

declare(strict_types=1);

namespace App\Services\Address;

use App\Enums\AddressType;
use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\CustomerAddress;
use App\Models\User;
use App\Support\Address\AddressFormatter;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Every write to a saved address goes through here.
 *
 * Three responsibilities, and each exists because doing it anywhere else would
 * be a bug waiting to happen:
 *
 *  - **Ownership.** The customer is always the authenticated actor, never a value
 *    from a request body. `ownedByOrFail()` is the only way to reach one address.
 *  - **The one-default rule.** Exactly one default per customer, held by a
 *    transaction plus a row lock — and, underneath, by a unique index the database
 *    will not let any code path violate.
 *  - **Derived state.** The one-line `formatted_address` and the fallback label
 *    are composed here, so they cannot drift between a create and an update.
 */
final class CustomerAddressService
{
    /** @return Collection<int, CustomerAddress> */
    public function listFor(User $customer): Collection
    {
        return CustomerAddress::query()
            ->ownedBy($customer)
            ->inDisplayOrder()
            ->get();
    }

    /**
     * Finds one address belonging to this customer.
     *
     * An address owned by somebody else and an address that does not exist give
     * **the same** answer. Distinguishing them would turn this endpoint into an
     * oracle: walk a range of ids, and 403-versus-404 tells you which ones are
     * real addresses belonging to real customers.
     *
     * @throws ApiException
     */
    public function ownedByOrFail(User $customer, string $uuid): CustomerAddress
    {
        $address = CustomerAddress::query()
            ->ownedBy($customer)
            ->where('uuid', $uuid)
            ->first();

        if ($address === null) {
            Log::info('address.access_denied', [
                'actor_id' => $customer->uuid,
                'address_uuid' => $uuid,
            ]);

            throw new ApiException(
                ApiErrorCode::AddressNotFound,
                'That saved address does not exist.',
            );
        }

        return $address;
    }

    /**
     * Creates an address for the authenticated customer.
     *
     * @param  array<string, mixed>  $attributes  Already validated and allow-listed.
     */
    public function create(User $customer, array $attributes, bool $makeDefault): CustomerAddress
    {
        return DB::transaction(function () use ($customer, $attributes, $makeDefault): CustomerAddress {
            // Locked for the whole transaction: the count below decides whether
            // the limit is reached and whether this is the first address, and
            // both would be wrong under a concurrent create.
            $existing = $this->lockedAddressesOf($customer);

            $limit = (int) config('foodonthego.addresses.max_per_customer');
            if ($existing->count() >= $limit) {
                throw new ApiException(
                    ApiErrorCode::AddressLimitReached,
                    "You can save up to {$limit} addresses. Remove one to add another.",
                );
            }

            // The first address a customer saves becomes their default, whether
            // or not they asked. A saved-address list with no default would make
            // the trip planner ask "from where?" to somebody who has answered
            // that exactly once.
            $isDefault = $makeDefault || $existing->isEmpty();

            if ($isDefault) {
                $this->clearDefault($existing);
            }

            $address = new CustomerAddress($this->derive($attributes));
            $address->customer_id = $customer->getKey();
            $address->is_default = $isDefault;
            $address->save();

            // Re-read so the response carries what the database actually stored,
            // not what was sent. Decimal columns round-trip to a fixed scale, and
            // returning the un-persisted value would make a create response and a
            // later fetch of the same address disagree.
            $address->refresh();

            Log::info('address.created', [
                'actor_id' => $customer->uuid,
                'address_uuid' => $address->uuid,
                'type' => $address->type->value,
                'is_default' => $isDefault,
            ]);

            return $address;
        });
    }

    /**
     * Updates an address the customer owns.
     *
     * @param  array<string, mixed>  $attributes  Already validated and allow-listed.
     */
    public function update(
        User $customer,
        CustomerAddress $address,
        array $attributes,
        ?bool $makeDefault,
    ): CustomerAddress {
        return DB::transaction(function () use ($customer, $address, $attributes, $makeDefault): CustomerAddress {
            $existing = $this->lockedAddressesOf($customer);

            // Merged with what is already stored before the one-line form is
            // recomposed: a PATCH that changes only the city must still produce a
            // formatted address containing the street.
            $merged = array_merge($address->only([
                'type', 'label', 'address_line_1', 'address_line_2', 'landmark',
                'city', 'state', 'postal_code', 'country_code',
                'latitude', 'longitude', 'place_id',
            ]), $attributes);

            $address->fill($this->derive($merged));

            if ($makeDefault === true && ! $address->is_default) {
                $this->clearDefault($existing);
                $address->is_default = true;
            }

            // Deliberately ignored. Un-defaulting by PATCH would leave a customer
            // with addresses and no default, which the create path works to avoid.
            // Choosing a different default is what `is_default: true` on the other
            // address is for.

            $address->save();
            $address->refresh();

            Log::info('address.updated', [
                'actor_id' => $customer->uuid,
                'address_uuid' => $address->uuid,
                'became_default' => $makeDefault === true,
            ]);

            return $address;
        });
    }

    /**
     * Deletes an address, promoting a replacement default when needed.
     *
     * Hard delete, not soft. An address is personal location data, and a customer
     * who removes one has asked for it to be gone — keeping a hidden copy is the
     * opposite of what they said. Historical trips and orders will hold their own
     * snapshot of the address they used (documented in
     * docs/19-customer-profile-and-addresses.md), so nothing downstream depends on
     * this row surviving.
     */
    public function delete(User $customer, CustomerAddress $address): void
    {
        DB::transaction(function () use ($customer, $address): void {
            $wasDefault = $address->is_default;
            $address->delete();

            if (! $wasDefault) {
                Log::info('address.deleted', [
                    'actor_id' => $customer->uuid,
                    'address_uuid' => $address->uuid,
                    'was_default' => false,
                ]);

                return;
            }

            // Deleting the default promotes the newest remaining address rather
            // than leaving the customer with none. Deterministic, so the same
            // deletion always produces the same result — and the newest is the
            // best available guess at where they are living or working now.
            $replacement = $this->lockedAddressesOf($customer)->first();
            $replacement?->forceFill(['is_default' => true])->save();

            Log::info('address.deleted', [
                'actor_id' => $customer->uuid,
                'address_uuid' => $address->uuid,
                'was_default' => true,
                'promoted_uuid' => $replacement?->uuid,
            ]);
        });
    }

    /** Makes one address the customer's default. */
    public function makeDefault(User $customer, CustomerAddress $address): CustomerAddress
    {
        return DB::transaction(function () use ($customer, $address): CustomerAddress {
            $existing = $this->lockedAddressesOf($customer);

            if ($address->is_default) {
                return $address;
            }

            $this->clearDefault($existing);

            $address->forceFill(['is_default' => true])->save();

            Log::info('address.default_changed', [
                'actor_id' => $customer->uuid,
                'address_uuid' => $address->uuid,
            ]);

            return $address;
        });
    }

    /**
     * This customer's addresses, locked for the rest of the transaction.
     *
     * `lockForUpdate` is what serialises two concurrent "make this my default"
     * requests: the second waits for the first to commit and then sees its
     * result, rather than both reading "no default yet" and both writing one.
     *
     * @return Collection<int, CustomerAddress>
     */
    private function lockedAddressesOf(User $customer): Collection
    {
        return CustomerAddress::query()
            ->ownedBy($customer)
            ->inDisplayOrder()
            ->lockForUpdate()
            ->get();
    }

    /**
     * Clears the current default, if there is one.
     *
     * Must happen before the new default is written, not after: the unique index
     * on the generated column would reject two defaults existing at once, even
     * momentarily inside the transaction.
     *
     * @param  Collection<int, CustomerAddress>  $addresses
     */
    private function clearDefault(Collection $addresses): void
    {
        foreach ($addresses as $existing) {
            if ($existing->is_default) {
                $existing->forceFill(['is_default' => false])->save();
            }
        }
    }

    /**
     * Fills in what the customer did not type.
     *
     * @param  array<string, mixed>  $attributes
     * @return array<string, mixed>
     */
    private function derive(array $attributes): array
    {
        $type = $attributes['type'] instanceof AddressType
            ? $attributes['type']
            : AddressType::from((string) $attributes['type']);

        $label = trim((string) ($attributes['label'] ?? ''));
        if ($label === '') {
            $label = $type->defaultLabel();
        }

        $attributes['type'] = $type->value;
        $attributes['label'] = $label;
        $attributes['country_code'] = strtoupper(trim((string) $attributes['country_code']));
        $attributes['formatted_address'] = AddressFormatter::compose($attributes);

        return $attributes;
    }
}
