<?php

declare(strict_types=1);

namespace App\Http\Requests\Auth;

/**
 * Requesting a code needs nothing beyond the number itself.
 *
 * Deliberately no device id, no advertising id, no attribution payload: none of
 * it is needed to send an SMS, and collecting identifiers "in case" is how a
 * sign-in screen becomes a tracking surface.
 */
final class OtpRequestRequest extends PhoneFormRequest {}
