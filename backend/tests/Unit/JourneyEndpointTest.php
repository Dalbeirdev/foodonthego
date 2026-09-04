<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\Trip\JourneyEndpoint;
use PHPUnit\Framework\TestCase;

/**
 * The value object both ends of a journey are built from. No database.
 */
final class JourneyEndpointTest extends TestCase
{
    /** @param array<string, mixed> $input */
    private function typed(array $input = []): JourneyEndpoint
    {
        return JourneyEndpoint::fromInput(array_merge([
            'address_line' => 'MI Road',
            'city' => 'Jaipur',
            'state' => 'Rajasthan',
            'country_code' => 'in',
        ], $input));
    }

    public function test_the_one_line_address_is_composed_from_the_parts(): void
    {
        $this->assertSame('MI Road, Jaipur, Rajasthan', $this->typed()->formattedAddress);
    }

    public function test_missing_parts_do_not_leave_stray_separators(): void
    {
        $endpoint = $this->typed(['address_line' => '', 'state' => '']);

        $this->assertSame('Jaipur', $endpoint->formattedAddress);
    }

    public function test_the_city_becomes_the_label_when_none_was_given(): void
    {
        // A traveller who typed only a city has named the place. An empty label
        // would render an unreadable row, and repeating the whole formatted line
        // would render an unreadable one for a different reason.
        $this->assertSame('Jaipur', $this->typed()->label);
    }

    public function test_a_given_label_wins(): void
    {
        $this->assertSame("Parents' House", $this->typed(['label' => "Parents' House"])->label);
    }

    public function test_a_country_code_is_upper_cased(): void
    {
        $this->assertSame('IN', $this->typed()->countryCode);
    }

    public function test_coordinates_are_null_when_none_were_supplied(): void
    {
        $endpoint = $this->typed();

        $this->assertNull($endpoint->latitude);
        $this->assertNull($endpoint->longitude);
        $this->assertNull($endpoint->placeId);
    }

    public function test_supplied_coordinates_are_kept_as_strings(): void
    {
        $endpoint = $this->typed(['latitude' => 26.9124, 'longitude' => 75.7873]);

        // Strings, not floats: the last decimal place of a coordinate is metres,
        // and it is the pair a corridor will be built from.
        $this->assertSame('26.9124', $endpoint->latitude);
        $this->assertSame('75.7873', $endpoint->longitude);
    }

    public function test_a_blank_place_id_becomes_null(): void
    {
        $this->assertNull($this->typed(['place_id' => '   '])->placeId);
    }

    public function test_two_spellings_of_the_same_place_are_the_same_place(): void
    {
        $a = $this->typed();
        $b = $this->typed(['city' => '  JAIPUR ', 'address_line' => 'mi   road']);

        $this->assertTrue($a->isSamePlaceAs($b));
    }

    public function test_two_different_places_are_different(): void
    {
        $this->assertFalse($this->typed()->isSamePlaceAs($this->typed([
            'address_line' => 'Civil Lines',
            'city' => 'Udaipur',
        ])));
    }

    public function test_the_columns_are_prefixed_for_the_end_they_belong_to(): void
    {
        $columns = $this->typed()->toColumns('destination');

        $this->assertSame('Jaipur', $columns['destination_city']);
        $this->assertSame('IN', $columns['destination_country_code']);
        $this->assertNull($columns['destination_latitude']);
        $this->assertArrayHasKey('destination_address_id', $columns);
        $this->assertArrayNotHasKey('origin_city', $columns);
    }

    public function test_a_typed_endpoint_carries_no_saved_address_id(): void
    {
        $this->assertNull($this->typed()->addressId);
    }
}
