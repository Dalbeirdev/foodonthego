# 02 — Architecture

```
┌──────────────────┐   ┌─────────────────────┐   ┌──────────────────┐
│  Customer app    │   │ Restaurant dashboard│   │   Admin panel    │
│  Flutter         │   │ React + TypeScript  │   │ React+TypeScript │
│  Android · iOS   │   │ :5173               │   │ :5174            │
└────────┬─────────┘   └──────────┬──────────┘   └────────┬─────────┘
         │                        │                       │
         └────────────────────────┼───────────────────────┘
                                  │  HTTPS · /api/v1 · JSON
                        ┌─────────▼──────────┐
                        │  Laravel 12 API    │
                        │  PHP 8.4 · :8000   │
                        └───┬────────────┬───┘
                            │            │
                  ┌─────────▼──┐   ┌─────▼──────────┐
                  │  MySQL 8   │   │   Redis 7      │
                  │ source of  │   │ cache · queues │
                  │   truth    │   │ locks · limits │
                  └────────────┘   └────────────────┘
```

## Repository layout

```
backend/          Laravel 12 API — all business rules live here
web/              npm workspaces
  packages/ui/      @fotg/ui — design tokens, AppShell, primitives, API client
  apps/restaurant/  @fotg/restaurant — restaurant dashboard
  apps/admin/       @fotg/admin — platform admin panel
mobile/           Flutter customer app
  lib/core/         theme, router, config
  lib/features/     one folder per feature area
  lib/shared/       widgets used by more than one feature
docs/             this documentation set
infrastructure/   deployment and environment material
```

## The rule that keeps this coherent

**Business rules live in the backend and nowhere else.**

Order state, pricing, commission, refund eligibility and — above all — the ETA calculation are
computed in Laravel. Flutter and React render what the API tells them.

This is not architectural preference. Three clients that each compute an ETA will disagree, and the
one the customer sees will not be the one the kitchen cooks to. When a client needs to show a
derived value, the API sends the value, not the inputs.

## Why MySQL is the source of truth and Redis is not

Redis holds cache entries, queue jobs, rate-limit counters, distributed locks, OTP state and
short-lived session data. It is configured without persistence in development and must be treated
as **lossy** everywhere.

Orders, payments, refunds and payouts are written to MySQL, in transactions. If Redis is flushed the
platform loses throughput and some cached reads; it must never lose an order or a payment.

## Shared design system, two implementations

`web/packages/ui/src/tokens.css` and `mobile/lib/core/theme/tokens.dart` hold the same palette,
spacing scale, radii and durations. Two platforms cannot share a stylesheet, so the contract between
them is [08-design-system.md](08-design-system.md); a change to one is a change to both.

## What Module 01 deliberately did not build

No authentication, no domain tables beyond `users`, no feature endpoints. Module-specific migrations
belong to the modules that own them — creating thirty half-designed tables now would fix decisions
before the features that depend on them are understood.
