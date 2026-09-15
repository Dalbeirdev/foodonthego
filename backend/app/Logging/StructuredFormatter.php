<?php

declare(strict_types=1);

namespace App\Logging;

use App\Support\RequestContext;
use Monolog\Formatter\JsonFormatter;
use Monolog\LogRecord;

/**
 * One JSON object per log line, carrying the correlation id and the authenticated
 * actor, with sensitive values redacted before they are ever written.
 *
 * Redaction happens here rather than at each call site on purpose: a call site that
 * forgets is the normal case, and a password reaching disk cannot be un-written.
 * The key list below is matched case-insensitively and applied at every depth.
 */
final class StructuredFormatter extends JsonFormatter
{
    /**
     * Substrings that make a key sensitive. Deliberately broad: `api_key`,
     * `authorization`, `card_number` and `otp_code` must all match.
     *
     * @var array<int, string>
     */
    private const SENSITIVE_KEYS = [
        'password', 'passwd', 'secret', 'token', 'authorization', 'auth',
        'otp', 'pin', 'cvv', 'cvc', 'card', 'pan', 'api_key', 'apikey',
        'private_key', 'credential', 'session', 'cookie', 'signature',
        // A PDO driver's own error payload. It carries the offending *value* of
        // whatever constraint was violated, which for `users_phone_e164_unique`
        // is a customer's phone number.
        'errorinfo',
    ];

    /**
     * Values a database driver puts in an error message.
     *
     * A constraint violation names the value that violated it — "Duplicate entry
     * '+919812345678' for key 'users.users_phone_e164_unique'" — and that message
     * reaches the log twice: once from Laravel's own reporting, and once from
     * this application's `api.unhandled_exception` line. Both are scrubbed here,
     * because redaction belongs in one place and a call site that forgets is the
     * normal case.
     *
     * The constraint name survives. That is the operationally useful half, and it
     * says nothing about anybody.
     *
     * @var array<int, string>
     */
    private const MESSAGE_PATTERNS = [
        // Laravel appends the whole statement **with its bindings inlined** to
        // every QueryException message: "(Connection: mysql, …, SQL: insert into
        // `users` (`phone_e164`) values (+919999900101))". Everything from
        // `(Connection:` onwards is dropped, which is the only reliable rule —
        // the values are positional and unquoted, so there is nothing narrower
        // to match. The SQLSTATE, the driver's own text and the constraint name
        // all come before it and survive.
        '/\\(Connection: .*$/s',

        // And the driver's own text names the offending value before that point.
        "/(Duplicate entry )'[^']*'/i",
        "/(Data too long for column '[^']*' at row )\\d+/i",
        "/(Incorrect \\w+ value: )'[^']*'/i",
    ];

    private const REDACTED = '[REDACTED]';

    public function format(LogRecord $record): string
    {
        $payload = [
            'timestamp' => $record->datetime->format(DATE_RFC3339_EXTENDED),
            'level' => $record->level->getName(),
            'channel' => $record->channel,
            'message' => $this->scrub($record->message),
            'request_id' => RequestContext::id(),
            'actor_id' => RequestContext::actorId(),
            'actor_role' => RequestContext::actorRole(),
            'context' => $this->redact($record->context),
        ];

        return json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE)."\n";
    }

    /**
     * @param  array<array-key, mixed>  $data
     * @return array<array-key, mixed>
     */
    private function redact(array $data, int $depth = 0): array
    {
        // A cycle or a pathologically nested payload must not turn a log write into
        // a stack overflow, so recursion is bounded.
        if ($depth > 8) {
            return ['[TRUNCATED]'];
        }

        $clean = [];

        foreach ($data as $key => $value) {
            if (is_string($key) && $this->isSensitive($key)) {
                $clean[$key] = self::REDACTED;

                continue;
            }

            $clean[$key] = match (true) {
                is_array($value) => $this->redact($value, $depth + 1),

                // A throwable in context is serialised by `json_encode` through
                // its **public properties**, which for a PDOException means
                // `errorInfo` — and that is how a customer's phone number
                // reached this log. Only the three facts worth having survive.
                $value instanceof \Throwable => [
                    'class' => $value::class,
                    'file' => $value->getFile(),
                    'line' => $value->getLine(),
                ],

                is_string($value) => $this->scrub($value),

                default => $value,
            };
        }

        return $clean;
    }

    /** Removes the values a database driver names in its error messages. */
    private function scrub(string $message): string
    {
        // The first pattern has no capture group — it removes a tail rather than
        // replacing a value inside one — so it is applied on its own.
        $message = (string) preg_replace(
            self::MESSAGE_PATTERNS[0],
            '(Connection: '.self::REDACTED.')',
            $message,
        );

        foreach (array_slice(self::MESSAGE_PATTERNS, 1) as $pattern) {
            $message = (string) preg_replace($pattern, '$1'.self::REDACTED, $message);
        }

        return $message;
    }

    private function isSensitive(string $key): bool
    {
        $needle = strtolower($key);

        foreach (self::SENSITIVE_KEYS as $sensitive) {
            if (str_contains($needle, $sensitive)) {
                return true;
            }
        }

        return false;
    }
}
