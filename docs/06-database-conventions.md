# 06 — Database conventions

MySQL 8, InnoDB, `utf8mb4` / `utf8mb4_0900_ai_ci`.

## Keys

Every table has **both**:

- `id` — `BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY`. InnoDB clusters on the primary key; a random
  UUID primary key fragments every insert and bloats every secondary index.
- `uuid` — indexed, unique, assigned by the model on create. **This is what the API exposes.**
  Sequential ids in URLs let anyone count our customers and walk to the next one.

Models set `getRouteKeyName()` to `uuid`.

## Columns

| Concern | Convention |
| --- | --- |
| Naming | `snake_case`; booleans read as assertions (`is_active`) |
| Timestamps | `created_at` / `updated_at` on every table |
| Soft deletes | `deleted_at` on anything a human can remove |
| Money | Integer minor units (`total_cents`). **Never** FLOAT or DOUBLE |
| Enums | MySQL `ENUM` mirroring a PHP backed enum, stored as strings |
| Foreign keys | Always declared, always named, always with an explicit `ON DELETE` |

### `ON DELETE` is a decision, not a default

- `cascade` — the child is meaningless alone (a menu item without its restaurant)
- `restrict` — deleting would destroy history (a user with orders)
- `set null` — the link is optional (an order's courier)

## Soft deletes and audit

A deleted row stays, so a deletion is recoverable and audit rows keep their foreign keys. Anything
that must not be resurrected — a payment token, a personal-data erasure — is a hard delete plus an
audit entry, decided in the module that owns it.

## Indexes

Add an index for a query you have, not one you imagine. `users` carries `(role, is_active)` because
the admin list filters on exactly that pair, and `created_at` because it sorts on it.

Index before a feature ships, not after it is slow in production — but only where the query exists.

## Migrations

- One migration per change; never edit a migration that has run anywhere but locally.
- Module-specific migrations belong to the module that owns them. Module 01 creates only `users`,
  `password_reset_tokens`, `sessions`, plus Laravel's `cache` and `jobs` tables.
- Every migration has a working `down()`.

## Personal data has a retention policy

A table that records *who tried to do what and when* is personal data, and keeping it forever only
widens what a compromise discloses. `otp_challenges` rows are deleted 48 hours after they become
unusable (`php artisan otp:prune`, scheduled daily).

Two rules the pruner follows, both worth copying when the next such table appears:

- a row that is still **usable** is never deleted however old it is — deleting a live OTP challenge
  would show "code expired" to somebody looking at the SMS on their screen;
- pruning never touches rate-limit counters, which would hand an attacker a fresh budget.

## Tests run against real MySQL

`phpunit.xml` pins `DB_CONNECTION=mysql`. The schema uses MySQL types (`ENUM`, `utf8mb4` collation)
and later modules will use MySQL locking semantics — a SQLite test run would pass against a schema
production cannot create.
