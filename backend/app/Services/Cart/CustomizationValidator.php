<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\ApiErrorCode;
use App\Enums\MenuItemStockStatus;
use App\Exceptions\ApiException;
use App\Models\MenuItem;
use App\Models\MenuItemVariant;
use App\Models\MenuModifierGroup;
use App\Models\MenuModifierOption;
use Illuminate\Support\Collection;

/**
 * Whether a configuration is one the customer may actually order.
 *
 * Everything here is checked against rows read **now**, inside the same request
 * that will write the cart line. The customer's screen was drawn from a
 * response that may be ten minutes old; the kitchen may have run out of
 * mushrooms since. This is where that gap is closed.
 *
 * Three families of check, and the order matters:
 *
 * 1. **Ownership.** Does this variant belong to this dish, this option to a
 *    group this dish actually asks about? A request naming somebody else's
 *    "Large" must not get somebody else's price.
 * 2. **Availability.** Is it active, and does the kitchen still have it?
 * 3. **Rules.** Does the selection satisfy every group's minimum and maximum?
 *
 * Ownership first, because a "you must choose a spice level" message about a
 * dish the customer is not looking at would be nonsense.
 */
final class CustomizationValidator
{
    /**
     * @throws ApiException
     */
    public function validate(MenuItem $item, CustomizationSelection $selection): ResolvedCustomization
    {
        $this->assertItemOrderable($item);

        $variant = $this->resolveVariant($item, $selection);
        $modifiers = $this->resolveModifiers($item, $selection);

        $this->assertSelectionRules($item, $modifiers, $selection);
        $this->assertQuantity($selection);
        $this->assertInstructions($selection);

        return new ResolvedCustomization(
            item: $item,
            variant: $variant,
            modifiers: $modifiers,
            quantity: $selection->quantity,
            specialInstructions: $selection->specialInstructions,
            fingerprint: $selection->fingerprint(),
        );
    }

    /**
     * @throws ApiException
     */
    private function assertItemOrderable(MenuItem $item): void
    {
        if (! $item->is_active) {
            // Withdrawn. Answered as not-found rather than unavailable: an
            // active dish and a withdrawn one must look the same to anybody
            // probing ids.
            throw new ApiException(
                ApiErrorCode::ItemNotFound,
                'That menu item could not be found.',
            );
        }

        if ($item->stockStatus() !== MenuItemStockStatus::InStock) {
            throw new ApiException(
                ApiErrorCode::ItemSoldOut,
                'The kitchen has run out of this one.',
            );
        }
    }

    /**
     * @throws ApiException
     */
    private function resolveVariant(MenuItem $item, CustomizationSelection $selection): ?MenuItemVariant
    {
        /** @var Collection<int, MenuItemVariant> $variants */
        $variants = $item->variants;

        $selectable = $variants->filter(
            static fn (MenuItemVariant $v): bool => $v->isSelectable(),
        );

        if ($selection->variantUuid === null) {
            if ($selectable->isEmpty()) {
                // A dish with no sizes. Ordinary, and not a fake "Regular".
                return null;
            }

            $default = $item->defaultVariant();

            if ($default !== null) {
                return $default;
            }

            throw new ApiException(
                ApiErrorCode::VariantRequired,
                'Choose a size to continue.',
            );
        }

        $chosen = $variants->first(
            static fn (MenuItemVariant $v): bool => $v->uuid === $selection->variantUuid,
        );

        if ($chosen === null) {
            // No such size, or a size belonging to another dish. One answer for
            // both: telling them apart would let somebody with a list of ids
            // map a competitor's menu by elimination.
            throw new ApiException(
                ApiErrorCode::VariantInvalid,
                'That size is not available for this item.',
            );
        }

        if (! $chosen->isSelectable()) {
            throw new ApiException(
                ApiErrorCode::VariantUnavailable,
                'That size has just sold out. Choose another.',
            );
        }

        return $chosen;
    }

