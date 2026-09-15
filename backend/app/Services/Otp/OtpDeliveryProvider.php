<?php

declare(strict_types=1);

namespace App\Services\Otp;

use App\Support\Phone\PhoneNumber;

/**
 * How a one-time code reaches a phone.
 *
 * The interface exists so the SMS vendor is a configuration decision rather than
 * a rewrite. Business logic — challenge creation, hashing, expiry, attempt limits —
 * lives in {@see OtpChallengeService} and knows nothing about who sends the SMS.
 */
interface OtpDeliveryProvider
{
    /**
     * @throws OtpDeliveryFailed when the code definitely was not sent.
     */
    public function send(PhoneNumber $phone, string $code): OtpDeliveryReceipt;

    /** Identifies the provider in logs and in the health endpoint. */
    public function name(): string;

    /**
     * Whether this provider can actually deliver to a real handset.
     *
     * The development provider returns false, and the production configuration
     * guard refuses to boot a production deployment wired to one — otherwise a
     * misconfigured release would silently accept a code nobody ever received.
     */
    public function deliversToRealDevices(): bool;
}
