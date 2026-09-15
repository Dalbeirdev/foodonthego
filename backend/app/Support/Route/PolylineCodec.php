<?php

declare(strict_types=1);

namespace App\Support\Route;

/**
 * Google's encoded polyline algorithm.
 *
 * Implemented here rather than pulled in, because it is forty lines and the
 * alternative is a dependency in the path of every route calculation. It exists
 * for one job: proving that what a provider sent is real geometry before any of
 * it is stored.
 *
 * A polyline that arrives as a plausible-looking string and decodes to two
 * points in the sea is exactly the failure this module cannot ship, and the only
 * way to catch it is to decode the thing.
 */
final class PolylineCodec
{
    /**
     * The most points we will decode from one polyline.
     *
     * A long Indian highway route is a few thousand points. This is an order of
     * magnitude above that, and it is here so a malformed or hostile response
     * cannot turn into an unbounded array — the decode allocates as it goes, and
     * "the provider is trusted" is not a memory-safety argument.
     */
    public const MAX_POINTS = 100_000;

    /**
     * Decodes an encoded polyline into coordinate pairs.
     *
     * @return list<array{0: float, 1: float}> latitude, longitude
     *
     * @throws PolylineException when the string is not a valid polyline
     */
    public static function decode(string $encoded): array
    {
        if ($encoded === '') {
            throw new PolylineException('The polyline was empty.');
        }

        $points = [];
        $index = 0;
        $length = strlen($encoded);
        $latitude = 0;
        $longitude = 0;

        while ($index < $length) {
            foreach (['lat', 'lng'] as $component) {
                $shift = 0;
                $result = 0;

                do {
                    if ($index >= $length) {
                        throw new PolylineException('The polyline ended mid-value.');
                    }

                    $byte = ord($encoded[$index++]) - 63;

                    if ($byte < 0) {
                        throw new PolylineException('The polyline contained a character outside the alphabet.');
                    }

                    $result |= ($byte & 0x1F) << $shift;
                    $shift += 5;

                    // Five bits per character, and a coordinate is at most 32
                    // bits. Beyond this the string is not a polyline, and
                    // continuing would shift into nothing for ever.
                    if ($shift > 35) {
                        throw new PolylineException('The polyline contained an over-long value.');
                    }
                } while ($byte >= 0x20);

                $delta = ($result & 1) !== 0 ? ~($result >> 1) : ($result >> 1);

                if ($component === 'lat') {
                    $latitude += $delta;
                } else {
                    $longitude += $delta;
                }
            }

            $points[] = [$latitude / 1e5, $longitude / 1e5];

            if (count($points) > self::MAX_POINTS) {
                throw new PolylineException('The polyline held more points than we will decode.');
            }
        }

        /*
         | There is deliberately no "decoded to no points" guard here.
         |
         | There used to be, and static analysis (KI-003) showed it could never
         | fire: an empty string is refused at the top of this method, so
         | $length is at least 1, the while loop runs at least once, and
         | $points has at least one pair by the time control reaches here.
         | The check read as though it were handling a case; it was handling a
         | case that had already been handled twenty lines earlier.
         |
         | Not a bug -- nothing behaved wrongly -- but 1,301 tests could never
         | have found it, because no input reaches an unreachable branch. This
         | is the class of defect static analysis is for, and the note stays so
         | the guard is not helpfully added back.
         */

        return $points;
    }

    /**
     * Encodes coordinate pairs. Used by tests and fixtures, not by the
     * production path — providers send polylines, they do not ask for them.
     *
     * @param  list<array{0: float, 1: float}>  $points
     */
    public static function encode(array $points): string
    {
        $encoded = '';
        $previousLatitude = 0;
        $previousLongitude = 0;

        foreach ($points as [$latitude, $longitude]) {
            $scaledLatitude = (int) round($latitude * 1e5);
            $scaledLongitude = (int) round($longitude * 1e5);

            $encoded .= self::encodeValue($scaledLatitude - $previousLatitude);
            $encoded .= self::encodeValue($scaledLongitude - $previousLongitude);

            $previousLatitude = $scaledLatitude;
            $previousLongitude = $scaledLongitude;
        }

        return $encoded;
    }

    private static function encodeValue(int $value): string
    {
        $value = $value < 0 ? ~($value << 1) : ($value << 1);
        $chunk = '';

        while ($value >= 0x20) {
            $chunk .= chr((0x20 | ($value & 0x1F)) + 63);
            $value >>= 5;
        }

        return $chunk.chr($value + 63);
    }
}
