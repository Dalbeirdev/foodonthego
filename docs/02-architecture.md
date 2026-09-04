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

## Where a customer's own data lives

Module 04 added the first table a customer both owns and writes: `customer_addresses`. Two structural
decisions in it are worth stating at the architecture level, because later modules inherit them.

**Ownership is a property of the route shape, not of a check inside the handler.** No self-service
route carries a customer identifier — the paths are `/api/v1/customer/profile`,
`/api/v1/customer/addresses/{uuid}` and `/api/v1/customer/trips/{uuid}`, and the owner is read from the Sanctum token. There is nothing
in the request for a caller to tamper with, so an ownership bug cannot be introduced by forgetting a
comparison; it would have to be introduced by adding a parameter that does not exist. Every read of
an address goes through one method, `CustomerAddressService::ownedByOrFail()`, which answers 404 for
both "no such address" and "not yours" so the endpoint cannot be used to enumerate identifiers.

**Invariants that the product depends on are enforced by the schema, not by the service.** "At most
one default address per customer" is a stored generated column plus a unique index, so a second
default cannot be written even by a direct `INSERT` that bypasses every line of PHP. The pattern is
described in [06-database-conventions.md](06-database-conventions.md#at-most-one-of-something-per-owner).

The same principle runs into the client. `AddressesController` in Flutter *watches* the auth state
rather than subscribing to a logout event, so ending a session rebuilds the provider from nothing —
one customer's addresses cannot survive into another customer's session, because there is no cached
state that outlives the session to forget to clear.

## Recording what somebody said, versus what is true

Modules 04 and 05 introduced a distinction the rest of the product inherits.

A saved address and a trip are **records of what a customer told us or chose**.
Neither carries anything derived, computed or observed: a saved address has no
coordinates until the customer locates it against a real place, a trip's
`route_status` is `NOT_CALCULATED` because nothing has calculated a route, and
the trip status enum has two cases because two is all this part of the system can
honestly establish.

The trip table takes the rule one step further: there is no `distance`,
`duration`, `polyline` or `eta` column at all. A nullable column is an invitation
to render "0 km" while it is still null; an absent one cannot be rendered.

The alternative — filling those fields with something plausible — is not a
shortcut, it is a corruption. A fabricated coordinate is indistinguishable from a
real one to the routing module that will consume it; an assumed travel state
becomes an assumed cooking time in a product whose entire proposition is cooking
at the right moment. Every nullable column in these two tables is a place where
the schema is ready and the data is honest about not being there yet.

The shape this takes in code is worth naming: **a record snapshots the values it
was decided from** rather than pointing at somewhere they might later change.
A trip copies each end out of whatever produced it — a saved address, a searched
place, a device fix — and keeps the address id only as provenance, so editing
that address cannot rewrite journeys already planned against it.

**Third-party credentials stay on the server.** The app never calls a place
provider: every lookup goes through `/customer/places/*`, so the key is in one
environment rather than in every installed bundle, and swapping providers is a
change to one adapter rather than an app release.

## What Module 01 deliberately did not build

No authentication, no domain tables beyond `users`, no feature endpoints. Module-specific migrations
belong to the modules that own them — creating thirty half-designed tables now would fix decisions
before the features that depend on them are understood.