    /**
     * Every chosen option, proved to belong to a group this dish asks about.
     *
     * @return list<array{group: MenuModifierGroup, option: MenuModifierOption}>
     *
     * @throws ApiException
     */
    private function resolveModifiers(MenuItem $item, CustomizationSelection $selection): array
    {
        if ($selection->optionUuids === []) {
            return [];
        }

        /** @var array<string, array{group: MenuModifierGroup, option: MenuModifierOption}> $byUuid */
        $byUuid = [];

        foreach ($item->modifierGroups as $group) {
            foreach ($group->options as $option) {
                $byUuid[$option->uuid] = ['group' => $group, 'option' => $option];
            }
        }

        // Built in the order the *screen* shows them — group by group, option by
        // option — rather than in the order the uuids happen to sort. The
        // selection's own order is canonical for matching, which is a different
        // job: a breakdown that read "Extra Cheese, Mild" because of how two
        // random uuids compare would be correct arithmetic and nonsense to
        // read.
        $order = [];
        $rank = 0;

        foreach ($item->modifierGroups as $group) {
            foreach ($group->options as $option) {
                $order[$option->uuid] = $rank++;
            }
        }

        $chosen = $selection->optionUuids;

        usort(
            $chosen,
            static fn (string $a, string $b): int => ($order[$a] ?? PHP_INT_MAX) <=> ($order[$b] ?? PHP_INT_MAX),
        );

        $resolved = [];

        foreach ($chosen as $uuid) {
            $found = $byUuid[$uuid] ?? null;

            if ($found === null) {
                // An option from another dish, another group, or nothing at
                // all. The lookup is built from this dish's own groups, so
                // there is no way for a foreign id to be present in it.
                throw new ApiException(
                    ApiErrorCode::ModifierInvalid,
                    'One of those choices is not available for this item.',
                );
            }

            if (! $found['option']->isSelectable()) {
                throw new ApiException(
                    ApiErrorCode::ModifierUnavailable,
                    'One of those choices has just sold out. Review your selection.',
                    ['group_id' => $found['group']->uuid, 'option_id' => $found['option']->uuid],
                );
            }

            $resolved[] = $found;
        }

        return $resolved;
    }

    /**
     * Every group's minimum and maximum, checked against what was chosen.
     *
     * @param  list<array{group: MenuModifierGroup, option: MenuModifierOption}>  $modifiers
     *
     * @throws ApiException
     */
    private function assertSelectionRules(
        MenuItem $item,
        array $modifiers,
        CustomizationSelection $selection,
    ): void {
        /** @var array<int, int> $chosenPerGroup */
        $chosenPerGroup = [];

        foreach ($modifiers as $pair) {
            $groupId = (int) $pair['group']->id;
            $chosenPerGroup[$groupId] = ($chosenPerGroup[$groupId] ?? 0) + 1;
        }

        foreach ($item->modifierGroups as $group) {
            $chosen = $chosenPerGroup[(int) $group->id] ?? 0;
            $min = $group->minSelect();
            $max = $group->maxSelect();

            if ($chosen > $max) {
                throw new ApiException(
                    ApiErrorCode::ModifierMaxExceeded,
                    $this->maxMessage($group->name, $max),
                    ['group_id' => $group->uuid, 'max_select' => $max],
                );
            }

            if ($chosen >= $min) {
                continue;
            }

            // Below the minimum. Two codes rather than one, because "you have
            // not chosen a spice level" and "you have chosen one of the two
            // sauces you need" are different sentences on screen.
            throw new ApiException(
                $min === 1 ? ApiErrorCode::ModifierRequired : ApiErrorCode::ModifierMinNotMet,
                $this->minMessage($group->name, $min),
                ['group_id' => $group->uuid, 'min_select' => $min, 'selected' => $chosen],
            );
        }
    }

    private function minMessage(string $group, int $min): string
    {
        return $min === 1
            ? "Choose an option under {$group} to continue."
            : "Choose at least {$min} options under {$group} to continue.";
    }

    private function maxMessage(string $group, int $max): string
    {
        return $max === 1
            ? "Choose only one option under {$group}."
            : "Choose at most {$max} options under {$group}.";
    }

    /**
     * @throws ApiException
     */
    private function assertQuantity(CustomizationSelection $selection): void
    {
        if ($selection->quantity < 1) {
            // Zero is not "remove"; on this screen it is a client bug or a
            // tampered request. A customer who wants none simply does not add.
            throw new ApiException(
                ApiErrorCode::QuantityInvalid,
                'Choose at least one.',
            );
        }

        $max = (int) config('foodonthego.cart.max_quantity_per_line');

        if ($selection->quantity > $max) {
            throw new ApiException(
                ApiErrorCode::QuantityLimitExceeded,
                "You can add up to {$max} of one item at a time.",
                ['max_quantity' => $max],
            );
        }
    }

    /**
     * @throws ApiException
     */
    private function assertInstructions(CustomizationSelection $selection): void
    {
        $note = $selection->specialInstructions;

        if ($note === null) {
            return;
        }

        $max = (int) config('foodonthego.cart.max_special_instructions');

        // Counted in characters, not bytes: a note in Devanagari is not four
        // times shorter than one in English.
        if (mb_strlen($note) > $max) {
            throw new ApiException(
                ApiErrorCode::SpecialInstructionsTooLong,
                "Keep your note to {$max} characters or fewer.",
                ['max_length' => $max],
            );
        }
    }
}
