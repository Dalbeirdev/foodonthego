<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Otp\OtpDeliveryFailed;
use App\Services\Otp\Providers\TwilioOtpProvider;
use App\Support\Phone\PhoneNumber;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The Twilio provider, with no Twilio.
 *
 * Every request is faked. That is not a limitation being apologised for — these
 * tests are about the shape of what we send and, more importantly, about what
 * must never leave this process. A live call could not assert the second thing
 * at all.
 *
 * The failure cases matter more than the success case. {@see OtpDeliveryFailed}
 * makes the caller invalidate the challenge and tell the customer to try again,
 * so throwing it when Twilio actually did send means a customer holds a working
 * code they are told does not exist, and not throwing it when Twilio did not
 * means they wait for a message that is never coming.
 */
final class TwilioOtpProviderTest extends TestCase
{
    private function provider(
        ?string $messagingServiceSid = 'MG00000000000000000000000000000001',
        ?string $from = null,
        string $template = '{code} is your FoodOnTheGo verification code.',
    ): TwilioOtpProvider {
        return new TwilioOtpProvider(
            accountSid: 'AC00000000000000000000000000000001',
            apiKeySid: 'SK00000000000000000000000000000001',
            apiKeySecret: 'a-secret-that-must-never-be-logged',
            messagingServiceSid: $messagingServiceSid,
            from: $from,
            messageTemplate: $template,
            baseUrl: 'https://api.twilio.example',
        );
    }

    private function phone(): PhoneNumber
    {
        return new PhoneNumber('+919888772736', 'IN', '9888772736');
    }

    private function accepted(array $overrides = []): array
    {
        return array_merge([
            'sid' => 'SM00000000000000000000000000000009',
            'status' => 'queued',
        ], $overrides);
    }

    public function test_it_posts_the_code_to_the_accounts_messages_endpoint(): void
    {
        Http::fake(['*' => Http::response($this->accepted(), 201)]);

        $receipt = $this->provider()->send($this->phone(), '481592');

        self::assertSame('twilio', $receipt->provider);
        self::assertSame('SM00000000000000000000000000000009', $receipt->providerReference);

        Http::assertSent(function (Request $request): bool {
            self::assertSame(
                'https://api.twilio.example/2010-04-01/Accounts/AC00000000000000000000000000000001/Messages.json',
                $request->url(),
                'The account SID belongs in the path; Twilio routes on it.',
            );
            self::assertSame('POST', $request->method());
            self::assertSame('+919888772736', $request['To']);
            self::assertStringContainsString('481592', (string) $request['Body']);

            return true;
        });
    }

    public function test_it_authenticates_with_the_api_key_not_the_account_sid(): void
    {
        Http::fake(['*' => Http::response($this->accepted(), 201)]);

        $this->provider()->send($this->phone(), '481592');

        Http::assertSent(function (Request $request): bool {
            $header = $request->header('Authorization')[0] ?? '';
            self::assertStringStartsWith('Basic ', $header);

            $decoded = base64_decode(substr($header, 6), true);

            // The key SID is the username. Sending the account SID here works
            // against Twilio too — with the auth token as the password — and is
            // exactly the arrangement this provider exists to avoid.
            self::assertSame(
                'SK00000000000000000000000000000001:a-secret-that-must-never-be-logged',
                $decoded,
            );

            return true;
        });
    }

    public function test_a_messaging_service_is_sent_instead_of_a_from_number_never_both(): void
    {
        Http::fake(['*' => Http::response($this->accepted(), 201)]);

        $this->provider(messagingServiceSid: 'MG00000000000000000000000000000001', from: '+15005550006')
            ->send($this->phone(), '481592');

        Http::assertSent(function (Request $request): bool {
            $sent = $request->data();

            self::assertSame('MG00000000000000000000000000000001', $sent['MessagingServiceSid']);

            // Absent, not empty. Twilio rejects a request carrying both, so an
            // empty-string From would be sent and refused.
            self::assertArrayNotHasKey(
                'From',
                $sent,
                'Twilio rejects a request carrying both a messaging service and a From number.',
            );

            return true;
        });
    }

    public function test_a_from_number_is_used_when_no_messaging_service_is_configured(): void
    {
        Http::fake(['*' => Http::response($this->accepted(), 201)]);

        $this->provider(messagingServiceSid: null, from: '+15005550006')
            ->send($this->phone(), '481592');

        Http::assertSent(function (Request $request): bool {
            $sent = $request->data();

            self::assertSame('+15005550006', $sent['From']);
            self::assertArrayNotHasKey('MessagingServiceSid', $sent);

            return true;
        });
    }

    public function test_the_body_is_the_configured_template_with_the_code_substituted(): void
    {
        Http::fake(['*' => Http::response($this->accepted(), 201)]);

        // In India this text has to match a DLT-registered template character
        // for character. A provider that built its own sentence would send
        // something the carrier drops, and the API call would still succeed.
        $this->provider(template: 'Your code is {code}. Valid 5 minutes.')
            ->send($this->phone(), '481592');

        Http::assertSent(function (Request $request): bool {
            self::assertSame('Your code is 481592. Valid 5 minutes.', $request['Body']);

            return true;
        });
    }

