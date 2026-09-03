<?php

declare(strict_types=1);

namespace App\Logging;

use Illuminate\Log\Logger;

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
        foreach ($logger->getLogger()->getHandlers() as $handler) {
            if (method_exists($handler, 'setFormatter')) {
                $handler->setFormatter(new StructuredFormatter);
            }
        }
    }
}
