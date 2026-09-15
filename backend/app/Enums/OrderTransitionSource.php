<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What kind of thing caused a status transition.
 *
 * NEVER READ FROM A REQUEST BODY. Every one of these is decided by the code
 * path performing the transition, from the authenticated principal it already
 * has. A client that could name its own source could write RESTAURANT into the
 * audit trail of an order it does not own, which would make the trail worse
 * than not having one.
 */
enum OrderTransitionSource: string
{
    /** The platform itself — placement, recovery, reconciliation. */
    case System = 'SYSTEM';

    /** A restaurant operator. Modules 18–19 will be the first to use it. */
    case Restaurant = 'RESTAURANT';

    /** A platform administrator acting deliberately. */
    case Admin = 'ADMIN';

    /** A payment outcome moved the order. Module 15 owns these. */
    case Payment = 'PAYMENT';

    /**
     * The customer did something that moved their own order.
     *
     * NOTHING USES THIS YET, and that is a policy statement rather than an
     * omission: no cancellation policy has been agreed, so the customer app has
     * no endpoint that transitions an order. See docs/36.
     */
    case CustomerAction = 'CUSTOMER_ACTION';

    /**
     * A development-only harness moved the order.
     *
     * Distinct from SYSTEM on purpose. A production database should contain no
     * rows carrying this source, which makes it a thing that can be queried for
     * rather than a thing that has to be trusted not to happen.
     */
    case TestHarness = 'TEST_HARNESS';
}
