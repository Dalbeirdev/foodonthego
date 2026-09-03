<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Services\Otp\OtpDeliveryFailed;
use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\OtpDeliveryReceipt;
use App\Support\Phone\PhoneNumber;

/**
 * A test double that stands in for an SMS vendor.
 *
 * It keeps the codes it was asked to send so a test can complete a real
 * verification round trip. That is only acceptable because these codes are
 * generated for the test process and never reach a handset — the production path
 * has no equivalent: the code exists as a local variable inside
 * OtpChallengeService::issue() and is never returned, logged or stored in
 * plaintext anywhere.
 */
final class RecordingOtpProvider implements OtpDeliveryProvider
{
    /** @var list<array{phone: string, code: string}> */
    public array $sent = [];

    public bool $shouldFail = false;

    // A property and a method may share a name in PHP; keeping them identical
    // makes the call site read as the thing being configured.
    public function __construct(private readonly bool $deliversToRealDevices = true) {}

    public function send(PhoneNumber $phone, string $code): OtpDeliveryReceipt
    {
        if ($this->shouldFail) {
            throw new OtpDeliveryFailed($this->name(), 'Simulated provider outage.', 'SIMULATED');
        }

        $this->sent[] = ['phone' => $phone->e164, 'code' => $code];

        return new OtpDeliveryReceipt($this->name(), 'test-'.count($this->sent));
    }

    public function name(): string
    {
        return 'recording';
    }

    public function deliversToRealDevices(): bool
    {
        return $this->deliversToRealDevices;
    }

    /** The code most recently handed to this provider. */
    public function lastCode(): string
    {
        $last = end($this->sent);

        if ($last === false) {
            throw new \RuntimeException('No OTP has been sent.');
        }

        return $last['code'];
    }

    public function count(): int
    {
        return count($this->sent);
    }
}
