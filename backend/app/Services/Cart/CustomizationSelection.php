<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use Illuminate\Http\Request;

/**
 * What the customer says they want.
 *
 * **Selections only. No money.** There is no unit price, no subtotal, no
 * discount and no total on this object, because there is none in the request:
 * the client says which dish, which size and which options, and the server
 * decides what that costs. A field that does not exist cannot be tampered with,
 * and this class is where that guarantee is made structural rather than
 * remembered.
 *
 * The one number that *does* come from the client is
 * {@see $quotedUnitPriceMinor}, and it is not a price to charge — it is the
 * customer's statement of what they were shown. The server compares its own
 * figure to it and refuses to charge more than the customer saw. Sending a
 * higher one buys an attacker nothing (they still pay the real price); sending
 * a lower one gets the add refused. See {@see MenuItemPricingService}.
 */
final readonly class CustomizationSelection
{
    /**
     * @param  list<string>  $optionUuids  the chosen options, as uuids
     */
    private function __construct(
        public string $itemUuid,
        public ?string $variantUuid,
        public array $optionUuids,
        public int $quantity,
        public ?string $specialInstructions,
        public ?int $quotedUnitPriceMinor,
    ) {}

    /**
     * @param  list<string>  $optionUuids
     */
    public static function of(
        string $itemUuid,
        ?string $variantUuid = null,
        array $optionUuids = [],
        int $quantity = 1,
        ?string $specialInstructions = null,
        ?int $quotedUnitPriceMinor = null,
    ): self {
        return new self(
            itemUuid: $itemUuid,
            variantUuid: $variantUuid,
            optionUuids: self::canonicalise($optionUuids),
            quantity: $quantity,
            specialInstructions: $specialInstructions,
            quotedUnitPriceMinor: $quotedUnitPriceMinor,
        );
    }

    /**
     * Reads the request, and refuses anything that is not a selection.
     *
     * @throws ApiException
     */
    public static function fromRequest(Request $request): self
    {
        $itemUuid = $request->input('item_id');

        if (! is_string($itemUuid) || $itemUuid === '') {
            throw self::invalid('item_id', 'Choose an item.');
        }

        $variantUuid = $request->input('variant_id');

        if ($variantUuid !== null && (! is_string($variantUuid) || $variantUuid === '')) {
            throw self::invalid('variant_id', 'That size could not be read.');
        }

        return new self(
            itemUuid: $itemUuid,
            variantUuid: $variantUuid,
            optionUuids: self::canonicalise(self::readOptionUuids($request)),
            quantity: self::readQuantity($request),
            specialInstructions: self::readInstructions($request),
            quotedUnitPriceMinor: self::readQuotedPrice($request),
        );
    }

    /**
     * The chosen options, from either shape the client may send.
     *
     * Grouped (`modifier_groups: [{group_id, option_ids}]`) is the documented
     * shape because it reads clearly. The group ids in it are **ignored**: an
     * option already knows its group, and trusting the client's pairing would
     * let a request claim "Spice level: Extra Cheese" and have the breakdown
     * agree with it.
     *
     * @return list<string>
     */
    private static function readOptionUuids(Request $request): array
    {
        $uuids = [];

        $groups = $request->input('modifier_groups');

        if (is_array($groups)) {
            foreach ($groups as $group) {
                if (! is_array($group)) {
                    continue;
                }

                $ids = $group['option_ids'] ?? null;

                if (is_array($ids)) {
                    foreach ($ids as $id) {
                        if (is_string($id) && $id !== '') {
                            $uuids[] = $id;
                        }
                    }
                }
            }
        }

        // The flat shape, accepted because it is what a hand-written client
        // reaches for first and there is no reason to refuse it.
        $flat = $request->input('modifier_option_ids');

        if (is_array($flat)) {
            foreach ($flat as $id) {
                if (is_string($id) && $id !== '') {
                    $uuids[] = $id;
                }
            }
        }

        return $uuids;
    }

    /**
     * @throws ApiException
     */
    private static function readQuantity(Request $request): int
    {
        $raw = $request->input('quantity', 1);

        // Deliberately strict. "2" from a form is fine; 2.5, "two" and true are
        // not, and coercing them would turn a client bug into a quiet
        // half-portion.
        if (is_string($raw) && ctype_digit($raw)) {
            $raw = (int) $raw;
        }

        if (! is_int($raw)) {
            throw new ApiException(
                ApiErrorCode::QuantityInvalid,
                'Choose how many you would like.',
            );
        }

        return $raw;
    }

    private static function readInstructions(Request $request): ?string
    {
        $raw = $request->input('special_instructions');

        if (! is_string($raw)) {
            return null;
        }

        // Runs of whitespace collapsed, but line breaks kept: "no onion" on its
        // own line is how somebody writes a second request, and flattening it
        // makes the kitchen's ticket harder to read.
        $clean = trim((string) preg_replace('/[ \t]+/u', ' ', $raw));

        return $clean === '' ? null : $clean;
    }

    /**
     * What the customer was shown, if the client said.
     *
     * Not a price to charge. Anything unreadable is simply absent, which means
     * "the client did not tell us" and leads to the add proceeding at the
     * server's price — the same outcome as an honest client whose figure
     * matched.
     */
    private static function readQuotedPrice(Request $request): ?int
    {
        $raw = $request->input('quoted_unit_price_minor');

        if (is_string($raw) && ctype_digit($raw)) {
            $raw = (int) $raw;
        }

        return (is_int($raw) && $raw >= 0) ? $raw : null;
    }

    /**
     * Sorted and de-duplicated.
     *
     * This is what makes cheese-then-jalapeño the same configuration as
     * jalapeño-then-cheese, so adding the same thing twice increments a line
     * instead of growing a second identical one.
     *
     * @param  list<string>  $uuids
     * @return list<string>
     */
    private static function canonicalise(array $uuids): array
    {
        $unique = array_values(array_unique($uuids));
        sort($unique);

        return $unique;
    }

    /**
     * A stable fingerprint of this configuration.
     *
     * Two selections hash the same exactly when a customer would call them the
     * same order: same dish, same size, same options, same note. A different
     * note is a different line, because "no onion" is not a detail the kitchen
     * can merge with "extra onion".
     *
     * Quantity is deliberately absent — two of a thing and three of a thing are
     * the same configuration in different amounts.
     */
    public function fingerprint(): string
    {
        return hash('sha256', json_encode([
            'item' => $this->itemUuid,
            'variant' => $this->variantUuid,
            'options' => $this->optionUuids,
            'note' => $this->specialInstructions,
        ], JSON_THROW_ON_ERROR));
    }

    public function withQuantity(int $quantity): self
    {
        return new self(
            itemUuid: $this->itemUuid,
            variantUuid: $this->variantUuid,
            optionUuids: $this->optionUuids,
            quantity: $quantity,
            specialInstructions: $this->specialInstructions,
            quotedUnitPriceMinor: $this->quotedUnitPriceMinor,
        );
    }

    private static function invalid(string $field, string $message): ApiException
    {
        return new ApiException(
            ApiErrorCode::ValidationFailed,
            $message,
            ['fields' => [$field => [$message]]],
        );
    }
}
