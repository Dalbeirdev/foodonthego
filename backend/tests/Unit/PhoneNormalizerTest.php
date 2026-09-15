<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\Phone\PhoneNormalizer;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * The one property that matters here: **every way a human can type one number
 * must produce one identity.** If it does not, the same person ends up with two
 * accounts, two order histories and a support ticket nobody can resolve.
 */
final class PhoneNormalizerTest extends TestCase
{
    /** @return array<string, array{0: string}> */
    public static function sameIndianNumber(): array
    {
        return [
            'plain' => ['9876543210'],
            'with trunk zero' => ['09876543210'],
            'with country code, no plus' => ['919876543210'],
            'e164' => ['+919876543210'],
            'spaced' => ['+91 98765 43210'],
            'dashed' => ['+91-98765-43210'],
            'bracketed' => ['+91 (98765) 43210'],
            'dotted' => ['98765.43210'],
            'surrounding whitespace' => ['  9876543210  '],
        ];
    }

    #[DataProvider('sameIndianNumber')]
    public function test_every_written_form_of_one_number_normalizes_to_the_same_identity(string $input): void
    {
        $phone = PhoneNormalizer::normalize($input);

        $this->assertNotNull($phone, "Failed to normalize: {$input}");
        $this->assertSame('+919876543210', $phone->e164);
        $this->assertSame('91', $phone->countryCode);
        $this->assertSame('9876543210', $phone->nationalNumber);
    }

    /** @return array<string, array{0: string}> */
    public static function unusableInput(): array
    {
        return [
            'empty' => [''],
            'whitespace only' => ['   '],
            'too short' => ['98765'],
            'too long' => ['98765432109876'],
            'letters' => ['98765ABCDE'],
            'sql-ish' => ["9876543210' OR 1=1--"],
            'script tag' => ['<script>alert(1)</script>'],
            'landline prefix' => ['1234567890'],
            'unsupported country' => ['+3312345678'],
            'plus only' => ['+'],
            'zeros only' => ['0000000000'],
        ];
    }

    #[DataProvider('unusableInput')]
    public function test_input_we_cannot_serve_is_rejected_rather_than_guessed_at(string $input): void
    {
        $this->assertNull(PhoneNormalizer::normalize($input));
    }

    public function test_an_indian_landline_prefix_is_rejected_because_it_cannot_receive_an_sms(): void
    {
        // 2-5 are landline ranges; sending an SMS there is a wasted charge and a
        // customer stuck on a screen waiting for a code that will never arrive.
        foreach (['2', '3', '4', '5'] as $prefix) {
            $this->assertNull(PhoneNormalizer::normalize($prefix.'876543210'), "Prefix {$prefix} should be rejected");
        }
    }

    public function test_the_longest_calling_code_wins_so_that_one_does_not_shadow_ninety_one(): void
    {
        // '+91...' must not be read as US '+1' followed by a national number.
        $this->assertSame('91', PhoneNormalizer::normalize('+919876543210')?->countryCode);
        $this->assertSame('971', PhoneNormalizer::normalize('+971501234567')?->countryCode);
        $this->assertSame('1', PhoneNormalizer::normalize('+12125550123')?->countryCode);
    }

    public function test_a_default_country_applies_only_when_the_input_has_no_plus(): void
    {
        $this->assertSame('+447700900123', PhoneNormalizer::normalize('7700900123', '44')?->e164);

        // An explicit +91 is not overridden by a default of 44.
        $this->assertSame('+919876543210', PhoneNormalizer::normalize('+919876543210', '44')?->e164);
    }

    public function test_an_unsupported_default_country_normalizes_to_nothing(): void
    {
        $this->assertNull(PhoneNormalizer::normalize('612345678', '33'));
    }

    public function test_the_supported_country_list_is_what_the_client_country_picker_offers(): void
    {
        $codes = array_column(PhoneNormalizer::supportedCountries(), 'code');

        $this->assertContains('91', $codes);
        $this->assertTrue(PhoneNormalizer::isSupportedCountry('91'));
        $this->assertFalse(PhoneNormalizer::isSupportedCountry('33'));

        foreach (PhoneNormalizer::supportedCountries() as $country) {
            $this->assertArrayHasKey('iso', $country);
            $this->assertArrayHasKey('name', $country);
        }
    }

    public function test_masking_reveals_only_the_last_four_digits(): void
    {
        $masked = PhoneNormalizer::normalize('+919876543210')?->masked();

        $this->assertSame('+91 ••••••3210', $masked);
        $this->assertStringNotContainsString('98765', (string) $masked);
    }

    public function test_the_logging_form_is_the_masked_form(): void
    {
        $phone = PhoneNormalizer::normalize('+919876543210');

        // A full number in a log line is a disclosure that outlives the request.
        $this->assertSame($phone?->masked(), $phone?->forLogging());
        $this->assertStringNotContainsString('9876543210', (string) $phone?->forLogging());
    }
}
