<?php

declare(strict_types=1);

namespace App\Logging;

use Illuminate\Log\Logger;
use Monolog\Logger as MonologLogger;

/**
 * A Monolog "tap" for the `structured` channel (config/logging.php).
 *
 * Laravel resolves the class listed under `tap` and calls it with the configured
 * Illuminate logger — NOT with the channel config array — so the signature below is
 * the contract. Getting it wrong throws only when something actually writes a log
 * line, which is why there is a test that asserts a line can be written and parsed.
 */
final class StructuredLogger
{
    public function __invoke(Logger $logger): void
    {
        $monolog = $logger->getLogger();

        /*
         | Narrowed rather than assumed.
         |
         | Laravel types getLogger() as the PSR LoggerInterface, which has no
         | getHandlers(); the object is a Monolog Logger and always has been,
         | so the call worked and static analysis was right to object anyway.
         | A driver that returned some other PSR logger would have fatalled
         | here on the first log line. Now it formats nothing instead, which is
         | the safer of the two ways to be wrong.
         */
        if (! $monolog instanceof MonologLogger) {
            return;
        }

        foreach ($monolog->getHandlers() as $handler) {
            if (method_exists($handler, 'setFormatter')) {
                $handler->setFormatter(new StructuredFormatter);
            }
        }
    }
}
