<?php

declare(strict_types=1);

namespace App\Services\Otp\Providers;

use App\Services\Otp\OtpDeliveryFailed;
use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\OtpDeliveryReceipt;
use App\Support\Phone\PhoneNumber;

/**
 * The production default until a real SMS vendor is configured.
 *
 * It **fails loudly** rather than pretending. The alternative — silently
 * succeeding — would tell every customer a code was on its way and leave them
 * waiting for an SMS that was never sent, which is worse than an honest error.
 *
 * The vendor (MSG91, Twilio, SNS) is a configuration decision: implement this
 * interface, register it in `config/foodonthego.php`, and nothing else changes.
 */
final class UnconfiguredOtpProvider implements OtpDeliveryProvider
{
    public function send(PhoneNumber $phone, string $code): OtpDeliveryReceipt
    {
        throw new OtpDeliveryFailed(
            'unconfigured',
            'No SMS provider is configured. Set OTP_PROVIDER and its credentials.',
        );
    }

    public function name(): string
    {
        return 'unconfigured';
    }

    public function deliversToRealDevices(): bool
    {
        // False, so the production configuration guard refuses to boot rather
        // than shipping an app whose sign-in cannot work.
        return false;
    }
}
