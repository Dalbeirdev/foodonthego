<?php

declare(strict_types=1);

namespace App\Support\Geo;

use App\Support\Route\PolylineCodec;
use App\Support\Route\PolylineException;

/**
 * A decoded route, and the measurements a discovery search takes against it.
 *
 * Built once per request and reused for every candidate. That is the whole
 * reason it is an object: decoding a 25 000-point polyline and accumulating its
 * segment lengths is real work, and doing it inside the candidate loop would
 * multiply it by the size of the candidate set.
 *
 * The points are simplified on construction — see {@see simplify()} — and the
 * cumulative distances are computed from the *simplified* line, so every figure
 * this class returns is consistent with every other. Mixing a simplified
 * projection with an unsimplified total would make distance-ahead values that do
 * not add up to the route's own length.
 */
final class RouteGeometry
{
    /** @var list<Coordinate> */
    private array $points;

    /**
     * Distance from the origin to each point, metres. Same length as $points,
     * first element zero.
     *
     * @var list<float>
     */
    private array $cumulative;

    private float $totalMetres;

    /** @param list<Coordinate> $points */
    private function __construct(array $points)
    {
        $this->points = $points;
        $this->cumulative = [0.0];

        $running = 0.0;

        for ($i = 1, $n = count($points); $i < $n; $i++) {
            $running += Distance::haversineMetres($points[$i - 1], $points[$i]);
            $this->cumulative[] = $running;
        }

        $this->totalMetres = $running;
    }

    /**
     * From a provider's encoded polyline.
     *
     * @throws PolylineException when the geometry will not decode.
     *                           Not caught here: a route whose geometry is unreadable is not a route
     *                           this module can search along, and pretending otherwise would mean
     *                           measuring restaurants against a straight line.
     */
    public static function fromEncoded(string $encoded, float $simplifyToleranceMetres): self
    {
        $decoded = array_map(
            static fn (array $pair): Coordinate => Coordinate::fromPair($pair),
            PolylineCodec::decode($encoded),
        );

        return new self(self::simplify($decoded, $simplifyToleranceMetres));
    }

    /** @param list<Coordinate> $points */
    public static function fromPoints(array $points): self
    {
        return new self($points);
    }

    /** @return list<Coordinate> */
    public function points(): array
    {
        return $this->points;
    }

    public function pointCount(): int
    {
        return count($this->points);
    }

    public function totalMetres(): float
    {
        return $this->totalMetres;
    }

    public function origin(): Coordinate
    {
        return $this->points[0];
    }

    public function destination(): Coordinate
    {
        return $this->points[count($this->points) - 1];
    }

    /**
     * Where a point sits relative to this route.
     *
     * Walks every segment, finds the closest approach, and reports both how far
     * off the route the point is and how far along the route that closest point
     * lies. Both numbers come out of the same pass, because they are the same
     * question asked twice and computing them separately is how they end up
     * disagreeing.
     *
     * **The self-crossing case.** A route that passes near itself — a ring road,
     * a return leg, a cloverleaf — offers two segments at almost the same
     * distance from a restaurant beside it, and picking the numerically smallest
     * is a coin flip that decides whether the restaurant is reported as 20 km
     * ahead or 200 km ahead. So ties are broken deliberately: among segments
     * within {@see AMBIGUOUS_TOLERANCE_METRES} of the best, the **earliest**
     * along the route wins. A traveller setting off wants the first chance to
     * stop, not the last, and being early is the error that costs them nothing.
     */
    public function project(Coordinate $point): RouteProjection
    {
        // Two passes rather than one. A single pass has to decide a tie before
        // it knows what the best distance will turn out to be, and the version
        // of this that tried was subtly wrong: a later segment could displace an
        // earlier one it was never actually closer than. Finding the minimum
        // first makes the tie rule a plain filter.
        $candidates = [];
        $best = INF;

        for ($i = 1, $n = count($this->points); $i < $n; $i++) {
            $a = $this->points[$i - 1];
            $b = $this->points[$i];

            [$closest, $fraction] = $this->closestOnSegment($a, $b, $point);

            // Cheap metric inside the loop; the reported figure is recomputed
            // exactly once, on the winner.
            $distance = Distance::equirectangularMetres($point, $closest);

            if ($distance > $best + self::AMBIGUOUS_TOLERANCE_METRES) {
                continue;
            }

            $best = min($best, $distance);

            $candidates[] = [
                'distance' => $distance,
                'along' => $this->cumulative[$i - 1]
                    + ($this->cumulative[$i] - $this->cumulative[$i - 1]) * $fraction,
                'index' => $i - 1,
                'point' => $closest,
            ];
        }

        // Everything within the tolerance of the closest approach is a genuine
        // tie the geometry cannot separate; the earliest of them wins.
        $tied = array_filter(
            $candidates,
            static fn (array $c): bool => $c['distance'] <= $best + self::AMBIGUOUS_TOLERANCE_METRES,
        );

        usort($tied, static fn (array $x, array $y): int => $x['along'] <=> $y['along']);

        $winner = $tied[0];

        return new RouteProjection(
            point: $winner['point'],
            segmentIndex: $winner['index'],
            // The reported figure is the exact great-circle distance. The cheap
            // metric chose the segment; it does not get to be the answer.
            proximityMetres: Distance::haversineMetres($point, $winner['point']),
            alongRouteMetres: $winner['along'],
            routeTotalMetres: $this->totalMetres,
        );
    }

