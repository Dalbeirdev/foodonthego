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

---

## Generated columns for stable identifiers (Module 08)

`restaurant_cuisines.slug` and `restaurant_facilities.slug` are **stored
generated columns**:

```sql
slug VARCHAR(60) AS (LOWER(REGEXP_REPLACE(TRIM(cuisine), '[^a-zA-Z0-9]+', '_'))) STORED
```

The rule they exist to enforce: **a customer filters by an identifier, never by
a display label.** Deriving the identifier in PHP would mean two places that
must agree about what "North Indian" becomes, and one of them eventually
wouldn't. The database maintains it, on write, for every row, including rows
written by a migration or by hand.

Stored rather than virtual because it is indexed and read on every discovery
request; the write cost is paid once by an operator editing a menu.

Indexes added alongside them:

| Index | Columns | For |
| --- | --- | --- |
| `restaurant_cuisines_slug_index` | `(slug, restaurant_id)` | "which restaurants serve this" |
| `restaurant_facilities_slug_index` | `(slug, restaurant_id)` | the same, for facilities |
| `restaurants_name_index` | `(name)` | name search, and operator lookup |

### An index that was measured and then removed

A composite `(status, verification_status, is_discoverable, latitude)` index was
built to serve the corridor query. With 5,008 restaurants spread across India it
read 554 rows; the existing `restaurants_position_index` on `(latitude,
longitude)` read 585 for the same query. That is not a difference worth an
index, so it was reverted.

The measurement is kept in `docs/evidence/module-08-verification-run.txt` so the
next person does not repeat the experiment. **An index nobody has measured is a
write cost with a hypothesis attached.**

---

## A moderation gate is a default, not a check (Module 09)

`restaurant_media.is_active` defaults to **false**.

Photographs will arrive from an operator dashboard a later module builds. A
column defaulting to true means every code path that inserts one has to remember
to withhold it; a column defaulting to false means the one path that publishes
has to remember to say so. The second is the direction a forgotten line should
fall.

The relation enforces it too:

```php
public function media(): HasMany
{
    return $this->hasMany(RestaurantMedia::class)
        ->where('is_active', true)
        ->orderBy('position')->orderBy('id');
}
```

A query that forgets a scope still cannot reach an unmoderated image.

### Two columns, not one flag

`restaurants.public_phone` is separate from `restaurants.owner_phone`. A single
"phone" column with a visibility boolean is one forgotten `where` clause away
from publishing somebody's personal mobile; two columns cannot make that
mistake, because the private one is on `privateColumns()` and the customer
projection never mentions it.

### A gallery is a relation

Module 07 stored `logo_url` and `cover_image_url` on the restaurant row, which
is enough for a list card. `image_1_url` through `image_5_url` is a schema that
runs out; `restaurant_media` is not.

---

## Money is an integer, and the column says so (Module 10)

```php
$table->unsignedInteger('base_price_minor');
$table->char('currency', 3)->default('INR');
```

Paise, not rupees. `DECIMAL` would be defensible; `FLOAT` and `DOUBLE` are not,
and `unsignedInteger` adds one more thing the storage engine enforces — a
negative price cannot be written at all.

The currency is stored per item rather than per restaurant. A restaurant does
not have a currency; a **price** does, and the day one operator lists something
in a second currency the schema does not need changing.

---

## A composite foreign key can make a whole class of bug impossible (Module 10)

An item must belong to a category **of its own restaurant**. That is easy to
state, easy to check in a service, and easy for the next person to forget in a
new query. So it is not a check:

```php
// menu_categories — not redundant with the primary key: this is what lets
// menu_items carry a composite foreign key.
$table->unique(['id', 'restaurant_id'], 'menu_categories_id_restaurant_unique');

// menu_items
$table->foreign(['menu_category_id', 'restaurant_id'], 'menu_items_category_same_restaurant')
    ->references(['id', 'restaurant_id'])->on('menu_categories')->cascadeOnDelete();
```

With `restaurant_id` on both tables and that redundant-looking `UNIQUE`, MySQL
itself refuses to link restaurant A's item to restaurant B's category —
regardless of what a service, a seeder, a migration or a direct `INSERT` tries.
A test attempts exactly that and asserts `SQLSTATE[23000] … 1452`.

The cost is one denormalised column and one extra index. The benefit is that a
cross-tenant data leak in this relationship is not a bug that can be written.

**When to reach for this:** a foreign key whose validity depends on a shared
parent — an item and its category, an order line and its order, an address and
its customer. When the rule is "these two must belong to the same third thing",
the schema can say so.

One consequence worth knowing: deletion order matters. `MenuTestDataSeeder`
clears items before categories, because the composite key is what holds them
together.

---

## The composite-key pattern, six more times (Module 11)

Module 10 introduced `UNIQUE(id, parent_id)` plus a composite foreign key to
make "these two must belong to the same third thing" a constraint rather than a
check. Module 11 applied it wherever that sentence was true:

| Constraint | The sentence it enforces |
| --- | --- |
| `menu_item_variants_item_same_restaurant` | A size belongs to a dish **of its own restaurant** |
| `menu_modifier_options_group_same_restaurant` | An option belongs to a group **of its own restaurant** |
| `menu_item_modifier_group_item_same_restaurant` | A dish is asked a question **of its own restaurant** |
| `menu_item_modifier_group_group_same_restaurant` | …and the question belongs there too |
| `cart_items_cart_same_restaurant` | A line's dish comes from **its cart's** restaurant |
| `cart_items_item_same_restaurant` | …and that restaurant actually sells it |
| `cart_items_variant_same_item` | A line's size belongs to **its line's** dish |
| `cart_item_modifiers_option_same_group` | A line's option belongs to the group it is recorded under |

The last one is the clearest illustration of why this is worth the redundant
column: without it a cart line could store "Spice level: Extra Cheese", and every
downstream check would validate cleanly on data that is nonsense.

### A partial index, in a database that has none

At most one **active** cart per customer per journey:

```sql
active_flag AS (CASE WHEN status = 'ACTIVE' THEN 1 ELSE NULL END) STORED,
UNIQUE (customer_id, trip_id, active_flag)
```

NULLs do not collide in a unique index, so any number of closed carts may exist
and exactly one active one. Two simultaneous taps cannot create two carts —
which matters because the service's own read-then-write would otherwise have a
window between them.

**One gotcha worth writing down:** MySQL refuses a cascading foreign key on a
column used in a generated column's expression. The obvious version of this flag
(`CASE WHEN status='ACTIVE' THEN trip_id ELSE NULL END`) therefore cannot
coexist with `trip_id` cascading on delete — and a deleted trip must take its
carts with it. The flag is derived from `status` alone and `trip_id` goes in the
index instead, which is equivalent and legal.

### Delete order follows the keys

`MenuTestDataSeeder` clears pivot rows, then options, then groups, then variants,
then items, then categories. Every one of those tables is held to the next by a
composite key, and deleting upwards fails. Any script that empties menu data has
to follow the same order.
