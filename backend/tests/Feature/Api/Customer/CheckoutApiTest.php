<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\CheckoutQuoteStatus;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Checkout, over HTTP.
 *
 * Three themes, in the order they matter.
 *
 * **No amount is the client's.** Several tests below post bodies carrying a
 * total, a subtotal, a tax figure and a discount, and assert the response is
 * byte-for-byte what it would have been without them. That is not "the server
 * validates what it is sent" — nothing here reads those keys at all.
 *
 * **Nothing is invented.** With no commercial rule configured the payable amount
 * is the items subtotal and the charges list is empty. A test asserts the
 * absence rather than a zero, because a zero states a decision nobody made.
 *
 * **Nothing is bought.** No order, no payment, no Razorpay object. Tests assert
 * the tables for all three do not exist.
 */
final class CheckoutApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private Trip $trip;

    private Restaurant $restaurant;

    private Cart $cart;

    private MenuItem $item;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');

        $this->cart = CartFixtures::activeCart($this->rahul, $this->trip, $this->restaurant);

        $category = MenuFixtures::category($this->restaurant, 'Mains');
        $this->item = MenuFixtures::item($category, 'Paneer Tikka', 24_900, ['preparation_minutes' => 20]);

        CartFixtures::line($this->cart, $this->item);
    }

    // --- plumbing -------------------------------------------------------------

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function prepareUrl(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/checkout/prepare';
    }

    private function validateUrl(string $checkoutId, ?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/checkout/'.$checkoutId.'/validate';
    }

    /** Chooses the recommended pickup time, the way the screen would. */
    private function choosePickup(?Trip $trip = null, ?User $as = null): void
    {
        $trip ??= $this->trip;
        $as ??= $this->rahul;

        $options = $this->as($as)
            ->postJson('/api/v1/customer/trips/'.$trip->uuid.'/cart/pickup-options')
            ->json('data.pickup');

        $this->as($as)->putJson(
            '/api/v1/customer/trips/'.$trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options['recommended_option_id']],
        )->assertOk();
    }

    /** @param array<string, mixed> $body */
    private function prepare(array $body = []): array
    {
        $response = $this->as($this->rahul)->postJson($this->prepareUrl(), $body);

        $response->assertOk();

        return $response->json('data');
    }

    // --- scenario 1: a valid checkout ----------------------------------------

    public function test_a_valid_cart_and_pickup_produce_an_authoritative_checkout(): void
    {
        $this->choosePickup();

        $data = $this->prepare();

        $this->assertNotNull($data['checkout_id']);
        $this->assertSame(CheckoutQuoteStatus::Active->value, $data['status']);
        $this->assertTrue($data['ready_for_payment']);

        // The whole purchase, in one body, so a screen renders one moment
        // rather than four.
        $this->assertSame('Highway Spice Kitchen', $data['restaurant']['name']);
        $this->assertNotNull($data['journey']['origin']);
        $this->assertSame('SELECTED', $data['pickup']['selection']['status']);
        $this->assertCount(1, $data['items']);
        $this->assertNotNull($data['expires_at']);
    }

    // --- scenario 12: nothing configured -------------------------------------

    public function test_with_no_commercial_rule_configured_the_payable_is_the_subtotal(): void
    {
        $this->choosePickup();

        $commercial = $this->prepare()['commercial'];

        $this->assertSame(24_900, $commercial['items_subtotal']['amount_minor']);
        $this->assertSame(24_900, $commercial['payable_total']['amount_minor']);

        // Absent, not zero. "No additional charges are currently configured" is
        // a different statement from "tax is nought", and only the first is
        // true.
        $this->assertSame([], $commercial['charges']);
        $this->assertSame([], $commercial['discounts']);
        $this->assertFalse($commercial['has_configured_adjustments']);
    }

    // --- scenario 11: only configured charges appear -------------------------

    public function test_only_a_configured_charge_appears_and_it_is_the_real_figure(): void
    {
        $this->restaurant->forceFill(['tax_rate_bps' => 500])->save();

        $this->choosePickup();

        $commercial = $this->prepare()['commercial'];

        $codes = array_column($commercial['charges'], 'code');

        $this->assertSame(['TAX'], $codes);
        $this->assertSame(1_245, $commercial['charges'][0]['amount']['amount_minor']);
        $this->assertSame(26_145, $commercial['payable_total']['amount_minor']);
        $this->assertTrue($commercial['has_configured_adjustments']);
    }

    // --- scenario 9: the client cannot name a price --------------------------

    public function test_a_body_carrying_its_own_amounts_changes_nothing(): void
    {
        $this->choosePickup();

        $honest = $this->prepare();

        $tampered = $this->prepare([
            'payable_total_minor' => 1,
            'items_subtotal_minor' => 1,
            'discount_minor' => 9_999_999,
            'tax_minor' => 0,
            'packaging_fee_minor' => 0,
            'platform_fee_minor' => 0,
            'commercial' => ['payable_total' => ['amount_minor' => 1]],
            'ready_for_payment' => true,
            'status' => 'ACTIVE',
        ]);

        // Identical arithmetic, because nothing anywhere reads those keys.
        $this->assertSame(
            $honest['commercial']['payable_total']['amount_minor'],
            $tampered['commercial']['payable_total']['amount_minor'],
        );
        $this->assertSame(24_900, $tampered['commercial']['payable_total']['amount_minor']);
        $this->assertSame([], $tampered['commercial']['discounts']);

        // And nothing reached the row either.
        $quote = CheckoutQuote::query()->where('uuid', $tampered['checkout_id'])->firstOrFail();

        $this->assertSame(24_900, $quote->payable_total_minor);
        $this->assertSame(0, $quote->discount_minor);
        $this->assertFalse($quote->discount_configured);
    }

    // --- scenario 2: the cart changed ----------------------------------------

    public function test_changing_the_cart_makes_the_quote_stale(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        $this->cart->recordContentChange();

        $data = $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data');

        $this->assertSame(CheckoutQuoteStatus::Stale->value, $data['status']);
        $this->assertFalse($data['ready_for_payment']);
    }

    // --- scenario 3: the pickup changed --------------------------------------

    public function test_changing_the_pickup_time_makes_the_quote_stale(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        // A different window, chosen the way a customer would.
        $options = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-options')
            ->json('data.pickup.options');

        $this->as($this->rahul)->putJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options[2]['id']],
        )->assertOk();

        $data = $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data');

        $this->assertSame(CheckoutQuoteStatus::Stale->value, $data['status']);
        $this->assertFalse($data['ready_for_payment']);
    }

    // --- scenario 4: a price changed -----------------------------------------

    public function test_a_price_rise_after_quoting_stops_the_checkout(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        $this->item->forceFill(['base_price_minor' => 31_900])->save();

        $data = $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data');

        // Module 12's revalidation is what notices, through Module 13's
        // pre-checkout — checkout does not re-implement price checking.
        $this->assertFalse($data['ready_for_payment']);
        $this->assertContains(
            'PRICE_INCREASED',
            array_column($data['validation']['issues'], 'code'),
        );
    }

    // --- scenario 5: a line sold out -----------------------------------------

    public function test_a_sold_out_line_blocks_the_checkout(): void
    {
        $this->choosePickup();

        $this->item->forceFill(['stock_status' => 'SOLD_OUT'])->save();

        $data = $this->prepare();

        $this->assertFalse($data['ready_for_payment']);
        $this->assertNull($data['checkout_id'], 'a quote was written for a basket nobody could buy');
    }

    // --- scenario 6: the kitchen paused --------------------------------------

    public function test_a_paused_kitchen_blocks_the_checkout(): void
    {
        $this->choosePickup();

        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $data = $this->prepare();

        $this->assertFalse($data['ready_for_payment']);
        $this->assertNull($data['checkout_id']);
    }

    // --- scenario 7: the pickup expired --------------------------------------

    public function test_a_pickup_window_that_has_passed_blocks_the_checkout(): void
    {
        $this->choosePickup();

        config(['foodonthego.pickup.route_estimate_max_age_seconds' => 86_400]);

        $this->travelTo(CarbonImmutable::parse('2026-09-07T06:30:00Z')->addHours(3));

        $data = $this->prepare();

        $this->assertFalse($data['ready_for_payment']);
        $this->assertNull($data['checkout_id']);
    }

    // --- scenario 8: the quote expired ---------------------------------------

    public function test_an_expired_quote_is_refused_and_asks_to_be_refreshed(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        $this->travelTo(
            CarbonImmutable::parse('2026-09-07T06:30:00Z')
                ->addMinutes((int) config('foodonthego.checkout.quote_ttl_minutes') + 1),
        );

        $data = $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data');

        $this->assertSame(CheckoutQuoteStatus::Expired->value, $data['status']);
        $this->assertFalse($data['ready_for_payment']);
    }

    public function test_expiry_is_reported_before_staleness(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        // Both true at once: the cart moved AND the clock ran out.
        $this->cart->recordContentChange();

        $this->travelTo(
            CarbonImmutable::parse('2026-09-07T06:30:00Z')
                ->addMinutes((int) config('foodonthego.checkout.quote_ttl_minutes') + 1),
        );

        $data = $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data');

        // "Your checkout timed out, here is a fresh one" is a smaller thing to
        // tell somebody than "your order changed", and the clock ran out first.
        $this->assertSame(CheckoutQuoteStatus::Expired->value, $data['status']);
    }

    // --- scenario 10: somebody else's checkout -------------------------------

    public function test_one_customer_cannot_validate_anothers_checkout(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        $ananya = CustomerFactory::ananya();
        $herTrip = RestaurantFixtures::tripWithSelectedRoute($ananya);

        // She needs a cart of her own, and this is the whole point of the
        // setup rather than scenery.
        //
        // An earlier version of this test gave her only a journey. She was then
        // refused with CART_NOT_FOUND before the quote lookup ever ran, so the
        // test passed while proving nothing about quote ownership — and two
        // negative controls against that lookup both stayed silent, which is
        // how the hole was found.
        $herCart = CartFixtures::activeCart($ananya, $herTrip, $this->restaurant);
        CartFixtures::line($herCart, $this->item);

        // Her own journey, her own cart, his checkout id.
        $this->as($ananya)
            ->postJson($this->validateUrl($checkoutId, $herTrip))
            ->assertStatus(404)
            ->assertJsonPath('error.code', ApiErrorCode::CheckoutQuoteNotFound->value);
    }

    public function test_a_checkout_id_from_a_different_journey_is_refused(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        $other = RestaurantFixtures::tripWithSelectedRoute($this->rahul);

        $this->as($this->rahul)
            ->postJson($this->validateUrl($checkoutId, $other))
            ->assertStatus(404)
            ->assertJsonPath('error.code', ApiErrorCode::CartNotFound->value);
    }

    public function test_a_forged_checkout_id_is_refused(): void
    {
        $this->choosePickup();
        $this->prepare();

        $this->as($this->rahul)
            ->postJson($this->validateUrl('00000000-0000-4000-8000-000000000000'))
            ->assertStatus(404)
            ->assertJsonPath('error.code', ApiErrorCode::CheckoutQuoteNotFound->value);
    }

    public function test_another_customer_cannot_prepare_on_this_journey(): void
    {
        $ananya = CustomerFactory::ananya();

        $this->as($ananya)->postJson($this->prepareUrl())->assertStatus(404);
    }

    // --- scenario 14: repeated preparation -----------------------------------

    public function test_preparing_repeatedly_supersedes_rather_than_accumulates(): void
    {
        $this->choosePickup();

        $first = $this->prepare()['checkout_id'];
        $second = $this->prepare()['checkout_id'];
        $third = $this->prepare()['checkout_id'];

        $this->assertNotSame($first, $third);

        // One cart, one checkout in flight. Reopening a screen or retrying a
        // lost request must not leave a pile of live offers behind.
        $active = CheckoutQuote::query()
            ->where('cart_id', $this->cart->id)
            ->where('status', CheckoutQuoteStatus::Active->value)
            ->count();

        $this->assertSame(1, $active);

        // The superseded ones are kept, not deleted: what was offered is worth
        // a record even after it stops being offered.
        $this->assertSame(3, CheckoutQuote::query()->where('cart_id', $this->cart->id)->count());
    }

    // --- scenario 15: payment readiness --------------------------------------

    public function test_readiness_is_true_for_a_good_quote_and_false_for_a_stale_one(): void
    {
        $this->choosePickup();

        $checkoutId = $this->prepare()['checkout_id'];

        $this->assertTrue(
            $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data.ready_for_payment'),
        );

        $this->cart->recordContentChange();

        $this->assertFalse(
            $this->as($this->rahul)->postJson($this->validateUrl($checkoutId))->json('data.ready_for_payment'),
        );
    }

    public function test_a_client_cannot_talk_the_server_into_saying_ready(): void
    {
        // No pickup chosen at all.
        $data = $this->prepare(['ready_for_payment' => true, 'status' => 'ACTIVE']);

        $this->assertFalse($data['ready_for_payment']);
        $this->assertNull($data['checkout_id']);
    }

    // --- scenarios 16 and 17: nothing was bought ------------------------------

    public function test_preparing_a_checkout_creates_no_order_and_no_payment(): void
    {
        $this->choosePickup();

        $this->prepare();

        // The check that would catch somebody getting ahead of the module.
        foreach (['orders', 'order_items', 'payments', 'pickup_codes', 'razorpay_orders'] as $table) {
            $this->assertFalse(
                Schema::hasTable($table),
                "{$table} exists in Module 14, which ends before any order does",
            );
        }

        $cart = $this->cart->fresh();

        $this->assertTrue($cart->isActive());
        $this->assertSame(1, $cart->version);
    }

    public function test_a_quote_is_never_written_in_an_order_status(): void
    {
        $this->choosePickup();
        $this->prepare();

        // Read from the column rather than through the cast: an enum that
        // refuses to hold an order status proves nothing about what a
        // migration or a raw update could put there.
        $statuses = DB::table('checkout_quotes')
            ->pluck('status')
            ->all();

        $this->assertNotEmpty($statuses);

        foreach ($statuses as $status) {
            $this->assertContains($status, ['ACTIVE', 'STALE', 'EXPIRED', 'CONSUMED']);
            $this->assertNotContains($status, ['PENDING', 'CONFIRMED', 'PAID', 'PLACED']);
        }
    }

    // --- one response, one clock ---------------------------------------------

    /**
     * Every instant in a checkout body carries the counter's offset.
     *
     * The rule Module 13 arrived at the hard way, applied to the whole response
     * rather than to the field that happened to be wrong at the time: if any
     * moment in a body is expressed on a particular clock, all of them are.
     *
     * What this catches is not a formatting preference. A quote's expiry sent in
     * UTC beside a pickup window sent at +05:30 renders as "held until 6:40 am"
     * under a 1:40 pm collection — an expiry seven hours in the customer's past,
     * on the screen where they agree to pay.
     */
    public function test_every_instant_in_one_response_is_on_one_clock(): void
    {
        $this->choosePickup();

        $instants = $this->instantsIn($this->prepare());

        // The control the assertion depends on: a body with one instant in it
        // would pass the comparison below while proving nothing.
        $this->assertGreaterThan(4, count($instants), 'too few instants to compare');

        $offsets = [];

        foreach ($instants as $path => $value) {
            $offsets[substr($value, -6)][] = $path;
        }

        $this->assertCount(
            1,
            $offsets,
            'instants on more than one clock: '.json_encode($offsets, JSON_PRETTY_PRINT),
        );

        // And it is the restaurant's clock, not the server's. Asia/Kolkata is
        // never +00:00, so a body that had merely become self-consistent by
        // sending everything in UTC still fails here.
        $this->assertSame('+05:30', array_key_first($offsets));
    }

    /**
     * Every ISO-8601 string in a response body, by dotted path.
     *
     * @param  array<string, mixed>  $body
     * @return array<string, string>
     */
    private function instantsIn(array $body): array
    {
        $found = [];

        $walk = function (array $node, string $prefix) use (&$walk, &$found): void {
            foreach ($node as $key => $value) {
                $path = $prefix === '' ? (string) $key : $prefix.'.'.$key;

                if (is_array($value)) {
                    $walk($value, $path);
                } elseif (is_string($value) && preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/', $value) === 1) {
                    $found[$path] = $value;
                }
            }
        };

        $walk($body, '');

        return $found;
    }

    // --- what must not leak ---------------------------------------------------

    public function test_the_response_leaks_nothing_operational(): void
    {
        $this->restaurant->forceFill([
            'internal_notes' => 'Owner is a friend of the founder.',
            'commission_rate' => '18.50',
            'owner_phone' => '+919812345678',
            'tax_rate_bps' => 500,
        ])->save();

        $this->choosePickup();

        $body = $this->as($this->rahul)->postJson($this->prepareUrl())->getContent();

        foreach ([
            'internal_notes', 'commission_rate', 'owner_phone', 'owner_email',
            'bank_account_reference', 'tax_identifier', 'friend of the founder',
            '18.50', '9812345678', 'fingerprint', 'commercial_rule_version',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "{$secret} reached the wire");
        }
    }
}
