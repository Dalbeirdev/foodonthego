# 26 — Menu item details, variants, add-ons, customization and Add to Cart

Module 10 answers "what can I eat here, and what does it cost?". Module 11
answers the question a customer asks the moment they have chosen something:

> **How do I want it, and how many?**

And it answers the question the *platform* has to get right at the same moment:

> **What does that actually cost, and who decides?**

---

## The one rule everything else follows

**The customer says what they want. The server decides what it costs.**

There is no price field in the add-to-cart request. Not one that is ignored —
one that does not exist. `CustomizationSelection` carries which dish, which
size, which options, how many and a note, and nothing else. Every figure that
reaches the database is calculated by `MenuItemPricingService` from rows it read
in the same request.

A test sends `unit_price_minor`, `unit_price`, `line_total_minor`, `subtotal`,
`discount`, `tax`, `final_total` and `price` in one body and is charged ₹329,
which is what the dish costs.

### The one number the client does send, and why it is not a price

`quoted_unit_price_minor` is **what the customer was shown**. It is an assertion
about the screen, not an instruction about the bill:

- The server prices the configuration from its own rows, always.
- If its figure is **higher** than the quote, the add is refused with
  `PRICE_UPDATED` and the new figure, so the customer agrees before they pay.
- If it is **lower or equal**, the add proceeds at the server's figure.

Sending a high quote buys an attacker nothing — they pay the real price. Sending
a low one gets the add refused. Sending none is what an honest client that never
displayed a price would do, and the server's figure stands.

A price that has come **down** goes through silently. Nobody needs a
confirmation dialogue to be charged less.

---

## The customization model

### One system, not two

Add-ons are **modifier groups**. "Add extras · Optional · choose up to 2" with
paid options inside it *is* the add-on feature.

A separate `menu_item_addons` table was considered and rejected. It would mean a
second validator, a second pricing path, a second snapshot table and a second
set of availability rules, all doing what the modifier model already does. The
one thing it would buy — per-add-on quantities ("2 × extra cheese") — is not in
any real restaurant configuration here, and nothing in the schema prevents
adding it later as a column on the option.

**Decision: variants + modifier groups. No separate addon model.**

### Variants carry an absolute price

```
Regular  ₹249
Large    ₹329
```

`price_minor` is what the dish costs in that size, **not** what it costs extra.
A delta reads fine on a screen and is ambiguous in a column — is `8000` the
price or the increment? — and the ambiguity resolves wrongly exactly once, in
production, on somebody's bill.

A dish with no variants is priced from `menu_items.base_price_minor`. There is
no fabricated "Regular".

### Modifier options carry a delta

```
Mild            +₹0
Extra Cheese    +₹40
```

The opposite decision, for the opposite reason: "Extra cheese ₹40" has only one
reading. The column is **unsigned** — a negative modifier would be a discount,
and discounts are a pricing concern with an audit trail, not something to
smuggle in through a menu option.

### The rule is two numbers

| Rule | `min_select` | `max_select` |
| --- | --- | --- |
| Choose exactly 1 | 1 | 1 |
| Choose up to 3 | 0 | 3 |
| Choose 2 to 4 | 2 | 4 |

`is_required` is stored as well and **derived** when read (`min >= 1` wins), so
a row where the two disagree behaves the way the numbers say. A group configured
`min=2 max=1` is unsatisfiable; the ceiling is raised to meet the floor rather
than permanently refusing every add on that dish.

The numbers travel to the client, so the screen enforces the rule without
parsing English and a future locale does not have to translate a rule to make it
work.

### A paid option is never a default

`MenuModifierOption::isDefault()` returns true only when the option is *free*,
whatever the column says. Starting a customer at "Extra Cheese +₹40" and letting
them discover it at the total is a dark pattern, and this makes it something
somebody would have to deliberately write rather than accidentally configure.

Likewise, a **default variant that has gone unavailable is not a default** — the
screen asks rather than quoting a price for a size the kitchen cannot make.

---

## Five constraints that make bad data unwritable

| Constraint | What it prevents |
| --- | --- |
| `menu_item_variants_item_same_restaurant` | Restaurant A's "Large" filed under restaurant B's dish |
| `menu_modifier_options_group_same_restaurant` | An option in another restaurant's group |
| `menu_item_modifier_group_item_same_restaurant` + `…_group_same_restaurant` | A dish asked another restaurant's question |
| `cart_items_cart_same_restaurant` | A cart line holding a dish from a different restaurant than its cart |
| `cart_items_item_same_restaurant` | A cart line holding a dish that restaurant does not sell |
| `cart_items_variant_same_item` | A line holding a size that belongs to a different dish |
| `cart_item_modifiers_option_same_group` | A line claiming "Spice level: Extra Cheese" |

Each needs a redundant-looking `UNIQUE(id, parent_id)` on the referenced table,
because MySQL only accepts a foreign key that references a unique index. That is
the whole cost, and the benefit is that a cross-tenant leak in these
relationships is not a bug that can be written.

Module 10 established the pattern; this module used it six more times.

---

## The APIs

