<?php

declare(strict_types=1);

namespace App\Services\Places;

use RuntimeException;

/**
 * A place provider could not answer.
 *
 * Carries no provider detail towards the client on purpose: a quota message, a
 * key error or a raw upstream body tells a caller about our billing and our
 * configuration. The controller turns this into `PLACE_LOOKUP_FAILED`, and the
 * detail goes to the log against the request id.
 */
final class PlaceLookupException extends RuntimeException {}
