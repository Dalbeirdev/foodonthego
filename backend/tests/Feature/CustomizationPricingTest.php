<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Enums\ApiErrorCode;
use App\Enums\MenuItemStockStatus;
use App\Exceptions\ApiException;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Services\Cart\CustomizationSelection;
use App\Services\Cart\CustomizationValidator;
use App\Services\Cart\MenuItemPricingService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Whether a configuration is legal, and what it costs.
 *
 * The two services that decide everything a customer is charged, tested away
 * from HTTP so the arithmetic and the rules can be read on their own.
 */
final class CustomizationPricingTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    /** @var array<string, mixed> */
    private array $menu;

    private CustomizationValidator $validator;

    private MenuItemPricingService $pricing;

    protected function setUp(): void
    {
        parent::setUp();

        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $this->menu = MenuFixtures::configurableItem($this->restaurant);
        $this->validator = new CustomizationValidator;
        $this->pricing = new MenuItemPricingService;
    }

    private function item(): MenuItem
    {
        /** @var MenuItem $item */
        $item = $this->menu['item'];

        return $item->fresh(['variants', 'modifierGroups.options']) ?? $item;
    }

    /** @param list<string> $optionUuids */
    private function priceOf(
        ?string $variantUuid,
        array $optionUuids = [],
        int $quantity = 1,
    ): int {
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                variantUuid: $variantUuid,
                optionUuids: $optionUuids,
                quantity: $quantity,
            ),
        );

        return $this->pricing->price($resolved)->lineTotal->minor;
    }

    // --- the arithmetic ------------------------------------------------------

    public function test_a_variant_price_replaces_the_base_rather_than_adding_to_it(): void
    {
        // Regular is ₹249 and the item's base price is also ₹249; Large is ₹329.
        // If the variant were a delta this would come out at ₹578.
        $this->assertSame(32_900, $this->priceOf($this->menu['large']->uuid, [$this->menu['mild']->uuid]));
    }

    public function test_an_item_with_no_variants_is_priced_from_its_base(): void
    {
        $category = MenuFixtures::category($this->restaurant, 'Breads', 1);
        $roti = MenuFixtures::item($category, 'Tandoori Roti', 3_900);

        $resolved = $this->validator->validate(
            $roti->fresh(['variants', 'modifierGroups.options']) ?? $roti,
            CustomizationSelection::of(itemUuid: $roti->uuid),
        );

        // No fake "Regular" invented to hang a price on.
        $this->assertNull($resolved->variant);
        $this->assertSame(3_900, $this->pricing->price($resolved)->unitPrice->minor);
    }

    public function test_paid_options_are_added_to_the_unit_price(): void
    {
        $total = $this->priceOf(
            $this->menu['large']->uuid,
            [$this->menu['mild']->uuid, $this->menu['cheese']->uuid, $this->menu['jalapeno']->uuid],
        );

        // 329 + 40 + 20.
        $this->assertSame(38_900, $total);
    }

    public function test_the_unit_price_is_multiplied_by_the_quantity(): void
    {
        $total = $this->priceOf(
            $this->menu['large']->uuid,
            [$this->menu['mild']->uuid, $this->menu['cheese']->uuid, $this->menu['jalapeno']->uuid],
            2,
        );

        $this->assertSame(77_800, $total);
    }

    public function test_the_breakdown_shows_where_the_total_came_from(): void
    {
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                variantUuid: $this->menu['large']->uuid,
                optionUuids: [$this->menu['mild']->uuid, $this->menu['cheese']->uuid],
                quantity: 2,
            ),
        );

        $priced = $this->pricing->price($resolved);

        $this->assertSame('Large', $priced->baseLabel);
        $this->assertSame(32_900, $priced->base->minor);

        // A free choice is listed too: its absence would read like it did not
        // land.
        $this->assertCount(2, $priced->additions);
        $this->assertSame(0, $priced->additions[0]['amount']->minor);
        $this->assertSame(4_000, $priced->additions[1]['amount']->minor);

        $this->assertSame(36_900, $priced->unitPrice->minor);
        $this->assertSame(73_800, $priced->lineTotal->minor);
    }

    public function test_a_default_variant_is_used_when_the_customer_chose_none(): void
    {
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                optionUuids: [$this->menu['mild']->uuid],
            ),
        );

        $this->assertSame('Regular', $resolved->variant?->name);
    }

    // --- what is refused -----------------------------------------------------

    public function test_a_size_must_be_chosen_when_there_is_no_default(): void
    {
        $this->menu['regular']->forceFill(['is_default' => false])->save();

        $this->expectApiError(
            ApiErrorCode::VariantRequired,
            fn () => $this->priceOf(null, [$this->menu['mild']->uuid]),
        );
    }

    public function test_a_variant_of_another_item_is_refused(): void
    {
        $other = MenuFixtures::configurableItem(
            RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites'),
        );

        $this->expectApiError(
            ApiErrorCode::VariantInvalid,
            fn () => $this->priceOf($other['large']->uuid, [$this->menu['mild']->uuid]),
        );
    }

    public function test_an_unavailable_variant_is_refused(): void
    {
        $this->menu['large']->forceFill(['is_available' => false])->save();

        $this->expectApiError(
            ApiErrorCode::VariantUnavailable,
            fn () => $this->priceOf($this->menu['large']->uuid, [$this->menu['mild']->uuid]),
        );
    }

    public function test_a_required_group_must_be_answered(): void
    {
        $this->expectApiError(
            ApiErrorCode::ModifierRequired,
            fn () => $this->priceOf($this->menu['large']->uuid),
        );
    }

    public function test_a_two_of_four_group_says_how_many_are_missing(): void
    {
        $sides = MenuFixtures::group($this->restaurant, 'Pick your sides', 2, 4);
        $chutney = MenuFixtures::option($sides, 'Mint chutney');
        MenuFixtures::option($sides, 'Onion salad');
        MenuFixtures::attach($this->menu['item'], $sides, 2);

        // One of the two. A different code from "you chose none", because the
        // sentence on screen is different.
        $this->expectApiError(
            ApiErrorCode::ModifierMinNotMet,
            fn () => $this->priceOf(
                $this->menu['large']->uuid,
                [$this->menu['mild']->uuid, $chutney->uuid],
            ),
        );
    }

    public function test_choosing_more_than_the_maximum_is_refused(): void
    {
        $third = MenuFixtures::option($this->menu['extras'], 'Extra Paneer', 6_000, ['order' => 2]);

        $this->expectApiError(
            ApiErrorCode::ModifierMaxExceeded,
            fn () => $this->priceOf($this->menu['large']->uuid, [
                $this->menu['mild']->uuid,
                $this->menu['cheese']->uuid,
                $this->menu['jalapeno']->uuid,
                $third->uuid,
            ]),
        );
    }

    public function test_two_answers_to_a_single_select_group_are_refused(): void
    {
        $this->expectApiError(
            ApiErrorCode::ModifierMaxExceeded,
            fn () => $this->priceOf($this->menu['large']->uuid, [
                $this->menu['mild']->uuid,
                $this->menu['hot']->uuid,
            ]),
        );
    }

    public function test_an_optional_group_may_be_left_alone(): void
    {
        // Spice is required; extras are not. Answering only the first is valid.
        $this->assertSame(32_900, $this->priceOf(
            $this->menu['large']->uuid,
            [$this->menu['mild']->uuid],
        ));
    }

    public function test_an_option_from_another_restaurant_is_refused(): void
    {
        $other = MenuFixtures::configurableItem(
            RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites'),
        );

        $this->expectApiError(
            ApiErrorCode::ModifierInvalid,
            fn () => $this->priceOf($this->menu['large']->uuid, [
                $this->menu['mild']->uuid,
                $other['cheese']->uuid,
            ]),
        );
    }

    public function test_an_option_from_a_group_this_item_does_not_ask_is_refused(): void
    {
        // A group of the *same* restaurant, never attached to this dish. The
        // lookup is built from the dish's own groups, so it is not there.
        $sauces = MenuFixtures::group($this->restaurant, 'Choose a sauce', 0, 1);
        $garlic = MenuFixtures::option($sauces, 'Garlic', 3_000);

        $this->expectApiError(
            ApiErrorCode::ModifierInvalid,
            fn () => $this->priceOf($this->menu['large']->uuid, [
                $this->menu['mild']->uuid,
                $garlic->uuid,
            ]),
        );
    }

    public function test_an_unavailable_option_is_refused(): void
    {
        $this->menu['cheese']->forceFill(['is_available' => false])->save();

        $this->expectApiError(
            ApiErrorCode::ModifierUnavailable,
            fn () => $this->priceOf($this->menu['large']->uuid, [
                $this->menu['mild']->uuid,
                $this->menu['cheese']->uuid,
            ]),
        );
    }

    public function test_a_sold_out_item_cannot_be_configured(): void
    {
        $this->menu['item']->forceFill([
            'stock_status' => MenuItemStockStatus::SoldOut->value,
        ])->save();

        $this->expectApiError(
            ApiErrorCode::ItemSoldOut,
            fn () => $this->priceOf($this->menu['large']->uuid, [$this->menu['mild']->uuid]),
        );
    }

    public function test_a_withdrawn_item_reads_as_not_found(): void
    {
        $this->menu['item']->forceFill(['is_active' => false])->save();

        // Not "unavailable": an active dish and a withdrawn one must look the
        // same to anybody probing ids.
        $this->expectApiError(
            ApiErrorCode::ItemNotFound,
            fn () => $this->priceOf($this->menu['large']->uuid, [$this->menu['mild']->uuid]),
        );
    }

    // --- quantity and notes --------------------------------------------------

    public function test_a_quantity_below_one_is_refused(): void
    {
        foreach ([0, -1, -999] as $quantity) {
            $this->expectApiError(
                ApiErrorCode::QuantityInvalid,
                fn () => $this->priceOf($this->menu['large']->uuid, [$this->menu['mild']->uuid], $quantity),
            );
        }
    }

    public function test_a_quantity_above_the_ceiling_is_refused(): void
    {
        $max = (int) config('foodonthego.cart.max_quantity_per_line');

        $this->expectApiError(
            ApiErrorCode::QuantityLimitExceeded,
            fn () => $this->priceOf($this->menu['large']->uuid, [$this->menu['mild']->uuid], $max + 1),
        );

        // And the ceiling itself is allowed.
        $this->assertGreaterThan(0, $this->priceOf(
            $this->menu['large']->uuid,
            [$this->menu['mild']->uuid],
            $max,
        ));
    }

    public function test_an_oversized_note_is_refused(): void
    {
        $max = (int) config('foodonthego.cart.max_special_instructions');

        $this->expectApiError(
            ApiErrorCode::SpecialInstructionsTooLong,
            fn () => $this->validator->validate(
                $this->item(),
                CustomizationSelection::of(
                    itemUuid: $this->item()->uuid,
                    variantUuid: $this->menu['large']->uuid,
                    optionUuids: [$this->menu['mild']->uuid],
                    specialInstructions: str_repeat('a', $max + 1),
                ),
            ),
        );
    }

    public function test_a_note_is_counted_in_characters_not_bytes(): void
    {
        $max = (int) config('foodonthego.cart.max_special_instructions');

        // Devanagari at the limit. Counting bytes would refuse this at roughly
        // a third of the length an English note is allowed.
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                variantUuid: $this->menu['large']->uuid,
                optionUuids: [$this->menu['mild']->uuid],
                specialInstructions: str_repeat('क', $max),
            ),
        );

        $this->assertSame($max, mb_strlen((string) $resolved->specialInstructions));
    }

    // --- the price quote -----------------------------------------------------

    public function test_a_price_that_has_gone_up_since_the_screen_loaded_is_refused(): void
    {
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                variantUuid: $this->menu['large']->uuid,
                optionUuids: [$this->menu['mild']->uuid],
            ),
        );

        $priced = $this->pricing->price($resolved);

        // The customer was shown ₹249; the dish is now ₹329.
        $this->expectApiError(
            ApiErrorCode::PriceUpdated,
            fn () => $this->pricing->assertQuoteStillHolds($priced, 24_900),
        );
    }

    public function test_a_price_that_has_come_down_is_simply_charged(): void
    {
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                variantUuid: $this->menu['large']->uuid,
                optionUuids: [$this->menu['mild']->uuid],
            ),
        );

        $priced = $this->pricing->price($resolved);

        // Nobody needs a confirmation dialogue to be charged less.
        $this->pricing->assertQuoteStillHolds($priced, 39_900);

        $this->assertSame(32_900, $priced->unitPrice->minor);
    }

    public function test_a_client_that_quotes_nothing_gets_the_server_price(): void
    {
        $resolved = $this->validator->validate(
            $this->item(),
            CustomizationSelection::of(
                itemUuid: $this->item()->uuid,
                variantUuid: $this->menu['large']->uuid,
                optionUuids: [$this->menu['mild']->uuid],
            ),
        );

        $priced = $this->pricing->price($resolved);
        $this->pricing->assertQuoteStillHolds($priced, null);

        $this->assertSame(32_900, $priced->unitPrice->minor);
    }

    // --- canonical configuration ---------------------------------------------

    public function test_option_order_does_not_change_the_configuration(): void
    {
        $a = CustomizationSelection::of(
            itemUuid: 'item',
            optionUuids: ['cheese', 'jalapeno'],
        );

        $b = CustomizationSelection::of(
            itemUuid: 'item',
            optionUuids: ['jalapeno', 'cheese'],
        );

        // Cheese-then-jalapeño is the same order as jalapeño-then-cheese, and
        // adding it twice must increment a line rather than grow a second.
        $this->assertSame($a->fingerprint(), $b->fingerprint());
    }

    public function test_a_different_note_is_a_different_configuration(): void
    {
        $a = CustomizationSelection::of(itemUuid: 'item', specialInstructions: 'No onion');
        $b = CustomizationSelection::of(itemUuid: 'item', specialInstructions: 'Extra onion');

        // Not a detail the kitchen can merge.
        $this->assertNotSame($a->fingerprint(), $b->fingerprint());
    }

    public function test_quantity_is_not_part_of_the_configuration(): void
    {
        $a = CustomizationSelection::of(itemUuid: 'item', quantity: 1);
        $b = CustomizationSelection::of(itemUuid: 'item', quantity: 3);

        // Two of a thing and three of a thing are the same thing.
        $this->assertSame($a->fingerprint(), $b->fingerprint());
    }

    public function test_a_repeated_option_is_counted_once(): void
    {
        // A client that sends the same option twice has a bug, not a doubled
        // portion. De-duplicated rather than refused: the intent is plain.
        $selection = CustomizationSelection::of(
            itemUuid: $this->item()->uuid,
            variantUuid: $this->menu['large']->uuid,
            optionUuids: [
                $this->menu['mild']->uuid,
                $this->menu['cheese']->uuid,
                $this->menu['cheese']->uuid,
            ],
        );

        $priced = $this->pricing->price($this->validator->validate($this->item(), $selection));

        $this->assertSame(36_900, $priced->unitPrice->minor);
    }

    private function expectApiError(ApiErrorCode $expected, callable $body): void
    {
        try {
            $body();
        } catch (ApiException $e) {
            $this->assertSame($expected, $e->errorCode, "Expected {$expected->value}, got {$e->errorCode->value}");

            return;
        }

        $this->fail("Expected {$expected->value}, but nothing was thrown.");
    }
}
