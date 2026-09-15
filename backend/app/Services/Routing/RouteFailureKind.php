<?php

declare(strict_types=1);

namespace App\Services\Routing;

/** Why a routing provider did not produce a route. */
enum RouteFailureKind: string
{
    /** Unreachable, 5xx, or a transport error. Retrying may work. */
    case Unavailable = 'unavailable';

    /** The provider took too long. Retrying may work. */
    case Timeout = 'timeout';

    /** Quota or throttling. Retrying *soon* will not work. */
    case RateLimited = 'rate_limited';

    /**
     * The provider answered and the answer was not usable — malformed JSON, a
     * missing polyline, a negative distance. Ours to fix, not the customer's to
     * retry, and it is logged loudly for exactly that reason.
     */
    case InvalidResponse = 'invalid_response';

    /** Our credentials were refused. Never retried, always alarming. */
    case NotAuthorised = 'not_authorised';
}
