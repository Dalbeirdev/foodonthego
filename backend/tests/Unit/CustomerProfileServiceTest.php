<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use App\Services\Profile\CustomerProfileService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

final class CustomerProfileServiceTest extends TestCase
{
    use RefreshDatabase;

    private CustomerProfileService $service;

    private User $rahul;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = $this->app->make(CustomerProfileService::class);
        $this->rahul = CustomerFactory::rahul();
    }

    public function test_it_updates_the_fields_a_customer_owns(): void
    {
        $updated = $this->service->update($this->rahul, [
            'first_name' => 'Rahul',
            'last_name' => 'S. Sharma',
            'email' => 'new@example.com',
        ]);

        $this->assertSame('Rahul', $updated->first_name);
        $this->assertSame('S. Sharma', $updated->last_name);
        $this->assertSame('new@example.com', $updated->email);
    }

    public function test_a_field_that_was_not_sent_is_left_alone(): void
    {
        $this->service->update($this->rahul, ['first_name' => 'Rahul Kumar']);

        // PATCH semantics: omitting a field means "leave it", which is not the
        // same as sending null.
        $this->assertSame('Sharma', $this->rahul->fresh()->last_name);
        $this->assertSame('rahul.test@foodonthego.example', $this->rahul->fresh()->email);
    }

    public function test_a_blank_optional_field_is_cleared_rather_than_stored_empty(): void
    {
        $updated = $this->service->update($this->rahul, ['last_name' => '  ', 'email' => '']);

        // "" is not a surname, and storing one makes every later
        // `last_name !== null` check wrong.
        $this->assertNull($updated->last_name);
        $this->assertNull($updated->email);
    }

    public function test_it_never_touches_identity_or_privilege_even_if_asked(): void
    {
        $originalPhone = $this->rahul->phone_e164;
        $originalVerifiedAt = $this->rahul->phone_verified_at;

        // The service reads three keys by name, so these are inert whatever a
        // caller sends.
        $this->service->update($this->rahul, [
            'first_name' => 'Rahul',
            'phone_e164' => '+919999999999',
            'phone_verified_at' => null,
            'role' => Role::SuperAdmin->value,
            'status' => AccountStatus::Suspended->value,
            'uuid' => 'attacker-chosen',
            'id' => 999,
        ]);

        $fresh = $this->rahul->fresh();

        $this->assertSame($originalPhone, $fresh->phone_e164);
        $this->assertEquals($originalVerifiedAt, $fresh->phone_verified_at);
        $this->assertSame(Role::Customer, $fresh->role);
        $this->assertSame(AccountStatus::Active, $fresh->status);
        $this->assertSame($this->rahul->uuid, $fresh->uuid);
    }

    public function test_changing_the_email_un_verifies_it(): void
    {
        $this->rahul->forceFill(['email_verified_at' => now()])->save();

        $updated = $this->service->update($this->rahul, ['email' => 'different@example.com']);

        // Written now so that adding email verification later cannot leave a
        // "verified" flag attached to an address swapped in afterwards.
        $this->assertNull($updated->email_verified_at);
    }

    public function test_resubmitting_the_same_email_does_not_un_verify_it(): void
    {
        $this->rahul->forceFill(['email_verified_at' => now()])->save();

        $updated = $this->service->update($this->rahul, [
            'first_name' => 'Rahul',
            'email' => 'rahul.test@foodonthego.example',
        ]);

        // Saving the form without touching the email must not silently undo a
        // verification the customer completed.
        $this->assertNotNull($updated->email_verified_at);
    }

    public function test_the_legacy_display_name_is_kept_in_step(): void
    {
        $updated = $this->service->update($this->rahul, [
            'first_name' => 'Rahul',
            'last_name' => 'S. Sharma',
        ]);

        // Two names in two places is the bug this prevents.
        $this->assertSame('Rahul S. Sharma', $updated->name);
        $this->assertSame('Rahul S. Sharma', $updated->displayName());
    }

    public function test_a_customer_with_one_name_keeps_a_clean_display_name(): void
    {
        $updated = $this->service->update($this->rahul, [
            'first_name' => 'Priya',
            'last_name' => null,
        ]);

        $this->assertSame('Priya', $updated->name);
    }

    public function test_unicode_names_survive_intact(): void
    {
        foreach (['José', "O'Brien", 'Aarav-Krishna', 'प्रिया', '李'] as $name) {
            $updated = $this->service->update($this->rahul, ['first_name' => $name]);

            $this->assertSame($name, $updated->fresh()->first_name);
        }
    }

    public function test_markup_in_a_name_is_stored_verbatim_and_not_mangled(): void
    {
        $this->service->update($this->rahul, ['first_name' => "<script>alert('x')</script>"]);

        // Escaping is the renderer's job. Mutating input on the way in loses data
        // for anybody whose name contains an apostrophe.
        $this->assertDatabaseHas('users', ['first_name' => "<script>alert('x')</script>"]);
    }
}
