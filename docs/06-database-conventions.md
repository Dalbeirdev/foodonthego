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

### At most one of something per owner

MySQL 8 has no partial or filtered index, so "exactly one default address per customer" cannot be
expressed as `UNIQUE (customer_id) WHERE is_default`. It can be expressed as a stored generated
column that is the customer id when the row is the default and `NULL` otherwise, plus a plain unique
index over it — MySQL does not collide `NULL`s, so every non-default row is exempt and the defaults
are forced apart:

```php
$table->rawColumn(
    'default_for_customer',
    'bigint unsigned generated always as (if(is_default = 1, customer_id, null)) stored',
)->nullable();
$table->unique('default_for_customer', 'customer_addresses_one_default_unique');
```

Three things to know before reusing this:

- **`->nullable()` is not optional.** Laravel appends `NOT NULL` to a `rawColumn` without it, and
  then every non-default row stores `NULL`-as-not-null → `0`, and the second address a customer saves
  collides. It fails loudly and immediately, which is the good case; the point is that the pattern
  looks correct without it.
- **The column must be declared inside `CREATE TABLE`.** Adding it later by `ALTER TABLE` makes MySQL
  copy the table, and it cannot re-create the foreign key while it does — error 1215.
- **The referenced column can no longer be `ON DELETE CASCADE`.** MySQL refuses a cascade on a column
  a stored generated column depends on, also 1215. `customer_addresses.customer_id` is therefore
  `RESTRICT`, and deleting a customer means deleting their addresses first — recorded as KI-009 in
  [13-known-issues.md](13-known-issues.md) so the erasure path in a later module accounts for it.

The invariant is worth the friction: it holds against a direct `INSERT`, a future service that
forgets the rule, and a race between two concurrent writes. It is verified by a test that writes
around the service and asserts error 1062.

### Snapshot what a record means; reference only what it came from

A row that describes a decision — a journey, an order, an invoice line — stores
the values it was decided from, not a foreign key to somewhere they might later
change. Module 05's `trips` copies each end of a journey out of whatever produced it, and
keeps `origin_saved_address_id` alongside as provenance with
`ON DELETE SET NULL`.

Holding only the key is the tempting version and is wrong three ways: editing the
address silently rewrites history, deleting it either orphans the row or blocks
the delete, and any source that has no id at all (a typed place, an imported one)
needs a second representation of the same concept.

### A column nothing fills yet is a column not to add

`trips` has `route_status`, and no `distance`, `duration`, `polyline` or `eta`.
Those belong to Module 06. Adding them early costs nothing at the schema level
and a great deal at the screen level: a nullable numeric column is an invitation
to render "0 km" for a route nobody has calculated, and by the time somebody
notices, the placeholder has been read as a real answer.

The state that *is* recorded is the absence itself — `route_status` starts at
`NOT_CALCULATED` — so a client reads the answer rather than assuming it.

The rule of thumb: if a human would say "but that is what it *was* at the time",
snapshot it.

## Soft deletes and audit

A deleted row stays, so a deletion is recoverable and audit rows keep their foreign keys. Anything
that must not be resurrected — a payment token, a personal-data erasure — is a hard delete plus an
audit entry, decided in the module that owns it.

## Indexes

Add an index for a query you have, not one you imagine. `users` carries `(role, is_active)` because
the admin list filters on exactly that pair, and `created_at` because it sorts on it.

Index before a feature ships, not after it is slow in production — but only where the query exists.

`customer_addresses` carries `(customer_id, is_default)` because the list query sorts defaults first,
and `(customer_id, type)` because the picker groups by type. It does not carry an index on
`place_id`: nothing looks an address up that way yet.

`trip_routes` carries `(trip_id, provider_route_index)` as a unique key — a
provider's own ordering is the natural identity of a route within a trip — and
`(trip_id, is_selected)` because every read of a trip's routes wants the selected
one first.

### A uniqueness rule the application cannot break

"Exactly one selected route per trip" is enforced by the schema rather than by
the service that writes it:

```php
$table->unsignedBigInteger('selected_trip_id')->nullable()
    ->virtualAs('CASE WHEN is_selected = 1 THEN trip_id ELSE NULL END');
$table->unique('selected_trip_id', 'trip_routes_one_selected_per_trip');
```

MySQL ignores NULLs in a unique index, so unselected rows never collide and two
selected rows for the same trip cannot exist. Two concurrent selections cannot
both win, whatever order the application happens to run in. This is the pattern
to reach for whenever "only one of these may be true at a time" matters —
`customer_addresses.is_default` is enforced in the service, and would be better
enforced here.

### Empty `$fillable` where the values are not the client's

`TripRoute` declares no fillable attributes at all. Every column is assigned
explicitly from a validated provider response. A model whose values must never
come from a request is clearer with an empty `$fillable` than with a `$guarded`
list somebody has to keep in step with the migration.

`restaurants` carries two indexes and no more: `(latitude, longitude)` for the
corridor's bounding-box range, and `(status, verification_status,
is_discoverable)` for the eligibility filter every discovery query applies.
Latitude leads the position index because it is the selective half — a
Delhi-Jaipur corridor is three degrees of latitude out of the thirty India spans.

### Spatial types, and why not yet

MySQL 8 supports `POINT` with SRID 4326 and `SPATIAL INDEX`, and that would be
the better tool for a corridor search — **once coordinates are mandatory**. A
spatial index requires a `NOT NULL` column, and `restaurants.latitude` is
deliberately nullable: a restaurant whose position has never been established is
not route-discoverable, and the only alternative to a nullable column is a
fabricated point.

So two `DECIMAL(10,7)` columns are the single source of truth and there is **no
parallel `POINT` column to drift out of step with them**. The upgrade path is
written down in `22-restaurant-route-discovery.md`, including the detail that
sinks people: coordinate order inside a 4326 `POINT` is latitude, longitude —
the opposite of GeoJSON.

### Attribute tables rather than JSON columns

`restaurant_cuisines`, `restaurant_facilities` and `restaurant_opening_hours` are
tables because the next module filters on all three, and **a JSON column that has
to be filtered is a table that has not been written yet**. The cost of
normalising them is three extra queries per request — eager-loaded, not per row.

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
