<?php

declare(strict_types=1);

namespace App\Services\Otp\Providers;

use App\Services\Otp\OtpDeliveryFailed;
use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\OtpDeliveryReceipt;
use App\Support\Phone\PhoneNumber;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * Sends the one-time code as an SMS through Twilio's REST API.
 *
 * Authenticates with an API key (SK…) rather than the account auth token. Both
 * work; the key is revocable on its own, so a leak costs one credential instead
 * of the account, and rotating it does not disturb anything else using Twilio.
 *
 * The one thing this class must never do is let the code escape anywhere except
 * into the request body. It is not logged, not put in an exception message, and
 * not returned in the receipt — the receipt carries Twilio's message SID, which
 * is what support quotes when a customer says nothing arrived.
 *
 * ## What counts as a failure
 *
 * {@see OtpDeliveryFailed} means the code **definitely** was not sent, because
 * the caller invalidates the challenge on it. Twilio accepting a message for
 * delivery is not delivery, and this class does not pretend otherwise: a 201
 * with a queued status is a success here even though the handset has nothing
 * yet. What is treated as failure is a rejected request, a transport error, or
 * a message Twilio itself reports as already failed at creation.
 *
 * ## India
 *
 * Reaching an Indian handset needs more than this class. The sender must be
 * registered on a DLT platform and the body must match a registered template.
 * An unregistered template is dropped by the carrier *after* the API returns
 * 201, so a green response here is not evidence the message arrived. That is
 * why the template is configuration rather than a string in this file.
 */
final readonly class TwilioOtpProvider implements OtpDeliveryProvider
{
    /**
     * @param  string  $accountSid  The account the key acts on (AC…).
     * @param  string  $apiKeySid  HTTP Basic username (SK…).
     * @param  string  $apiKeySecret  HTTP Basic password. Never logged.
     * @param  string|null  $messagingServiceSid  Preferred sender (MG…).
     * @param  string|null  $from  Sender number in E.164, when no messaging service.
     * @param  string  $messageTemplate  Must contain the {code} placeholder.
     */
    public function __construct(
        private string $accountSid,
        private string $apiKeySid,
        private string $apiKeySecret,
        private ?string $messagingServiceSid = null,
        private ?string $from = null,
        private string $messageTemplate = '{code} is your verification code.',
        private int $timeoutSeconds = 10,
        private string $baseUrl = 'https://api.twilio.com',
    ) {}

    public function send(PhoneNumber $phone, string $code): OtpDeliveryReceipt
    {
        $payload = [
            'To' => $phone->e164,
            'Body' => str_replace('{code}', $code, $this->messageTemplate),
        ];

        // Twilio rejects a request carrying both, and one of them is required.
        // The messaging service wins when configured because it is the one that
        // can carry a registered sender.
        if ($this->messagingServiceSid !== null && $this->messagingServiceSid !== '') {
            $payload['MessagingServiceSid'] = $this->messagingServiceSid;
        } else {
            $payload['From'] = (string) $this->from;
        }

        try {
            $response = Http::asForm()
                ->withBasicAuth($this->apiKeySid, $this->apiKeySecret)
                ->timeout($this->timeoutSeconds)
                ->post($this->messagesEndpoint(), $payload);
        } catch (ConnectionException $e) {
            // Nothing reached Twilio, so nothing was sent. The message is safe
            // to carry: it describes a socket, and the payload never got near it.
            throw new OtpDeliveryFailed('twilio', 'Could not reach Twilio: '.$e->getMessage());
        } catch (Throwable $e) {
            // Deliberately broad, and deliberately does not repeat $e's message.
            // An unexpected throwable from inside the HTTP stack can carry the
            // request it was building, and that request contains the code.
            throw new OtpDeliveryFailed(
                'twilio',
                'Unexpected failure sending through Twilio: '.$e::class,
            );
        }

        /** @var array<string, mixed> $body */
        $body = $response->json() ?? [];

        if ($response->failed()) {
            // Twilio's error body is a documented shape and contains neither the
            // credential nor the message text, so quoting it aids diagnosis
            // without leaking. It reaches a log, never the customer — the caller
            // answers them with a fixed sentence.
            throw new OtpDeliveryFailed(
                'twilio',
                sprintf(
                    'Twilio rejected the message (HTTP %d): %s',
                    $response->status(),
                    is_string($body['message'] ?? null) ? $body['message'] : 'no message given',
                ),
                isset($body['code']) ? (string) $body['code'] : null,
            );
        }

        $status = is_string($body['status'] ?? null) ? $body['status'] : '';

        // 'failed' and 'undelivered' at creation time mean it will not be sent.
        // Every other status — queued, accepted, sending, sent — means Twilio has
        // taken it, which is as much as any SMS API can promise synchronously.
        if (in_array($status, ['failed', 'undelivered'], true)) {
            throw new OtpDeliveryFailed(
                'twilio',
                sprintf('Twilio created the message already in status "%s".', $status),
                isset($body['error_code']) ? (string) $body['error_code'] : null,
            );
        }

        return new OtpDeliveryReceipt(
            'twilio',
            is_string($body['sid'] ?? null) ? $body['sid'] : null,
        );
    }

    public function name(): string
    {
        return 'twilio';
    }

    public function deliversToRealDevices(): bool
    {
        return true;
    }

    private function messagesEndpoint(): string
    {
        return sprintf(
            '%s/2010-04-01/Accounts/%s/Messages.json',
            rtrim($this->baseUrl, '/'),
            $this->accountSid,
        );
    }
}
