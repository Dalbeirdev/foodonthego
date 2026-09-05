# 25 — Menu, categories and item browsing

Module 09 answers "is this the right place for me to stop?". Module 10 answers
the question a customer asks the moment they decide it might be:

> **What can I actually eat here, and what does it cost?**

Everything on the screen serves that question. There is no cart, no quantity
stepper, no variant list and no add-on picker, because none of them answers it —
they are Modules 11 and 12, and a disabled version of them here would promise a
cart that does not exist.

---

## Two decisions that shape everything else

### 1. Money is an integer count of paise, and the server never formats it

```json
"price": { "amount_minor": 24900, "currency": "INR" }
```

₹249.90 stored as a binary float is `249.90000000000001`. Ten of those summed at
checkout is off by a rupee, and the customer is right and the platform is wrong.
So the column is `unsignedInteger base_price_minor`, the PHP side is a readonly
`Money` value object, the Dart side is a `Money` class, and neither of them has
a `toDouble()`.

The currency travels with the amount, because `24900` alone is ₹249 or $249
depending on something a widget three files away cannot see.

And the server sends the number, not a rendered string. What a price *looks*
like — the symbol, the grouping, the decimals — is a locale decision, and the
server does not know the customer's locale. `Money.format()` in the Flutter app
is the only place in the product that turns an amount into something a person
reads, and it asks `intl` rather than concatenating a rupee sign.

One rule inside it earns its keep: a whole amount drops its decimals (`₹249`,
not `₹249.00`, because a menu of trailing zeroes reads like a spreadsheet) and a
part amount keeps them (`₹349.50`, because `₹349` would be a lie about the
price).

### 2. A cross-restaurant item is refused by the database, not by a service

```php
$table->foreign(['menu_category_id', 'restaurant_id'], 'menu_items_category_same_restaurant')
    ->references(['id', 'restaurant_id'])->on('menu_categories');
```

`menu_categories` carries a redundant-looking `UNIQUE(id, restaurant_id)` so
that this composite foreign key can exist. With it, an item belonging to
restaurant A cannot be filed under restaurant B's category — not by a bug, not
by a bad migration, not by a direct `INSERT`. A test attempts exactly that and
asserts MySQL's `SQLSTATE[23000] … 1452`.

This is the difference between a rule a reviewer has to remember and a rule the
storage engine enforces.

---

## The API

```
GET /api/v1/customer/trips/{trip}/restaurants/{restaurant}/menu
GET /api/v1/customer/trips/{trip}/restaurants/{restaurant}/menu/items/{item}
```

Nested under the restaurant, which is nested under the trip. Every segment earns
its place: the trip proves the journey is the customer's, and the restaurant is
validated through the same `RestaurantDetailService` Module 09 uses — so **a
menu cannot be opened for a restaurant whose page could not be opened**. There
is no second set of `where` clauses here to get wrong.

That service now has two entry points. `detail()` is Module 09's, and loads the
photographs, cuisines, facilities and a fortnight of opening hours. The menu
screen calls the lighter `orderingContext()`, because it renders a name and an
ordering state and nothing else — which took a menu open from twenty queries to
seventeen. Both go through the same `onRoute()`, so a customer's entitlement to
see a restaurant is decided in one place and cannot drift between the screens.

### Query parameters

| Parameter | Rules |
| --- | --- |
| `search` | 2–100 characters. Whitespace collapsed. Shorter than 2 is treated as no search (a customer mid-keystroke, not an error). Longer than 100 is `VALIDATION_FAILED`. A term that is punctuation only is treated as no search — see below. |

### Response shape

```json
{
  "restaurant": { "id": "…", "name": "…", "ordering": { "state": "OPEN_ACCEPTING", "can_order": true, "can_browse_menu": true } },
  "categories": [ { "id": "…", "name": "Starters", "description": null, "items": [ … ] } ],
  "meta": {
    "category_count": 4,
    "item_count": 13,
    "visible_item_count": 13,
    "search_empty": false,
    "menu_empty": false,
    "applied": { "search": null },
    "generated_at": "…"
  }
}
```

`item_count` is after the search; `visible_item_count` is before it. **The pair
is what tells the two empty states apart**, and they need different words: "this
restaurant has not published a menu" sends the customer back to the list, while
"nothing matched 'pizza'" asks them to clear the box. Module 08 needed the same
distinction for the same reason.

---

## What is on the menu, and what is not

Everything below is enforced **in the query**, not filtered afterwards — an
inactive category never reaches PHP, so its items cannot leak through a search
or a direct lookup that forgot a check. The relations are scope-guarded at the
model as well, which is belt and braces on the one rule that would be
embarrassing to get wrong.

