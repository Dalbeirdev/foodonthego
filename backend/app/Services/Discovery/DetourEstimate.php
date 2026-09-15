<?php

declare(strict_types=1);

namespace App\Services\Discovery;

/**
 * What stopping somewhere adds to a journey.
 *
 * Both figures are differences between two provider answers, not measurements in
 * their own right, and both are clamped at zero. `provider` travels with them so
 * a figure can always be traced to what produced it — and so a synthetic one
 * from the development stand-in is identifiable wherever it ends up.
 */
final readonly class DetourEstimate
{
    public function __construct(
        public int $extraDistanceMetres,
        public int $extraDurationSeconds,
        public string $provider,
    ) {}

    /** @return array{distance: int, duration: int, provider: string} */
    public function toArray(): array
    {
        return [
            'distance' => $this->extraDistanceMetres,
            'duration' => $this->extraDurationSeconds,
            'provider' => $this->provider,
        ];
    }

    /** @param array{distance: int, duration: int, provider: string} $cached */
    public static function fromArray(array $cached): self
    {
        return new self(
            extraDistanceMetres: (int) $cached['distance'],
            extraDurationSeconds: (int) $cached['duration'],
            provider: (string) $cached['provider'],
        );
    }

    public function isWithin(int $maxDistanceMetres, int $maxDurationSeconds): bool
    {
        return $this->extraDistanceMetres <= $maxDistanceMetres
            && $this->extraDurationSeconds <= $maxDurationSeconds;
    }
}
