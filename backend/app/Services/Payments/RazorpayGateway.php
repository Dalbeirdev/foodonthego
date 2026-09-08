<?php

declare(strict_types=1);

namespace App\Services\Payments;

use App\Enums\PaymentStatus;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Razorpay, over its REST API.
 *
 * **Never executed in this project as it stands.** No Razorpay credentials
 * exist, none were invented, and the container binds
 * {@see UnconfiguredPaymentGateway} instead. This class is written so that
 * supplying credentials is a configuration change rather than a development
 * task, and so that the shape of the integration can be reviewed now — but no
 * claim is made that it has spoken to Razorpay, because it has not.
 *
 * The amount is sent in minor units, which is also what Razorpay expects, so
 * nothing here multiplies or divides by a hundred. Every float-shaped bug in
 * payment code starts with a conversion that looked harmless.
 */
final class RazorpayGateway implements PaymentGateway
{
    private const BASE_URL = 'https://api.razorpay.com/v1';

    public function __construct(
        private readonly string $keyId,
        private readonly string $keySecret,
        private readonly int $timeoutSeconds = 15,
    ) {}

    public function name(): string
    {
        return 'razorpay';
    }

    public function createOrder(int $amountMinor, string $currency, string $receipt): GatewayOrder
    {
        $body = $this->post('/orders', [
            'amount' => $amountMinor,
            'currency' => $currency,
            'receipt' => $receipt,
            // Razorpay would otherwise capture automatically on some accounts.
            // Asking explicitly means the behaviour is ours rather than the
            // dashboard's, and reconciliation knows what to expect.
            'payment_capture' => 1,
        ]);

        $id = $body['id'] ?? null;

        if (! is_string($id) || $id === '') {
            throw new PaymentGatewayException('Razorpay returned an order with no id.');
        }

        return new GatewayOrder(
            id: $id,
            amountMinor: (int) ($body['amount'] ?? $amountMinor),
            currency: (string) ($body['currency'] ?? $currency),
            status: (string) ($body['status'] ?? 'created'),
        );
    }

    public function fetchOrderPayments(string $providerOrderId): array
    {
        $body = $this->get('/orders/'.urlencode($providerOrderId).'/payments');

        $items = $body['items'] ?? [];

        if (! is_array($items)) {
            throw new PaymentGatewayException('Razorpay returned a payment list that was not a list.');
        }

        $payments = [];

        foreach ($items as $item) {
            if (! is_array($item) || ! is_string($item['id'] ?? null)) {
                continue;
            }

            $payments[] = new GatewayPayment(
                id: $item['id'],
                orderId: is_string($item['order_id'] ?? null) ? $item['order_id'] : $providerOrderId,
                amountMinor: (int) ($item['amount'] ?? 0),
                currency: (string) ($item['currency'] ?? 'INR'),
                status: self::translateStatus((string) ($item['status'] ?? '')),
                failureReason: is_string($item['error_description'] ?? null)
                    ? mb_substr($item['error_description'], 0, 200)
                    : null,
            );
        }

        return $payments;
    }

    public function fetchPayment(string $providerPaymentId): GatewayPayment
    {
        $body = $this->get('/payments/'.urlencode($providerPaymentId));

        $id = $body['id'] ?? null;
        $orderId = $body['order_id'] ?? null;

        if (! is_string($id) || ! is_string($orderId)) {
            throw new PaymentGatewayException('Razorpay returned a payment with no id or order id.');
        }

        return new GatewayPayment(
            id: $id,
            orderId: $orderId,
            amountMinor: (int) ($body['amount'] ?? 0),
            currency: (string) ($body['currency'] ?? 'INR'),
            status: self::translateStatus((string) ($body['status'] ?? '')),
            failureReason: is_string($body['error_description'] ?? null)
                ? mb_substr($body['error_description'], 0, 200)
                : null,
        );
    }

    /**
     * Razorpay's vocabulary, mapped onto ours.
     *
     * `refunded` deliberately maps to Captured rather than to a status of its
     * own. A refund is a later event about money that was genuinely taken, and
     * flattening it into "failed" would make an order that was paid and then
     * refunded look like one that never paid. Refund handling is not in this
     * module; when it arrives it gets its own record rather than overwriting
     * this one.
     */
    private static function translateStatus(string $status): PaymentStatus
    {
        return match ($status) {
            'captured', 'refunded' => PaymentStatus::Captured,
            'authorized' => PaymentStatus::Authorized,
            'failed' => PaymentStatus::Failed,
            default => PaymentStatus::Created,
        };
    }

    /** @return array<string, mixed> */
    private function post(string $path, array $payload): array
    {
        return $this->send('post', $path, $payload);
    }

    /** @return array<string, mixed> */
    private function get(string $path): array
    {
        return $this->send('get', $path, null);
    }

    /**
     * @param  array<string, mixed>|null  $payload
     * @return array<string, mixed>
     */
    private function send(string $method, string $path, ?array $payload): array
    {
        try {
            $request = Http::withBasicAuth($this->keyId, $this->keySecret)
                ->acceptJson()
                ->timeout($this->timeoutSeconds);

            $response = $method === 'post'
                ? $request->post(self::BASE_URL.$path, $payload ?? [])
                : $request->get(self::BASE_URL.$path);
        } catch (ConnectionException $e) {
            // The message, not the exception: a stack trace from an HTTP client
            // can carry the Authorization header, and this line goes to a log
            // somebody else reads.
            Log::error('payments.razorpay_unreachable', ['path' => $path, 'reason' => $e->getMessage()]);

            throw new PaymentGatewayException('Razorpay could not be reached.');
        } catch (Throwable) {
            Log::error('payments.razorpay_transport_failed', ['path' => $path]);

            throw new PaymentGatewayException('Razorpay request failed.');
        }

        if ($response->failed()) {
            // Razorpay's own description is safe to log — it describes the
            // request, not the payer. The body is not logged wholesale.
            Log::warning('payments.razorpay_rejected', [
                'path' => $path,
                'status' => $response->status(),
                'code' => $response->json('error.code'),
            ]);

            throw new PaymentGatewayException(
                'Razorpay refused the request with status '.$response->status().'.',
            );
        }

        $body = $response->json();

        if (! is_array($body)) {
            throw new PaymentGatewayException('Razorpay returned a response that was not an object.');
        }

        return $body;
    }
}