| Situation | What the customer sees |
| --- | --- |
| Category `is_active = false` | Absent, and so is every item in it — including live ones. |
| Item `is_active = false` | Absent, from the list *and* from the item endpoint. |
| Category outside `available_from`–`available_until` | Absent. Breakfast at four in the afternoon is withheld rather than greyed out: they cannot order it either way, and a menu full of things they cannot have is harder to read than a shorter one. |
| Category with no visible items | Absent. "Desserts — no items" answers a question nobody asked. |
| Item `stock_status = SOLD_OUT` | **Present**, dimmed and labelled. A customer who came for one thing deserves to learn the kitchen has run out, rather than to conclude they misremembered the menu. |
| Restaurant closed or kitchen paused | The whole menu, with a banner. A customer planning tomorrow's drive has a good reason to read tonight's menu. |
| Restaurant suspended, unverified or permanently closed | 404, because `orderingContext()` refuses first. |

### Nothing is invented

The prohibition list is the module's, and each entry is a field that is simply
absent when the restaurant did not publish it:

- **Description** — the operator's own words or nothing. Never generated.
- **Photograph** — the dish's own, or a monogram. There is no stock-image
  fallback anywhere in this app: a generic curry standing in for an
  unphotographed dish is a claim about what arrives in the box, and one the
  restaurant never made.
- **Dietary type** — read from a structured column and never inferred from a
  name. "Paneer Tikka" is vegetarian to a reader and unknown to this app,
  because the one time the guess is wrong it is served to somebody whose
  religion or health depended on it. A value this build has not heard of renders
  as nothing rather than as the nearest of the four it knows.
- **Spice level** — 0–3 as the operator set it, or nothing. A dish called "Fiery
  Chicken" may be mild.
- **Allergens** — there is no allergen field, no allergen UI and no allergen
  string on the wire. When one exists it will be operator-declared.
- **Preparation time** — item metadata, worded as *"15 min to cook"* and
  announced to a screen reader as *"Takes about 15 minutes to cook. This is not
  a pickup time."* It says nothing about the queue ahead of the customer, the
  drive to the restaurant, or when an order placed now would be ready.

An item whose price cannot be parsed is **dropped**, not rendered at zero: a row
reading "— · ₹0" invites a customer to order something nobody can price.

---

## Searching

In memory, over items already fetched. The menu was loaded to be shown;
searching it is a filter over what is in hand, not a second trip to the
database. Two consequences worth stating:

- A search **cannot reach** an item the visibility rules already excluded,
  because those items were never loaded.
- A search term **never becomes SQL**, because there is no query for it to
  become part of.

Matching folds case, accents and punctuation (`Normalizer::FORM_D` plus
stripping combining marks, so `Café` matches `cafe` — deliberately *not*
`iconv('ASCII//TRANSLIT')`, which turns `पनीर टिक्का` into question marks). Name
first, then the category's own name — a customer searching "Breads" means the
section, and being shown three of eight breads because five lack the word in
their name is worse than useless — then the description, as a weak last resort.

**A punctuation-only term is not a search.** `%%`, `--`, `...` normalise to
nothing and would therefore match every item; returning the whole menu is right,
but reporting it as *the result for `%%`* is a claim the customer reads as
"these all match". So the term is discarded, `applied.search` is `null`, and the
menu comes back honestly unfiltered. (Found by the integration run — see
M10-B02.)

That in-memory decision is right at pilot scale and is measured rather than
assumed. A menu large enough to change the answer would move this to an indexed
query, and the *shape* would not change: the same visibility scopes, applied
first.

---

## Cost

| Menu size | Queries for the menu | Queries for the whole request |
| --- | --- | --- |
| 6 items, 3 categories | 2 | 17 |
| 500 items, 20 categories | 2 | 17 |

Two queries whatever the size: one for the categories, one for all of their
items. Not one per category, and certainly not one per item.

`MenuItem::toCustomerArray()` takes its category as an **argument** rather than
reading the inverse relation. Items arrive through `$category->items`, so that
relation is not loaded, and reading it would be one query per item. Requiring
the argument makes the mistake impossible rather than merely unlikely — and the
mistake was real: it was written the other way first and caught by
`LazyLoadingViolationException`.

The remaining fifteen are the token, the trip, its selected route and the cached
corridor read the eligibility check goes through. `MenuPerformanceTest` asserts
the count does not grow with the number of items or of categories, and holds a
ceiling that a per-category regression (twenty more) or a per-item one (five
hundred more) would break.

### The mandatory one: opening a menu calls no routing provider

`orderingContext()` reaches Module 07's cached discovery result, which is the
only thing in the application that can reach a provider, and it is already warm
from the list the customer came through. A menu is opened, searched and backed
out of dozens of times in a single journey; a billed call on any of those would
make the screen cost more than the order.

Asserted twice — with a counting stub in `MenuPerformanceTest`, and against the
real provider log in `tool/menu_smoke.dart`.

A 500-item menu is ~130 KB of JSON and is not paginated: a customer scrolling a
long menu should not discover that the second half needs a second request they
have no signal to make.

---

## The screen

One scroll view with a pinned section selector. The selector **leads and
follows** — tapping a chip scrolls to that section, and scrolling the list moves
the highlight. The second half is the one that matters: a selector that only
leads is a set of shortcuts, while one that follows tells a customer halfway
down a long menu where they are.

