<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Tenancy;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Enums\TenantRole;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Tenancy\TenantAccessService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\Support\TenancyFixtures;
use Tests\TestCase;

/**
 * Cross-tenant isolation, tested the only way it can be: over HTTP, with a real
 * token, substituting an identifier that belongs to somebody else.
 *
 * Two restaurants and five people. Priya manages the Spice Kitchen; Vikram
 * manages the Coast Cafe; Arjun owns the Spice Kitchen; Meera is a super
 * administrator; Rahul is a customer. Every test below is some version of "can
 * one of them reach something that is not theirs", and the answer is always the
 * same 404 a stranger gets.
 *
 * The tests worth reading twice are the indirect ones. A menu item fetched by its
 * own id names no restaurant anywhere in the request, so nothing in the request
 * can be trusted to scope one — and the obvious implementation passes every test
 * about menu items while handing one restaurant's prices to another.
 */
final class TenantIsolationTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $spice;

    private Restaurant $coast;

    private User $priya;   // manager at Spice

    private User $vikram;  // manager at Coast

    private User $arjun;   // owner at Spice

    private MenuItem $spiceItem;

    private MenuItem $coastItem;

    protected function setUp(): void
    {
        parent::setUp();

        $this->spice = RestaurantFixtures::nearRoute(0.4, 800, 'Spice Kitchen');
        $this->coast = RestaurantFixtures::nearRoute(0.6, 900, 'Coast Cafe');

        $this->priya = TenancyFixtures::operator('Priya', '+919999911001');
        $this->vikram = TenancyFixtures::operator('Vikram', '+919999911002');
        $this->arjun = TenancyFixtures::operator('Arjun', '+919999911003', Role::RestaurantOwner);

        TenancyFixtures::assign($this->priya, $this->spice, TenantRole::Manager);
        TenancyFixtures::assign($this->vikram, $this->coast, TenantRole::Manager);
        TenancyFixtures::assign($this->arjun, $this->spice, TenantRole::Owner);

        $this->spiceItem = MenuFixtures::item(
            MenuFixtures::category($this->spice, 'Mains'), 'Paneer Tikka', 24_900,
        );
        $this->coastItem = MenuFixtures::item(
            MenuFixtures::category($this->coast, 'Mains'), 'Prawn Curry', 39_900,
        );
    }

    private function as(User $user): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.TenancyFixtures::tokenFor($user));
    }

    // --- reading a list -------------------------------------------------------

    public function test_an_operator_sees_only_the_tenants_they_are_assigned_to(): void
    {
        $body = $this->as($this->priya)
            ->getJson('/api/v1/restaurant/restaurants')
            ->assertOk()
            ->json('data.restaurants');

        $this->assertCount(1, $body);
        $this->assertSame('Spice Kitchen', $body[0]['name']);

        // Not merely "the right one is present". The other must be absent, and a
        // test that only checked presence would pass on a list of everything.
        $this->assertNotContains('Coast Cafe', array_column($body, 'name'));
    }

    public function test_an_operator_with_no_assignment_sees_nothing(): void
    {
        $nobody = TenancyFixtures::operator('Nobody', '+919999911009');

        $body = $this->as($nobody)
            ->getJson('/api/v1/restaurant/restaurants')
            ->assertOk()
            ->json('data.restaurants');

        $this->assertSame([], $body);
    }

    // --- reading one ----------------------------------------------------------

    public function test_an_operator_can_read_their_own_tenant(): void
    {
        $this->as($this->priya)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid)
            ->assertOk()
            ->assertJsonPath('data.restaurant.name', 'Spice Kitchen')
            ->assertJsonPath('data.restaurant.capability', 'manager');
    }

    public function test_one_tenants_manager_cannot_read_another_tenant(): void
    {
        // The plain cross-tenant read. Vikram holds a valid session, a valid
        // role, and a real restaurant's identifier. Only the assignment is
        // missing, and that is the whole boundary.
        $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid)
            ->assertNotFound();
    }

    public function test_a_foreign_tenant_and_a_nonexistent_one_answer_identically(): void
    {
        $foreign = $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid);

        $imaginary = $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/restaurants/'.Str::uuid());

        $foreign->assertNotFound();
        $imaginary->assertNotFound();

        // The point of a 404 over a 403: the difference between "not yours" and
        // "not real" is exactly what somebody enumerating identifiers is trying
        // to learn, and here there is no difference to read.
        $this->assertSame(
            $imaginary->json('error.code'),
            $foreign->json('error.code'),
        );
        $this->assertSame(
            $imaginary->json('error.message'),
            $foreign->json('error.message'),
        );
    }

    // --- writing --------------------------------------------------------------

    public function test_an_operator_can_change_their_own_tenants_settings(): void
    {
        $this->as($this->priya)
            ->patchJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid, [
                'is_accepting_orders' => false,
            ])
            ->assertOk()
            ->assertJsonPath('data.restaurant.is_accepting_orders', false);

        $this->assertFalse((bool) $this->spice->fresh()->is_accepting_orders);
    }

    public function test_one_tenants_manager_cannot_write_to_another_tenant(): void
    {
        $before = (bool) $this->spice->is_accepting_orders;

        $this->as($this->vikram)
            ->patchJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid, [
                'is_accepting_orders' => false,
            ])
            ->assertNotFound();

        // Read from the database, not from the response. A refusal that still
        // wrote the row would be the worst possible outcome and the response
        // would look identical.
        $this->assertSame($before, (bool) $this->spice->fresh()->is_accepting_orders);
    }

    public function test_staff_may_read_but_not_change_operational_settings(): void
    {
        $cook = TenancyFixtures::operator('Cook', '+919999911004', Role::RestaurantStaff);
        TenancyFixtures::assign($cook, $this->spice, TenantRole::Staff);

        $this->as($cook)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid)
            ->assertOk();

        // Reachability and depth are different questions. This is a 403, not a
        // 404: the restaurant is theirs, the action is not.
        $this->as($cook)
            ->patchJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid, [
                'is_accepting_orders' => false,
            ])
            ->assertForbidden();
    }

    // --- the indirect path ----------------------------------------------------

    public function test_a_menu_item_reached_by_its_own_id_is_still_tenant_scoped(): void
    {
        // Nothing in this request names a restaurant. The obvious implementation
        // — where('uuid', $uuid)->first() — returns the row, and this is the test
        // that says so.
        $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/menu/items/'.$this->spiceItem->uuid)
            ->assertNotFound();

        // And the control: the same route, the same shape, their own item.
        $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/menu/items/'.$this->coastItem->uuid)
            ->assertOk()
            ->assertJsonPath('data.item.name', 'Prawn Curry');
    }

    public function test_a_menu_list_cannot_be_read_through_a_foreign_restaurant_id(): void
    {
        $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid.'/menu/items')
            ->assertNotFound();

        $mine = $this->as($this->vikram)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->coast->uuid.'/menu/items')
            ->assertOk()
            ->json('data.items');

        $this->assertSame(['Prawn Curry'], array_column($mine, 'name'));
    }

    // --- revocation -----------------------------------------------------------

    public function test_a_revoked_assignment_grants_nothing(): void
    {
        $temp = TenancyFixtures::operator('Temp', '+919999911005');
        TenancyFixtures::assign($temp, $this->spice, TenantRole::Manager, status: 'revoked');

        $this->as($temp)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid)
            ->assertNotFound();

        $this->assertSame([], $this->as($temp)
            ->getJson('/api/v1/restaurant/restaurants')
            ->json('data.restaurants'));
    }

    public function test_a_deactivated_account_reaches_nothing_it_was_assigned_to(): void
    {
        // The other half of `accountUsable`. `status` and `is_active` are
        // separate switches that disagree in practice, and a test for one proves
        // nothing about the other.
        $this->priya->forceFill(['is_active' => false])->save();

        $this->as($this->priya)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid)
            ->assertNotFound();
    }

    public function test_a_suspended_account_reaches_nothing_it_was_assigned_to(): void
    {
        // The assignment is untouched and still says 'active'. The account is
        // not. KI-008 records that a token outlives a suspension; this is what
        // stops that token still reaching a restaurant.
        $this->priya->forceFill(['status' => AccountStatus::Suspended->value])->save();

        $this->as($this->priya)
            ->getJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid)
            ->assertNotFound();
    }

    // --- the surface gate -----------------------------------------------------

    public function test_a_customer_account_cannot_reach_the_restaurant_surface(): void
    {
        $rahul = CustomerFactory::rahul();

        $this->as($rahul)
            ->getJson('/api/v1/restaurant/restaurants')
            ->assertForbidden();
    }

    public function test_an_assignment_does_not_promote_a_customer_account(): void
    {
        // The subtle one. A row in restaurant_user is not, by itself, a way in:
        // the surface gate is checked as well as the assignment, so a mistaken
        // or malicious insert grants nothing.
        $rahul = CustomerFactory::rahul();
        TenancyFixtures::assign($rahul, $this->spice, TenantRole::Owner);

        $this->as($rahul)
            ->getJson('/api/v1/restaurant/restaurants')
            ->assertForbidden();

        // And the service agrees, independently of the middleware — so a future
        // route that forgets the role gate is still refused.
        $access = app(TenantAccessService::class);
        $this->assertNull($access->capabilityFor($rahul->fresh(), $this->spice));
    }

    // --- platform accounts ----------------------------------------------------

    public function test_a_super_administrator_with_no_grant_reaches_nothing(): void
    {
        $meera = TenancyFixtures::operator('Meera', '+919999911006', Role::SuperAdmin);

        $body = $this->as($meera)
            ->getJson('/api/v1/admin/restaurants')
            ->assertOk()
            ->json('data');

        // The assertion this whole design turns on. "May access multiple tenants
        // according to RBAC" is not "may access all tenants implicitly", and the
        // day somebody adds a policy before() hook this is the test that fails.
        $this->assertSame([], $body['restaurants']);
        $this->assertSame('granted', $body['scope']);
    }

    public function test_a_super_administrator_reaches_exactly_what_they_are_granted(): void
    {
        $meera = TenancyFixtures::operator('Meera', '+919999911006', Role::SuperAdmin);
        TenancyFixtures::grant($meera, $this->spice, TenantRole::Staff);

        $body = $this->as($meera)
            ->getJson('/api/v1/admin/restaurants')
            ->assertOk()
            ->json('data.restaurants');

        $this->assertSame(['Spice Kitchen'], array_column($body, 'name'));
    }

    public function test_a_platform_wide_grant_reaches_every_tenant(): void
    {
        $meera = TenancyFixtures::operator('Meera', '+919999911006', Role::SuperAdmin);
        TenancyFixtures::grant($meera, null, TenantRole::Owner);

        $body = $this->as($meera)
            ->getJson('/api/v1/admin/restaurants')
            ->assertOk()
            ->json('data');

        $this->assertSame('all', $body['scope']);
        $this->assertEqualsCanonicalizing(
            ['Coast Cafe', 'Spice Kitchen'],
            array_column($body['restaurants'], 'name'),
        );
    }

    public function test_a_revoked_platform_grant_reaches_nothing(): void
    {
        $meera = TenancyFixtures::operator('Meera', '+919999911006', Role::SuperAdmin);
        TenancyFixtures::grant($meera, null, TenantRole::Owner, status: 'revoked');

        $this->assertSame([], $this->as($meera)
            ->getJson('/api/v1/admin/restaurants')
            ->json('data.restaurants'));
    }

    public function test_a_support_agent_granted_one_tenant_cannot_reach_the_other(): void
    {
        $support = TenancyFixtures::operator('Sam', '+919999911007', Role::SupportAgent);
        TenancyFixtures::grant($support, $this->coast, TenantRole::Staff);

        $names = array_column($this->as($support)
            ->getJson('/api/v1/admin/restaurants')
            ->assertOk()
            ->json('data.restaurants'), 'name');

        $this->assertSame(['Coast Cafe'], $names);
    }

    // --- depth ----------------------------------------------------------------

    public function test_an_owner_holds_everything_a_manager_does(): void
    {
        $this->as($this->arjun)
            ->patchJson('/api/v1/restaurant/restaurants/'.$this->spice->uuid, [
                'is_accepting_orders' => false,
            ])
            ->assertOk();
    }

    public function test_capability_is_the_stronger_of_assignment_and_grant(): void
    {
        // Somebody who both works for the platform and runs a restaurant. The
        // stronger of the two applies, and it is worked out by the enum's own
        // ordering rather than by a comparison written twice.
        $both = TenancyFixtures::operator('Both', '+919999911008', Role::Admin);
        TenancyFixtures::grant($both, $this->spice, TenantRole::Staff);

        // Refreshed on purpose. A model straight from `create()` has not read
        // back the columns the database defaulted, and asserting against one
        // that has not round-tripped is asserting about PHP rather than about
        // the row an HTTP request would load.
        $both->refresh();

        $access = app(TenantAccessService::class);

        $this->assertSame(TenantRole::Staff, $access->capabilityFor($both, $this->spice));
        $this->assertFalse($access->allows($both, $this->spice, TenantRole::Manager));
    }
}
