<?php

declare(strict_types=1);

namespace App\Services\Payments;

use RuntimeException;

/**
 * The gateway could not be reached, or refused to do what was asked.
 *
 * Distinct from a payment *failing*. A declined card is a normal outcome with a
 * status of its own; this is the provider being unreachable, misconfigured or
 * answering with something unintelligible. Callers must not treat the two the
 * same, because one means "tell the customer their card was declined" and the
 * other means "tell the customer to try again and tell us about it".
 */
final class PaymentGatewayException extends RuntimeException {}
