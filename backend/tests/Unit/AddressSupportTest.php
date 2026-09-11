<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\AddressType;
use App\Support\Address\AddressFormatter;
use App\Support\Address\PostalCode;
use Tests\TestCase;

final class AddressSupportTest extends TestCase
{
    public function test_the_one_line_address_reads_the_way_an_envelope_does(): void
    {
        $this->assertSame(
            '12 Green Park Road, Green Park, New Delhi, Delhi 110016, IN',
            AddressFormatter::compose([
                'address_line_1' => '12 Green Park Road',
                'address_line_2' => 'Green Park',
                'city' => 'New Delhi',
                'state' => 'Delhi',
                'postal_code' => '110016',
                'country_code' => 'IN',
            ]),
        );
    }

    public function test_empty_parts_do_not_leave_stray_commas(): void
    {
        $this->assertSame(
            'Connaught Place, New Delhi, Delhi, IN',
            AddressFormatter::compose([
                'address_line_1' => 'Connaught Place',
                'address_line_2' => null,
                'landmark' => '   ',
                'city' => 'New Delhi',
                'state' => 'Delhi',
                'postal_code' => null,
                'country_code' => 'IN',
            ]),
        );
    }

    public function test_the_landmark_is_deliberately_not_in_the_one_line_form(): void
    {
        $composed = AddressFormatter::compose([
            'address_line_1' => 'Connaught Place',
            'landmark' => 'Near the metro station',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'country_code' => 'IN',
        ]);

        // It helps somebody find the door and is shown beside the address, but
        // inside a one-line address it is noise and useless to a geocoder.
        $this->assertStringNotContainsString('metro', $composed);
    }

    public function test_the_postcode_stays_attached_to_the_region(): void
    {
        $composed = AddressFormatter::compose([
            'address_line_1' => 'A',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ]);

        // "Delhi 110016", not "Delhi, 110016" — which reads as two fields.
        $this->assertStringContainsString('Delhi 110016', $composed);
    }

    public function test_indian_pin_codes_are_six_digits_not_starting_with_zero(): void
    {
        $this->assertTrue(PostalCode::isValid('IN', '110016'));
        $this->assertTrue(PostalCode::isValid('IN', '560001'));

        $this->assertFalse(PostalCode::isValid('IN', '11001'));
        $this->assertFalse(PostalCode::isValid('IN', '1100166'));
        $this->assertFalse(PostalCode::isValid('IN', '010016'));
        $this->assertFalse(PostalCode::isValid('IN', 'ABC123'));
    }

    public function test_a_pin_code_is_required_in_india_and_not_everywhere(): void
    {
        $this->assertTrue(PostalCode::isRequiredFor('IN'));
        $this->assertFalse(PostalCode::isValid('IN', ''));

        // The UAE has no postal code system in general use; requiring one would
        // make an Emirati address impossible to save.
        $this->assertFalse(PostalCode::isRequiredFor('AE'));
        $this->assertTrue(PostalCode::isValid('AE', ''));
    }

    public function test_other_countries_are_not_forced_into_the_indian_shape(): void
    {
        // "Six digits" is an Indian rule, not a universal one.
        $this->assertTrue(PostalCode::isValid('GB', 'SW1A 1AA'));
        $this->assertTrue(PostalCode::isValid('GB', 'sw1a1aa'));
        $this->assertFalse(PostalCode::isValid('GB', '110016'));

        $this->assertTrue(PostalCode::isValid('US', '10001'));
        $this->assertTrue(PostalCode::isValid('US', '10001-1234'));
        $this->assertFalse(PostalCode::isValid('US', '1000'));
    }

    public function test_an_unlisted_country_is_accepted_rather_than_blocked(): void
    {
        // Rejecting would make an address in an unlisted country impossible to
        // save, which is worse than storing a postcode we could not check.
        $this->assertTrue(PostalCode::isValid('FR', '75008'));
        $this->assertTrue(PostalCode::isValid('IE', 'D02 AF30'));
        $this->assertFalse(PostalCode::hasRuleFor('FR'));

        // A length sanity check still applies, so the column always holds it.
        $this->assertFalse(PostalCode::isValid('FR', str_repeat('9', 20)));
    }

    public function test_address_types_carry_their_own_fallback_label(): void
    {
        $this->assertSame('Home', AddressType::Home->defaultLabel());
        $this->assertSame('Work', AddressType::Work->defaultLabel());

        // Only OTHER makes the customer name the place — "Other" in a list of
        // three Others is unreadable.
        $this->assertTrue(AddressType::Other->requiresCustomLabel());
        $this->assertFalse(AddressType::Home->requiresCustomLabel());
    }
}