The list is a `ListView.builder`, so a heading fourteen sections down has never
been built and has no `BuildContext` to scroll to. `_jumpTo` steps towards the
target a screen at a time until the builder has made the heading, then lands on
it exactly. Without that, the selector would work only for the sections already
on screen — which are the ones nobody needs it for.

### State

`MenuScreenController` enforces two rules, both because a customer types faster
than a network answers:

1. **The newest request wins.** Three keystrokes produce three requests that can
   return in any order; without the generation check the slowest lands last and
   the screen shows results for "pan" under the word "paneer".
2. **A search does not blank the menu.** Previous results stay on screen under a
   thin progress bar, because a list that empties and refills on every letter is
   unreadable.

Search is debounced 350 ms. Below two characters nothing is sent, because the
server would return the whole menu and the screen would present it as a result
for "p".

### The item preview

Read-only, and fetched fresh rather than echoed from the list — a customer may
have had the menu open for ten minutes, and a preview built from the payload it
was opened from would quote a price the kitchen has left behind. The card's copy
is drawn immediately under a progress bar so the sheet is never blank, and is
replaced the moment the server answers.

An item withdrawn since the list was drawn loses the card's copy too: leaving it
up would present a dish the kitchen has taken off as though it were still
available.

Where Module 10 stops is visible here — a sentence, *"Ordering opens soon"*, and
no button at all.

---

## Security

| Attack | Answer |
| --- | --- |
| Menu of a suspended restaurant, by uuid | 404 — `orderingContext()` refuses before the menu service is reached. |
| Restaurant A's context, restaurant B's item id | `ITEM_NOT_FOUND`. The query is scoped by `restaurant_id`; there is nothing to return. |
| Item id of a withdrawn item | `ITEM_NOT_FOUND` — the same answer as a nonexistent one, on purpose. Telling them apart lets anybody with a list of ids map a competitor's menu. |
| Item id inside a withdrawn category | Same. |
| Another customer's trip | `TRIP_NOT_FOUND`, via `TripService::ownedByOrFail()`. |
| SQL injection in `search` | Matched in memory against dish names; there is no query for it to join. |
| `POST`/`PATCH`/`PUT`/`DELETE` on the menu | 404/405. There is no write endpoint, and `MenuRepository` in the app has no write method to leave out later. |
| Sequential id enumeration | Only uuids on the wire; `menu_items.id` and `menu_categories.id` never leave the server. |

The customer payload is an **allow-list**, named field by field in
`toCustomerArray()`. Cost price, margin, vendor, supplier, recipe, internal
notes, staff notes, stock quantity and commission are not omitted by oversight —
there is no line that could emit them, and a test asserts each string is absent
from the response body.

### One residual disclosure, inherited and accepted

A restaurant that exists but is no longer eligible answers `404
RESTAURANT_UNAVAILABLE`; one that never existed answers `404
RESTAURANT_NOT_FOUND`. The **status** is identical — which is what a prober with
a list of uuids mostly sees — but the code differs, and someone reading codes
can tell a suspended business from a nonexistent one.

That is Module 09's deliberate, documented choice: the customer's next move
genuinely differs ("go back to the list" versus "this closed since you looked"),
and the wording on screen differs accordingly. Module 10 inherits it rather than
diverging. It is recorded here as a known trade-off, not as an oversight; if it
is ever judged the wrong side of the line, the fix belongs in
`RestaurantDetailService::absent()` and affects both modules at once.

---

## Test data

`MenuTestDataSeeder` refuses to run in production, marks everything it creates
with `[TEST]`, and clears its own rows before re-seeding (items before
categories, because of the composite foreign key). It is never in
`DatabaseSeeder`.

The fixtures exist to make edge cases real rather than only unit-tested:

| Fixture | Why |
| --- | --- |
| Papad | Nothing optional: no description, image, prep time or diet. |
| Tandoori Mushroom | Sold out, and still on the menu. |
| Discontinued Kebab | `is_active = false`. Must never appear, by list or by id. |
| Desserts → Gulab Jamun | A live item inside a withdrawn category. |
| Breakfast (06:00–11:00) | A time-limited section, present or absent by the clock. |
| Table Water (₹0) | A free item. A formatter that assumed a non-zero price would print nothing. |
| Celebration Hamper (₹12,999) | Five figures — the grouping separator has to be right somewhere. |
| A 60-character dish name | Wraps on a 320 dp screen. |
| `[TEST] Bare Bones Stop` | No menu at all, so the empty state is a fixture rather than a branch nobody exercises. |
| `[TEST] Rajasthan Highway Bites` | A second restaurant, for the cross-restaurant refusal. |

The 500-item performance fixture is **generated in the test**. Production data
is never used for a load measurement.

---

## Not in this module

Variants, add-ons, customisation, the cart, checkout, payment and order
creation. `is_orderable` is on the wire and drives what the screen *says*, not
what it lets a customer do — Module 10 places no orders.
