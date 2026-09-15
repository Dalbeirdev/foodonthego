<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Which authority convinced the server that a payment happened.
 *
 * Recorded rather than inferred, because these are not equally strong and a
 * later reader deserves to know which one was believed. A client callback is a
 * signed message relayed through a device we do not control; a webhook comes
 * from the provider directly; reconciliation is the server going and asking.
 * All three are verified before they are acted on — the distinction is not
 * trusted versus untrusted, it is which path got there first.
 */
enum PaymentVerificationSource: string
{
    /** The app returned a signature, and the server checked the HMAC itself. */
    case ClientCallback = 'CLIENT_CALLBACK';

    /** The provider posted to us, and the server checked the body's HMAC. */
    case Webhook = 'WEBHOOK';

    /** The server asked the provider what it thought. */
    case Reconciliation = 'RECONCILIATION';
}
