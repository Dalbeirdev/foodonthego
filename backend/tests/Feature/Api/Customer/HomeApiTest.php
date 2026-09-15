<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Trip;
use App\Models\User;
use App\Services\Places\PlaceProvider;
use App\Services\Routing\RouteProvider;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * GET /api/v1/customer/home.
 *
 * The endpoint exists to save round trips on a connection belonging to someone
 * driving, so most of these tests are about what it must NOT do: not leak
 * another customer's journey, not answer an unauthenticated request, not call a
 * paid provider, and not turn "nothing is happening" into an error.
 */
final class HomeApiTest extends TestCase
{
    use RefreshDatabase;

    private function home(User $customer): TestResponse
    {
        return $this->withToken(CustomerFactory::tokenFor($customer))
            ->getJson('/api/v1/customer/home');
    }

    public function test_it_answers_with_every_section_home_needs(): void
    {
        $response = $this->home(CustomerFactory::rahul());

        $response->assertOk()->assertJsonStructure([
            'data' => [
                'customer',
                'active_trip',
                'active_order',
                'notification_summary' => ['supported', 'unread'],
            ],
        ]);
    }

    public function test_a_customer_with_nothing_running_gets_nulls_not_an_error(): void
    {
        // The empty Home is the common case for a new customer, and it must be
        // a 200 the client renders an empty state from. Reporting it as an
        // error would put a retry button in front of somebody who has simply
        // not planned a journey yet.
        $response = $this->home(CustomerFactory::rahul());

        $response->assertOk();
        self::assertNull($response->json('data.active_trip'));
        self::assertNull($response->json('data.active_order'));
    }

    public function test_it_returns_the_callers_own_journey(): void
    {
        $rahul = CustomerFactory::rahul();
        $this->planJourneyFor($rahul);

        $response = $this->home($rahul);

        $response->assertOk();
        self::assertNotNull($response->json('data.active_trip'), 'The journey in progress is missing from Home.');
    }

    public function test_it_never_returns_another_customers_journey(): void
    {
        $rahul = CustomerFactory::rahul();
        $ananya = CustomerFactory::ananya();
        $this->planJourneyFor($ananya);

        // Rahul has no journey. Ananya does. Home is derived from the token,
        // so there is no id for Rahul to tamper with — which is the point of
        // asserting it: the absence of a parameter is the defence.
        $response = $this->home($rahul);

        $response->assertOk();
        self::assertNull(
            $response->json('data.active_trip'),
            'Home returned a journey belonging to a different customer.',
        );
    }

    public function test_it_refuses_an_unauthenticated_request(): void
    {
        $this->getJson('/api/v1/customer/home')->assertUnauthorized();
    }

    /**
     * Opening Home must not spend money.
     *
     * A customer parked at a service station may open the app a dozen times.
     * If Home resolved a route or a place on each load, that is a dozen billed
     * calls for a screen that displays what the server already knows. The
     * providers are replaced with doubles that fail the test if touched.
     */
    public function test_opening_home_calls_no_paid_provider(): void
    {
        $this->app->bind(RouteProvider::class, static function (): never {
            self::fail('Home called the routing provider. Opening a screen must not cost money.');
        });
        $this->app->bind(PlaceProvider::class, static function (): never {
            self::fail('Home called the places provider. Opening a screen must not cost money.');
        });

        $rahul = CustomerFactory::rahul();
        $this->planJourneyFor($rahul);

        $this->home($rahul)->assertOk();
    }

    /**
     * One request, and a small, bounded number of queries behind it.
     *
     * Not a fixed number — that would fail on an unrelated eager-load change
     * and teach everyone to raise the bound. A ceiling catches the thing worth
     * catching: a presenter fetching a restaurant per row, or a section added
     * later that queries in a loop.
     */
    public function test_it_answers_within_a_bounded_number_of_queries(): void
    {
        $rahul = CustomerFactory::rahul();
        $this->planJourneyFor($rahul);

        $queries = 0;
        DB::listen(static function () use (&$queries): void {
            $queries++;
        });

        $this->home($rahul)->assertOk();

        self::assertLessThan(
            15,
            $queries,
            "Home ran {$queries} queries. It exists to remove round trips, not to move them behind one.",
        );
    }

    public function test_notifications_report_themselves_as_unbuilt_rather_than_as_zero(): void
    {
        $response = $this->home(CustomerFactory::rahul());

        // A zero would render as "nothing waiting for you", which is a claim
        // this platform cannot make: there is no notifications table at all.
        self::assertFalse($response->json('data.notification_summary.supported'));
        self::assertNull($response->json('data.notification_summary.unread'));
    }

    public function test_the_greeting_name_comes_from_the_same_place_the_profile_screen_uses(): void
    {
        $rahul = CustomerFactory::rahul();

        $home = $this->home($rahul)->json('data.customer');
        $profile = $this->withToken(CustomerFactory::tokenFor($rahul))
            ->getJson('/api/v1/customer/profile')
            ->json('data');

        // Identical, so a field redacted on the profile screen is redacted on
        // Home without this endpoint knowing which fields those are.
        self::assertSame($profile, $home);
    }

    /**
     * Plans a journey through the same service the API uses.
     *
     * Not a raw Trip::create — the model guards uuid against mass assignment,
     * and a test that reaches around that guard stops exercising the path a
     * customer takes. The first attempt here did exactly that and was rejected
     * by the model, which is the guard doing its job.
     */
    private function planJourneyFor(User $customer): Trip
    {
        return app(TripService::class)->create(
            $customer,
            [
                'origin' => [
                    'source_type' => 'PLACE_SEARCH',
                    'display_name' => 'Delhi',
                    'formatted_address' => 'Delhi, India',
                    'latitude' => '28.613900',
                    'longitude' => '77.209000',
                ],
                'destination' => [
                    'source_type' => 'PLACE_SEARCH',
                    'display_name' => 'Jaipur',
                    'formatted_address' => 'Jaipur, Rajasthan, India',
                    'latitude' => '26.912400',
                    'longitude' => '75.787300',
                ],
            ],
            CarbonImmutable::now(),
        );
    }
}
