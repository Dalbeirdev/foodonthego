<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Where one step of a customer's timeline stands.
 *
 * The server decides this, not the phone. A client that worked out "COOKING
 * comes after ACCEPTED, so ACCEPTED must be done" would be re-implementing the
 * lifecycle in Dart, and would be wrong the first time the lifecycle changed
 * without the app being updated.
 */
enum OrderTimelineStepState: string
{
    /** Reached, with a timestamp saying when. */
    case Completed = 'COMPLETED';

    /** Where the order is right now. */
    case Current = 'CURRENT';

    /** Expected, not yet reached, and carrying no timestamp. */
    case Upcoming = 'UPCOMING';

    /**
     * The order ended here instead of continuing.
     *
     * REJECTED and CANCELLED are exceptions rather than progress, and rendering
     * them as a completed step would put a tick beside "your order was
     * refused".
     */
    case Exception = 'EXCEPTION';
}
