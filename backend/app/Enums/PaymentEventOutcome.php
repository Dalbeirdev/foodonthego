<?php

declare(strict_types=1);

namespace App\Enums;

/** What the webhook handler did with one delivery. */
enum PaymentEventOutcome: string
{
    /** It changed something. */
    case Applied = 'APPLIED';

    /** Seen before. The unique index caught it; nothing ran twice. */
    case Duplicate = 'DUPLICATE';

    /** Understood, and there was nothing to do. */
    case Ignored = 'IGNORED';

    /**
     * Understood, verified, and naming something this server does not know.
     *
     * There is deliberately no REJECTED case. A delivery whose signature fails
     * is never written to `payment_events` at all — see that table's migration
     * for why storing it would hand anybody a way to suppress a real one.
     */
    case Unknown = 'UNKNOWN';
}