```
GET  /api/v1/customer/trips/{trip}/restaurants/{restaurant}/menu/items/{item}
POST /api/v1/customer/trips/{trip}/restaurants/{restaurant}/cart/items
GET  /api/v1/customer/trips/{trip}/cart
```

Nested under the restaurant, which is nested under the trip, for the same reason
the menu is: the path is what proves the customer is entitled to both.

### The item detail response gained a `customization` block

```json
"customization": {
  "variants": [
    { "id": "…", "name": "Regular", "price": {"amount_minor": 24900, "currency": "INR"},
      "is_default": true, "is_available": true, "preparation_minutes": null }
  ],
  "requires_variant": false,
  "modifier_groups": [
    { "id": "…", "name": "Spice level", "min_select": 1, "max_select": 1,
      "is_required": true, "is_single_select": true,
      "options": [ { "id": "…", "name": "Mild",
                     "price_delta": {"amount_minor": 0, "currency": "INR"},
                     "is_default": false, "is_available": true } ] }
  ],
  "limits": { "max_quantity": 20, "max_special_instructions": 300 }
}
```

The **limits travel with the item**, so the stepper and the note counter cannot
drift from what the server accepts.

A withdrawn size, option or group is **absent**. A sold-out one is **present and
disabled**: hiding it would leave a customer who came for the family portion
wondering whether they misremembered the menu.

### The add-to-cart request

```json
{
  "item_id": "…",
  "variant_id": "…",
  "modifier_groups": [ { "group_id": "…", "option_ids": ["…"] } ],
  "quantity": 2,
  "special_instructions": "Less spicy please",
  "quoted_unit_price_minor": 38900
}
```

A flat `modifier_option_ids` array is accepted too, because it is what a
hand-written client reaches for first.

**The `group_id` in the grouped shape is ignored.** An option already knows its
group; trusting the client's pairing would let a request claim "Spice level:
Extra Cheese" and have the stored breakdown agree with it.

### What the server does, in order

1. Trip ownership — somebody else's journey is *not found*, not refused.
2. Restaurant eligibility, through Module 09's `orderingContext()`.
3. Ordering state — a paused or closed kitchen takes no orders.
4. The dish, scoped to this restaurant.
5. Ownership of every id: the variant belongs to the dish, each option to a
   group this dish actually asks about.
6. Availability of each — item, variant, every option.
7. Every group's minimum and maximum.
8. Quantity and note length.
9. **Then** the price.
10. Cart scoping, and the write — in one transaction.

Ownership before availability, because a "you must choose a spice level" message
about a dish the customer is not looking at is nonsense. Availability before
price, because pricing something the kitchen has run out of is arithmetic nobody
needs.

---

## The cart foundation

Module 11 builds no cart *screen*. It builds the minimum that makes Add to Cart
mean something.

### Scoping, all of it enforced

**One active cart per customer per journey**, by a unique index on a generated
column:

```sql
active_flag AS (CASE WHEN status = 'ACTIVE' THEN 1 ELSE NULL END) STORED
UNIQUE (customer_id, trip_id, active_flag)
```

NULLs do not collide, so any number of closed carts may exist and exactly one
active one per journey. Two taps racing cannot make two carts.

*(The flag is derived from `status` alone, with `trip_id` in the index instead of
the expression, because MySQL refuses a cascading foreign key on a column used in
a generated column — and a deleted trip must take its carts with it.)*

**One restaurant per cart.** A pickup order is collected at a counter; two
counters is two orders.

**One currency per cart**, stored rather than derived.

### Conflicts refuse; they never mutate

| Situation | Answer |
| --- | --- |
| Cart holds another restaurant's food | `409 CART_RESTAURANT_CONFLICT`, naming the restaurant |
| Cart belongs to another journey | `409 CART_TRIP_CONFLICT` |

Nothing is merged and **nothing is emptied**. Destroying a customer's selections
to make an API call succeed is their decision, and the screen that lets them
make it is Module 12's. The response names the other restaurant so the client
can say *"Your cart has items from Highway Spice Kitchen"* rather than
*"conflict"*.

### Line matching

Two adds are the same line when the **configuration** matches: same dish, same
size, same options, same note. Quantity is deliberately not part of it — two of
a thing and three of a thing are the same thing in different amounts.

Options are **sorted before hashing**, so cheese-then-jalapeño is the same
configuration as jalapeño-then-cheese. A different note is a different line,
because "no onion" is not something the kitchen can merge with "extra onion".

The fingerprint is a `UNIQUE(cart_id, configuration_hash)`, and the read that
precedes the write is `lockForUpdate()` — so two simultaneous taps increment one
line rather than racing to create two.

### Snapshots

`item_name_snapshot`, `variant_name_snapshot`, `group_name_snapshot`,
`option_name_snapshot` and every price are written at the moment of adding. A
restaurant that renames a dish tomorrow must not rewrite what the customer chose
today.

The snapshot answers *"what did I choose"*, never *"what do I owe"*. This module
already refuses a stale price at the moment of adding, and Module 12 revalidates
before an order exists.

### Expiry

`last_activity_at` and `expires_at` are written; **nothing deletes on them**. A
scheduled job that silently empties carts before the screen explaining it exists
would be shipping the consequence without the explanation. Module 12 owns that.

