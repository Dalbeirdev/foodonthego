<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What became of one attempt to pay.
 *
 * Authorized and Captured are kept apart rather than collapsed into "succeeded".
 * They are genuinely different facts — the money is promised versus the money is
 * taken — and a project that flattens them cannot later answer a question about
 * settlement without going back to the provider for every row.
 */
enum PaymentStatus: string
{
    /** The provider order exists. Nobody has paid anything yet. */
    case Created = 'CREATED';

    /** The money is promised. */
    case Authorized = 'AUTHORIZED';

    /** The money is taken. */
    case Captured = 'CAPTURED';

    /** The provider refused. */
    case Failed = 'FAILED';

    /** Whether this attempt is good enough to mark its order paid. */
    public function settlesOrder(): bool
    {
        return $this === self::Captured;
    }

    public function isFinished(): bool
    {
        return $this === self::Captured || $this === self::Failed;
    }
}
