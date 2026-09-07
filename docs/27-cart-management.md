# 27 — Cart management, price revalidation and the order summary

Module 12. Module 11 built a cart a customer could add to and nothing else: no
screen, no way to change a line, no way to empty it, and no answer to "what do I
owe". This module supplies those, and closes the dead end Module 11's device
tests found.

Everything here obeys the rule Module 11 established and does not relax it: the
**client never sends a price**, and the server never reads one from a request.

---

## The cart lifecycle

`CartStatus` has had two cases since Module 11 and only ever wrote one. `CLOSED`
is written for the first time here.

| Event | Effect |
| --- | --- |
| First add on a journey | A cart is created `ACTIVE` |
| Every line removed | Cart `CLOSED` |
| Cart emptied explicitly | Cart `CLOSED` |
| Journey discarded | Its cart `CLOSED`, in the same transaction |
| Conflict resolved by "start a new cart" | Old cart `CLOSED`, then the add proceeds |

**A cart is never deleted.** Its rows survive for history and for the orders
Module 13 will point at. Only the status moves.

### Why an empty cart is closed rather than kept

Because an empty `ACTIVE` cart is not harmless. The one-active-cart-per-journey
index is what makes `CART_TRIP_CONFLICT` possible, and an empty cart on a
journey the customer has forgotten still occupies that slot — so removing your
last line on Monday's trip would block adding anything to Tuesday's, with a
message naming a cart that contains nothing. That is KI-014 again by a different
route.

`GET /cart` already answers `{"cart": null, "item_count": 0}` when there is no
active cart, and every client handles it, so closing an emptied cart needs no
new client state. An empty cart is the absence of a cart, and is reported as
one.

### KI-014 — discarding a journey closes its cart

Recorded in [13-known-issues.md](13-known-issues.md), found by the first
on-device run that got as far as adding to a cart, and reproduced against a real
backend in four requests:

```
POST /trips/{A}/restaurants/{R}/cart/items   200   cart created
POST /trips/{A}/discard                      200   trip CANCELLED, cart still ACTIVE
GET  /trips/{B}/cart                         200   {"cart": null}
POST /trips/{B}/restaurants/{R}/cart/items   409   CART_TRIP_CONFLICT
```

The customer could never add to a cart again, on any journey, and no screen
reached the cart that was blocking them because it sat on a cancelled trip.

`TripService::discard` now closes the trip's active cart in the same
transaction that cancels the trip. This is **not** "silently deleting a cart":
the customer explicitly cancelled that journey, the cart belonged to it, and the
rows remain. Leaving it active is what surprised them.

The refusal itself was never wrong. Moving a stop from one road to another
without asking would be worse than refusing. What was missing was the release.

---

## Editing a line

| Operation | Method | Rule |
| --- | --- | --- |
| Read the cart | `GET /trips/{trip}/cart` | Lines, options, and the order summary |
| Change quantity | `PATCH /trips/{trip}/cart/items/{item}` | `1..CART_MAX_QUANTITY_PER_LINE` |
| Remove a line | `DELETE /trips/{trip}/cart/items/{item}` | Closes the cart if it was the last |
| Empty the cart | `DELETE /trips/{trip}/cart` | Closes the cart |

None of these is nested under the restaurant, and that is not an oversight. A
cart already knows which kitchen it belongs to; a path that repeated it would
let a request name a restaurant its own cart disagrees with. The journey is the
only thing the customer has to own, and everything else is read from the cart.

All four answer in one shape — `{cart, item_count, line_count}` — so a client
renders the response of a delete exactly as it renders a read. A cart that has
just been closed reports as `"cart": null`, which is what `GET` has always
answered for a journey with nothing on it: to the customer, an emptied cart and
a journey they have not started ordering on look the same.

`GET /trips/{trip}/cart` is Module 11's badge endpoint, extended rather than
replaced. Every field that response carried — `cart.id`, `cart.restaurant_id`,
`cart.restaurant_name`, `cart.subtotal`, `item_count`, `line_count` — is still
in the same place. A tidier shape is not worth breaking a client that ships
today, and there is a test that says so by name.

The read costs the same number of queries whether the cart holds one line or
twenty. A cart screen that gets slower the more a customer puts in it is the
classic N+1, and the screen where they are about to spend money is the worst
place to meet it.

`PATCH` reads exactly one field: `quantity`. **Quantity zero is refused, not
treated as removal.** A client that means "remove" says `DELETE`. Overloading
a quantity of nought as deletion makes an off-by-one in a stepper destroy a
customer's selection, and makes the server unable to tell a mistake from an
intention.

Changing a quantity **re-prices the line from live menu data** rather than
multiplying the snapshot. The unit price stored on a line was authoritative at
the moment it was added; it is not a licence to charge that figure later. If the
dish now costs more, the response says so rather than quietly applying it — the
same `PRICE_UPDATED` policy Module 11 uses at the moment of adding, with both
figures in the error's details and the cart left exactly as it was.

A price that has gone *down* is applied without ceremony. Nobody needs a
confirmation dialogue to be charged less, and leaving the stale higher figure on
the row would charge a customer for a reduction they were given.

