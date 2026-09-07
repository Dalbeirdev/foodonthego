<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Enums\ApiErrorCode;
use Carbon\CarbonImmutable;

/**
 * Everything the server worked out about when this cart could be collected.
 *
 * A plan is produced even when no pickup is possible. A refusal with the
 * arithmetic attached — "the kitchen needs twenty-five minutes and you would
 * arrive after they close" — is something a screen can explain; a bare error is
 * something a customer has to guess at.
 *
 * The client renders these figures. It computes none of them and decides
 * nothing from them: whether a pickup time is valid is a question only the
 * server answers, and it answers it again at selection and again at
 * pre-checkout.
 */
final readonly class PickupPlan
{
    /**
     * @param  list<PickupWindow>  $windows  the options offered, already capped
     */
    public function __construct(
        /** Authoritative server time this was planned against. Never a device clock. */
        public CarbonImmutable $serverNow,
        public ?ArrivalEstimate $arrival,
        public PreparationEstimate $preparation,
        public int $bufferMinutes,
        public int $minimumLeadMinutes,
        public ?CarbonImmutable $earliestReadyAt,
        public ?PickupWindow $recommended,
        public array $windows,
        public string $fingerprint,
        public string $timezone,
        public bool $requiresRouteRefresh,
        /** Why no pickup can be offered, or null when one can. */
        public ?ApiErrorCode $refusal,
    ) {}

    public function isFeasible(): bool
    {
        return $this->refusal === null && $this->windows !== [];
    }

    /**
     * The customer-facing shape.
     *
     * What is here: the times, and the three durations that explain them.
     *
     * What is deliberately NOT here, and must not be added: the per-line
     * preparation breakdown, any restaurant capacity or staffing figure, the
     * ranking arithmetic behind the recommendation, internal ids, and anything
     * from an operator's private columns. A customer needs to know when their
     * food is ready; a competitor would like to know how the kitchen is run.
     *
     * The window instants carry their offset and the zone name travels beside
     * them, so the client formats without doing arithmetic — the one calculation
     * a client must never perform is the one this module exists to make
     * authoritative.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'server_now' => $this->serverNow->toIso8601String(),
            'timezone' => $this->timezone,
            'travel' => $this->arrival?->toApiArray(),
            'preparation' => $this->preparation->toApiArray(),
            'buffer_minutes' => $this->bufferMinutes,
            'minimum_lead_minutes' => $this->minimumLeadMinutes,
            'earliest_ready_at' => $this->earliestReadyAt?->toIso8601String(),
            'requires_route_refresh' => $this->requiresRouteRefresh,
            'is_feasible' => $this->isFeasible(),
            'reason' => $this->refusal?->value,
        ];
    }
}
