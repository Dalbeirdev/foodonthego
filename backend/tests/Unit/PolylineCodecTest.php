<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\Route\PolylineCodec;
use App\Support\Route\PolylineException;
use Tests\TestCase;

/**
 * The polyline codec.
 *
 * It exists so a provider's geometry can be *proved* to be geometry before it is
 * stored. A polyline that arrives as a plausible string and decodes to nothing —
 * or to two points in the sea — is the failure this module must not ship, and
 * the only way to catch it is to decode the thing.
 */
final class PolylineCodecTest extends TestCase
{
    public function test_it_decodes_the_example_from_googles_own_specification(): void
    {
        // The canonical example: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453).
        $points = PolylineCodec::decode('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

        $this->assertCount(3, $points);
        $this->assertEqualsWithDelta(38.5, $points[0][0], 0.00001);
        $this->assertEqualsWithDelta(-120.2, $points[0][1], 0.00001);
        $this->assertEqualsWithDelta(43.252, $points[2][0], 0.00001);
        $this->assertEqualsWithDelta(-126.453, $points[2][1], 0.00001);
    }

    public function test_it_round_trips(): void
    {
        $original = [[28.5494, 77.2001], [27.5, 76.5], [26.8242, 75.8122]];

        $decoded = PolylineCodec::decode(PolylineCodec::encode($original));

        foreach ($original as $index => [$latitude, $longitude]) {
            $this->assertEqualsWithDelta($latitude, $decoded[$index][0], 0.00001);
            $this->assertEqualsWithDelta($longitude, $decoded[$index][1], 0.00001);
        }
    }

    public function test_an_empty_string_is_refused(): void
    {
        $this->expectException(PolylineException::class);

        PolylineCodec::decode('');
    }

    public function test_a_string_that_is_not_a_polyline_is_refused(): void
    {
        // Below the alphabet's floor of 63, so it cannot be a chunk.
        $this->expectException(PolylineException::class);

        PolylineCodec::decode("\x01\x02\x03");
    }

    public function test_a_truncated_polyline_is_refused_rather_than_half_read(): void
    {
        // A continuation bit set on the final character: the value never ends.
        // Truncation is exactly what a proxy or a length limit produces, and half
        // a route drawn confidently on a map is worse than none.
        $this->expectException(PolylineException::class);

        PolylineCodec::decode('_p~iF~ps|U_ulLnnq');
    }

    public function test_an_over_long_value_is_refused(): void
    {
        // Eight continuation characters is more shifting than a coordinate can
        // need; without the guard this loops into meaningless numbers.
        $this->expectException(PolylineException::class);

        PolylineCodec::decode(str_repeat(chr(0x20 + 63), 12));
    }

    public function test_a_single_point_decodes(): void
    {
        // Valid, and the validator is what rejects it as a route. The codec's job
        // is to say what the string contains, not whether it is useful.
        $points = PolylineCodec::decode(PolylineCodec::encode([[28.5494, 77.2001]]));

        $this->assertCount(1, $points);
    }

    public function test_precision_survives_to_five_decimal_places(): void
    {
        // The format's own precision. Anything finer is not lost by this codec —
        // it was never in the string.
        $decoded = PolylineCodec::decode(PolylineCodec::encode([[28.54941, 77.20013]]));

        $this->assertEqualsWithDelta(28.54941, $decoded[0][0], 0.000001);
        $this->assertEqualsWithDelta(77.20013, $decoded[0][1], 0.000001);
    }
}