    public function test_a_rejected_request_is_a_definite_failure_carrying_twilios_error_code(): void
    {
        Http::fake([
            '*' => Http::response([
                'code' => 21211,
                'message' => "The 'To' number is not a valid phone number.",
                'status' => 400,
            ], 400),
        ]);

        try {
            $this->provider()->send($this->phone(), '481592');
            self::fail('A 400 from Twilio must be reported as a definite failure.');
        } catch (OtpDeliveryFailed $failure) {
            self::assertSame('twilio', $failure->provider);
            self::assertSame('21211', $failure->providerCode);
            self::assertStringContainsString('400', $failure->getMessage());
        }
    }

    public function test_a_message_created_already_failed_is_a_failure_despite_the_201(): void
    {
        // Twilio answers 201 Created and the message is dead on arrival. Reading
        // only the status code would tell the customer a code is on its way.
        Http::fake([
            '*' => Http::response($this->accepted([
                'status' => 'failed',
                'error_code' => 30008,
            ]), 201),
        ]);

        $this->expectException(OtpDeliveryFailed::class);
        $this->expectExceptionMessageMatches('/status "failed"/');

        $this->provider()->send($this->phone(), '481592');
    }

    public function test_a_queued_message_is_a_success_because_that_is_all_an_sms_api_can_promise(): void
    {
        Http::fake(['*' => Http::response($this->accepted(['status' => 'accepted']), 201)]);

        // Throwing here would invalidate the challenge for a code Twilio is
        // about to deliver, leaving the customer holding a working code the
        // server has already thrown away.
        $receipt = $this->provider()->send($this->phone(), '481592');

        self::assertSame('SM00000000000000000000000000000009', $receipt->providerReference);
    }

    public function test_a_transport_failure_is_a_definite_failure(): void
    {
        Http::fake(fn () => throw new ConnectionException('Connection timed out'));

        $this->expectException(OtpDeliveryFailed::class);
        $this->expectExceptionMessageMatches('/Could not reach Twilio/');

        $this->provider()->send($this->phone(), '481592');
    }

    /**
     * The one that matters most.
     *
     * A failure message reaches a log line. If it carried the code, every failed
     * send would write a live one-time code to the application log — which is
     * precisely the property that makes LogOtpProvider unfit for production, and
     * it would have been reintroduced through the error path of the provider
     * that replaced it.
     */
    public function test_no_failure_message_ever_contains_the_code_or_the_credential(): void
    {
        $cases = [
            'rejected' => fn () => Http::fake(['*' => Http::response(['code' => 21608, 'message' => 'x'], 400)]),
            'created failed' => fn () => Http::fake([
                '*' => Http::response(['sid' => 'SM1', 'status' => 'failed'], 201),
            ]),
            'transport' => fn () => Http::fake(fn () => throw new ConnectionException('timed out')),
        ];

        foreach ($cases as $label => $arrange) {
            $arrange();

            try {
                $this->provider()->send($this->phone(), '481592');
                self::fail("The '$label' case was expected to fail.");
            } catch (OtpDeliveryFailed $failure) {
                self::assertStringNotContainsString(
                    '481592',
                    $failure->getMessage(),
                    "The '$label' failure message carries the one-time code into the log.",
                );
                self::assertStringNotContainsString(
                    'a-secret-that-must-never-be-logged',
                    $failure->getMessage(),
                    "The '$label' failure message carries the API key secret into the log.",
                );
            }
        }
    }

    public function test_the_receipt_carries_a_reference_and_never_the_code(): void
    {
        Http::fake(['*' => Http::response($this->accepted(), 201)]);

        $receipt = $this->provider()->send($this->phone(), '481592');

        self::assertStringNotContainsString('481592', (string) $receipt->providerReference);
    }

    public function test_it_reports_that_it_reaches_real_devices(): void
    {
        // The production guard boots or refuses on this answer alone.
        self::assertTrue($this->provider()->deliversToRealDevices());
        self::assertSame('twilio', $this->provider()->name());
    }

    /**
     * A key present but blank in a .env file reads as an empty string, not as
     * absent, so `env('X', $default)` returns '' and the default never applies.
     *
     * This is here because it caught me: .env.example ships these keys blank so
     * an operator can see what to fill in, and copying it unedited would have
     * produced a zero timeout — which Guzzle reads as "wait forever" — and a
     * message template with no {code} in it. Both would have shipped looking
     * configured.
     */
    public function test_a_blank_setting_falls_back_to_the_default_rather_than_an_empty_string(): void
    {
        config(['foodonthego.otp.twilio' => null]);
        $this->refreshApplication();

        // Simulates .env.example copied without editing: keys present, blank.
        putenv('TWILIO_TIMEOUT_SECONDS=');
        putenv('TWILIO_MESSAGE_TEMPLATE=');
        putenv('TWILIO_BASE_URL=');

        try {
            $settings = require base_path('config/foodonthego.php');
            $twilio = $settings['otp']['twilio'];

            self::assertSame(10, $twilio['timeout_seconds'], 'A zero timeout means no timeout at all.');
            self::assertStringContainsString(
                '{code}',
                (string) $twilio['message_template'],
                'A blank template would send a well-formed SMS containing no code.',
            );
            self::assertSame('https://api.twilio.com', $twilio['base_url']);
        } finally {
            putenv('TWILIO_TIMEOUT_SECONDS');
            putenv('TWILIO_MESSAGE_TEMPLATE');
            putenv('TWILIO_BASE_URL');
        }
    }
}
