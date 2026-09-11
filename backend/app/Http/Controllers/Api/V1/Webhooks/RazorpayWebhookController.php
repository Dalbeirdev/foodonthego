<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Webhooks;

use App\Enums\ApiErrorCode;
use App\Http\Responses\ApiResponse;
use App\Services\Payments\WebhookService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * The one endpoint in this API that anybody on the internet may call.
 *
 * It is not authenticated, because the provider has no account here. What stands
 * in for authentication is the HMAC over the request body, and everything about
 * this controller follows from that:
 *
 * - The signature is computed over `getContent()`, the **raw** body. Laravel's
 *   parsed input would have to be re-encoded to hash it, and re-encoding changes
 *   bytes — key order, spacing, unicode escapes — so the HMAC would never match.
 * - Nothing is written before the signature verifies. In particular no
 *   `payment_events` row: that table's unique index is the idempotency gate, and
 *   writing an unverified event id would let anybody suppress a genuine delivery
 *   by claiming its id first.
 * - A rejected delivery gets 400 and a log line, and says nothing about why.
 *
 * A verified delivery answers 200 even when there was nothing to do. Providers
 * retry on non-2xx, and answering 500 because an event named an order this
 * deployment has never heard of would earn an escalating retry storm for a
 * condition no retry can fix.
 */
final class RazorpayWebhookController
{
    /** Razorpay's header names. Both are read case-insensitively by Laravel. */
    private const SIGNATURE_HEADER = 'X-Razorpay-Signature';

    private const EVENT_ID_HEADER = 'X-Razorpay-Event-Id';

    public function __construct(
        private readonly WebhookService $webhooks,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $rawBody = $request->getContent();
        $signature = (string) $request->header(self::SIGNATURE_HEADER, '');

        if (! $this->webhooks->signatureIsValid($rawBody, $signature)) {
            // The digest, not the body, and no detail about which check failed.
            // A caller probing this endpoint learns nothing from the response and
            // nothing from a timing difference — the comparison underneath is
            // constant-time.
            Log::warning('payments.webhook_signature_rejected', [
                'digest' => hash('sha256', $rawBody),
                'has_signature' => $signature !== '',
            ]);

            return ApiResponse::error(
                ApiErrorCode::WebhookSignatureInvalid,
                'Signature verification failed.',
            );
        }

        // Taken from the header rather than the body. The header is what the
        // provider guarantees to be unique per delivery, and a body field would
        // let a payload with a duplicated id inside it collide with a real event.
        $eventId = (string) $request->header(self::EVENT_ID_HEADER, '');

        if ($eventId === '') {
            // Verified, so genuinely from the provider, but with nothing to make
            // it idempotent on. Falling back to the body digest is right: two
            // deliveries with identical bytes are the same event by any useful
            // definition.
            $eventId = 'digest:'.hash('sha256', $rawBody);
        }

        $outcome = $this->webhooks->handleVerified($rawBody, $eventId);

        return ApiResponse::ok([
            'received' => true,
            'outcome' => $outcome->value,
        ]);
    }
}