---

## Idempotency

Module 01's `Idempotency-Key` middleware is global on unsafe requests, so
add-to-cart gets it by carrying the header.

The client mints **one key per attempt** and keeps it across retries of that
attempt. It is dropped the moment the configuration changes, because a different
configuration is a different order and must not be deduplicated against the last
one, and dropped again once an add succeeds.

The lost-response case, which is the whole reason this exists:

1. The request reaches the server; the cart line is written.
2. The response is lost on a motorway connection.
3. The client retries with the same key.
4. The middleware replays the first response. **One line, at the quantity asked
   for once.**

A rapid double-tap is handled twice over: the controller refuses to submit while
one is in flight, and the key would make a second submission a replay anyway.

---

## The screen

### Rules are stated before they can be broken

"Required · Choose 1" sits above the options, not in an error below them. A
customer should not have to be refused to learn what was being asked of them,
and a validation message is a poor place to explain a rule for the first time.

### The button stays enabled when something is missing

It says **"Choose required options"**, and the tap scrolls to the first
unanswered group and marks it. A disabled button with no explanation is a
customer wondering what they did wrong.

Nothing is marked red until the customer has *tried* — a screen that opens
covered in warnings is telling somebody off for not having started.

### The price on the button is a preview and the code says so

It moves the instant anything is tapped, because a total that lags feels broken.
It is replaced by the server's figure on every add. The two disagree only when
the menu changed underneath the customer, which is exactly what `PRICE_UPDATED`
is for — and then both figures are shown: *"This item was ₹249 and is now
₹269."* "The price changed" without saying to what is not information.

### At the ceiling, options disable rather than swapping

A customer who taps a third extra when two are allowed keeps their two and sees
*"You can choose up to 2."* Silently dropping their first choice would leave
them to work out which one went.

### Nothing is invented

No fabricated "Regular" for a dish without sizes. No preselected paid option. No
stock photograph. The note field says the kitchen *will do what they can*, and
never that they will comply — and it is never presented as a way to declare an
allergy, because a free-text field is not an allergen control.

---

## Security

| Attack | Answer |
| --- | --- |
| A price in the request body | No field reads it. Charged the real price. |
| A variant from another dish | `422 VARIANT_INVALID` |
| An option from a group this dish does not ask | `422 MODIFIER_INVALID` |
| An option paired with the wrong group in the request | The pairing is ignored; the option knows its group |
| Quantity 0, −1, 999999, "two", 2.5, `true` | `422` |
| A 5000-character note | `422 SPECIAL_INSTRUCTIONS_TOO_LONG` |
| Another customer's trip | `404 TRIP_NOT_FOUND` |
| Another customer's cart | Unreachable — the cart is found *through* the trip |
| A suspended restaurant | `404`, before the dish is even read |
| A paused kitchen | `409 RESTAURANT_NOT_ACCEPTING_ORDERS` |
| Markup or SQL in a note | Stored verbatim, rendered as text |

Notes are stored **exactly as written**. Escaping on the way in would
double-escape on the way out, and the place to make markup safe is where it is
rendered — which for a restaurant dashboard is a later module's job, recorded
here so it is not forgotten.

---

## Cost

| Measurement | Result |
| --- | --- |
| Item detail: customization queries | **3** — one for sizes, one for groups, one for all options |
| Item detail: whole request | 20, flat at 1 group or 10 |
| Add to cart: reads | flat as options grow; writes grow by one row per option |
| Routing provider calls: opening an item | **0** |
| Routing provider calls: adding to a cart | **0** |
| Routing provider calls: reading the badge | **0** |
| Menu rows changed by adding to a cart | **0** |

The mandatory one is proved twice: with a counting stub in
`CartPerformanceTest`, and against the real provider log in
`tool/cart_smoke.dart` across fifteen item and cart requests.

The N+1 assertion measures **reads**, not total queries. Writing five modifier
rows is five inserts, which is rows being written rather than a query being
repeated; conflating the two would either hide a real N+1 or fail on a
legitimate write.

---

## Test data

`MenuTestDataSeeder` gained sizes and questions, deliberately uneven:

| Fixture | Why |
| --- | --- |
| Paneer Tikka: Regular (default), Large, Family (sold out) | A default that is configured, and a size shown-but-disabled |
| Masala Chai: 150 ml, 250 ml, **no default** | The "Choose a size to continue" refusal |
| Dal Makhani: a question, no sizes | The screen must not invent a "Regular" |
| Papad: neither | The plain path |
| Spice level (1–1, on three dishes) | A group written once and attached repeatedly |
| Add extras (0–2, one option sold out) | Optional, multi-select, paid, and the ceiling |
| Pick your sides (2–4) | The "choose at least 2" message as a fixture |
| Tandoori Mushroom: sold out *with* a question | The sold-out refusal on a configurable dish |

---

## Not in this module

The cart screen, editing a line from it, removing a line, promo codes, taxes,
fees, the order total, pickup time, checkout, payment and order creation. Those
begin in Module 12.

`is_orderable` and `can_order` drive what the screen *says*. Module 11 places no
orders.