Re-pricing goes through the same validator and the same pricing service the
original add used: `CartLineRepricer` turns the stored line back into the
selection that produced it, and hands that to Module 11's code unchanged. A
second implementation of "what does this dish cost" would be a second thing to
keep in step with the first, and the day the two disagree the customer is
charged by whichever one happens to run.

---

## Resolving a conflict

Module 11 refuses a cross-restaurant or cross-journey add, names the other
restaurant, and mutates nothing. That refusal was always half an answer: the
other half is a screen where the customer chooses.

Two choices, both explicit:

- **Keep what I have.** Nothing happens; the add is abandoned.
- **Start a new cart.** The existing cart is `CLOSED` and the new item added.

There is no third option in which the app decides. Emptying a cart to make an
API call succeed is the customer's decision.

---

## Price revalidation

`GET /trips/{trip}/cart/revalidate`.

A read, and a `GET` deliberately: it **never mutates the cart** and never
re-prices anything on its own. A `POST` would suggest otherwise, and the one
thing this endpoint must never be understood to do is correct a cart on the
customer's behalf. Its job is to answer, for every line, whether what the
customer chose is still available and still costs what it did.

The check is Module 11's validator and Module 11's pricing service, run over the
stored line. A second set of availability rules written for this screen would
produce a cart that revalidates clean and then refuses at the counter.

Per line it reports:

| Finding | Meaning |
| --- | --- |
| `PRICE_INCREASED` / `PRICE_DECREASED` | With both figures, in minor units |
| `ITEM_UNAVAILABLE` | Sold out or withdrawn from the menu |
| `VARIANT_UNAVAILABLE` | The chosen size is gone |
| `MODIFIER_UNAVAILABLE` | A chosen option is gone, named |

And for the cart: whether the restaurant is still accepting orders.

The snapshot answers *"what did I choose"*. Revalidation answers *"what do I
owe"*. Keeping those separate is what stops a renamed dish rewriting history and
a stale price becoming a charge.

Findings come in two kinds, and the response says which: a price that moved does
not stop the customer ordering — they look at it and decide — while a missing
dish, size or option does, because there is nothing to decide about until the
line changes. `can_proceed` is the single answer a screen branches on;
`blocks_ordering` is the same question per line.

Every line is reported, including the ones with nothing wrong. A screen that
lists only problems leaves the customer wondering whether the rest was checked.
And a failing line does not stop the ones after it: a customer who has to fix
three things wants to be told about three things, not the first one three times.

`finding` is a coarse bucket, and `source_code` alongside it carries the refusal
the pricing path actually gave. That is what lets a screen say "Choose a spice
level" rather than "something about the options changed" — a restaurant can make
a modifier group required after a line was added, and the customer's fix is
specific.

`totals_if_accepted` says what the cart would cost if the customer accepted
every price change on the screen. It is **null the moment any line cannot be
priced**: a total worked out around a missing dish is a figure for a cart nobody
has, and offering one before the customer has decided what happens to that line
is a guess at what they will choose.

Nothing is auto-corrected — in either direction. A cart whose price rose is
shown with both figures and the customer decides, because a total that changes
itself between the screen and the payment is the thing customers do not forgive.
A price that *fell* is reported too rather than quietly applied: a customer
should see a reduction, and a read that rewrote a row would be doing the
forbidden thing in the direction that happens to be pleasant.

Revalidating calls no routing provider. The restaurant's ordering state comes
from Module 07's cached discovery result, exactly as adding to the cart does —
looking at your own cart must not spend a route call.

---

## The order summary

Server-calculated, integer minor units, in one place:

```
subtotal        sum of live line totals
taxes           computed on the subtotal
fees            packaging, platform
------------------------------------
total
```

### Rates are configuration, not code

**No tax rate or fee is invented in this module, and none is hard-coded.** They
are business inputs:

| Input | Where | Default |
| --- | --- | --- |
| Tax rate | `restaurants.tax_rate_bps`, falling back to `foodonthego.cart.tax_rate_bps` | **0** |
| Packaging fee | `restaurants.packaging_fee_minor` | **0** |
| Platform fee | `foodonthego.cart.platform_fee_minor` | **0** |

Defaulting to zero is deliberate. A plausible-looking 5% that nobody chose is
worse than a visible zero: it would be wrong in a way that reads as right, and
it would ship as a real charge. The mechanism is built and tested with non-zero
values in the seeded fixtures; the production defaults stay at zero until the
business sets them.

Basis points, not percentages, so a rate is an integer and no float ever touches
money.

### Rounding

Tax is computed on the **subtotal**, once, not per line, and rounded half up to
the paisa. Per-line rounding drifts: twenty lines rounded individually can miss
the correct total by several paise, and the customer's arithmetic will not match
the invoice.

---

## Not in this module

Checkout, payment, order creation, promo codes, pickup-time selection, and the
restaurant's side of an order. Module 12 ends when a customer can see, correct
and understand their cart — and knows what it will cost — not when they can buy
it.
