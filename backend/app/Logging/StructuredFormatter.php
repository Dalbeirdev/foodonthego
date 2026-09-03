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
    ];

    private const REDACTED = '[REDACTED]';

    public function format(LogRecord $record): string
    {
        $payload = [
            'timestamp' => $record->datetime->format(DATE_RFC3339_EXTENDED),
            'level' => $record->level->getName(),
            'channel' => $record->channel,
            'message' => $record->message,
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

            $clean[$key] = is_array($value) ? $this->redact($value, $depth + 1) : $value;
        }

        return $clean;
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