    /**
     * The route's own bounding box, grown by a margin.
     *
     * One box for the whole route rather than one per segment. A box per segment
     * would select less at the corners, but it means a query per segment — and
     * a Delhi-Jaipur route simplifies to a couple of hundred of them, so the
     * database round trips would cost more than the rows they saved. The single
     * box over-selects, and the exact projection then rejects what it let
     * through, which is the two-stage design working as intended.
     *
     * @return array{south: float, west: float, north: float, east: float}
     */
    public function boundingBox(float $marginMetres): array
    {
        $south = $north = $this->points[0]->latitude;
        $west = $east = $this->points[0]->longitude;

        foreach ($this->points as $p) {
            $south = min($south, $p->latitude);
            $north = max($north, $p->latitude);
            $west = min($west, $p->longitude);
            $east = max($east, $p->longitude);
        }

        // Grown at the widest latitude the box reaches, so the margin is at
        // least the requested one everywhere inside it.
        [$latMargin, $lonMargin] = Distance::degreesFor(
            $marginMetres,
            max(abs($south), abs($north)),
        );

        return [
            'south' => $south - $latMargin,
            'west' => $west - $lonMargin,
            'north' => $north + $latMargin,
            'east' => $east + $lonMargin,
        ];
    }

    /**
     * Two segments closer than this are treated as equally close.
     *
     * Ten metres: below the accuracy of the geometry itself, so this never
     * overrides a real difference — it only decides cases the data cannot.
     */
    private const AMBIGUOUS_TOLERANCE_METRES = 10.0;

    /**
     * The closest point on segment a-b to p, and how far along a-b it lies.
     *
     * Ordinary vector projection, done in a locally flat frame. The clamp to
     * [0, 1] is what makes it a *segment* rather than an infinite line: without
     * it a restaurant beyond the end of a segment projects past the segment's
     * end, and a restaurant past the destination reports as being on the route.
     *
     * @return array{0: Coordinate, 1: float}
     */
    private function closestOnSegment(Coordinate $a, Coordinate $b, Coordinate $p): array
    {
        $cos = cos(deg2rad($a->latitude));

        $ax = $a->longitude * $cos;
        $bx = $b->longitude * $cos;
        $px = $p->longitude * $cos;

        $dx = $bx - $ax;
        $dy = $b->latitude - $a->latitude;

        $lengthSquared = $dx * $dx + $dy * $dy;

        if ($lengthSquared <= 0.0) {
            // A zero-length segment: providers do emit repeated points.
            return [$a, 0.0];
        }

        $t = (($px - $ax) * $dx + ($p->latitude - $a->latitude) * $dy) / $lengthSquared;
        $t = max(0.0, min(1.0, $t));

        return [
            new Coordinate(
                $a->latitude + $dy * $t,
                $a->longitude + ($b->longitude - $a->longitude) * $t,
            ),
            $t,
        ];
    }

    /**
     * Ramer-Douglas-Peucker, with a metric tolerance.
     *
     * Drops points that lie within the tolerance of the line their neighbours
     * describe, which on a motorway removes most of them and on a hairpin
     * removes none. The tolerance is configured an order of magnitude below the
     * corridor width, so simplification can never move a restaurant across the
     * threshold that decides whether it is a candidate.
     *
     * @param  list<Coordinate>  $points
     * @return list<Coordinate>
     */
    private static function simplify(array $points, float $toleranceMetres): array
    {
        $count = count($points);

        if ($count <= 2 || $toleranceMetres <= 0) {
            return $points;
        }

        $keep = array_fill(0, $count, false);
        $keep[0] = true;
        $keep[$count - 1] = true;

        /** @var list<array{0: int, 1: int}> $stack */
        $stack = [[0, $count - 1]];

        while ($stack !== []) {
            [$start, $end] = array_pop($stack);

            if ($end - $start < 2) {
                continue;
            }

            $worst = 0.0;
            $worstIndex = $start;

            for ($i = $start + 1; $i < $end; $i++) {
                $d = self::perpendicularMetres($points[$i], $points[$start], $points[$end]);

                if ($d > $worst) {
                    $worst = $d;
                    $worstIndex = $i;
                }
            }

            if ($worst > $toleranceMetres) {
                $keep[$worstIndex] = true;
                $stack[] = [$start, $worstIndex];
                $stack[] = [$worstIndex, $end];
            }
        }

        $simplified = [];

        for ($i = 0; $i < $count; $i++) {
            if ($keep[$i]) {
                $simplified[] = $points[$i];
            }
        }

        return $simplified;
    }

    private static function perpendicularMetres(Coordinate $p, Coordinate $a, Coordinate $b): float
    {
        $cos = cos(deg2rad($a->latitude));

        $ax = $a->longitude * $cos;
        $dx = $b->longitude * $cos - $ax;
        $dy = $b->latitude - $a->latitude;

        $lengthSquared = $dx * $dx + $dy * $dy;

        if ($lengthSquared <= 0.0) {
            return Distance::equirectangularMetres($p, $a);
        }

        $t = (($p->longitude * $cos - $ax) * $dx + ($p->latitude - $a->latitude) * $dy) / $lengthSquared;
        $t = max(0.0, min(1.0, $t));

        $closest = new Coordinate(
            $a->latitude + $dy * $t,
            $a->longitude + ($b->longitude - $a->longitude) * $t,
        );

        return Distance::equirectangularMetres($p, $closest);
    }
}
