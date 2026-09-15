# 01 — Product overview

## What FoodOnTheGo is

A **route-based food pre-order and pickup platform**. A traveller enters an origin and a
destination; FoodOnTheGo finds restaurants on or near that route; the traveller orders before they
arrive; the kitchen starts cooking against their **expected arrival time**.

The business objective, stated precisely:

> Food should be ready when the traveller reaches the restaurant — minimising their wait without
> preparing the food so early that it is cold.

Both halves matter. "Ready on arrival" alone is satisfied by cooking immediately and letting it sit.
The product is the *timing*, and the ETA engine is therefore the thing the platform lives or dies by.

## What makes it different from food delivery

| | Delivery platform | FoodOnTheGo |
| --- | --- | --- |
| Who moves | A courier, to the customer | The customer, past the restaurant |
| Anchor time | When the order was placed | When the traveller will arrive |
| Discovery | Restaurants near an address | Restaurants near a **route** |
| Key risk | Late courier | Food cooked at the wrong moment |
| Restaurant queue | Ordered by placement time | Ordered by **expected arrival** |

This is why the restaurant dashboard's order queue is sorted by arrival rather than by order time,
and why per-item preparation time is a first-class field on the menu rather than a note.

## Actors

| Role | Surface | What they do |
| --- | --- | --- |
| `customer` | Mobile (Flutter) | Plans a journey, orders, collects |
| `restaurant_owner` | Web dashboard | Owns one or more restaurants; full control |
| `restaurant_manager` | Web dashboard | Runs a restaurant day to day |
| `restaurant_staff` | Web dashboard | Works the order queue |
| `support_agent` | Admin panel | Handles tickets; limited data access |
| `admin` | Admin panel | Platform operations |
| `super_admin` | Admin panel | Everything, including role assignment |

## Module 01 scope

Foundation only: architecture, repository structure, design system, API contract, database
conventions, security baseline, application shells, CI, and documentation.

**No business feature is implemented.** No authentication, journey planner, restaurant search,
ordering, payment or ETA engine. Every shell route that has no feature behind it renders a
placeholder that says so and names the module that will deliver it.

---

## Where Module 10 leaves the customer

A customer can now plan a journey, see what is on the road, filter it, open one
restaurant, decide whether to stop there — and read the whole menu.

What they still cannot do is order. That is deliberate and it is the boundary
Module 10 stops at: no cart, no variants, no add-ons, no payment. The menu shows
`is_orderable` and the screen says *"Ordering opens soon"* rather than showing a
button that does nothing.

The product decision underneath it is the one this whole app is built on: **a
menu that says less than it knows is a menu a customer can trust.** A dish
without a description gets none. A dish nobody photographed gets a monogram, not
somebody else's curry. A dish nobody declared vegetarian is not marked
vegetarian, however obvious the name makes it — because the one time that guess
is wrong, it is wrong on somebody's plate.

---

## Where Module 11 leaves the customer

A customer can now open a dish, choose its size, answer the questions the
kitchen asks about it, add extras, set a quantity, say what they would prefer —
and put it in a cart that lives on the server.

What they still cannot do is see that cart as a screen, change what is in it, or
pay for anything. Module 11 stops at the moment the line exists: the add returns
a small badge ("1 item · ₹778") and the cart screen, price revalidation and
order summary are Module 12's.

Three product decisions underneath it are worth stating plainly, because they
are the ones a customer would notice if we got them wrong:

**The app never decides what anything costs.** The phone shows a price so the
customer knows what they are agreeing to, but the number that reaches the cart
is computed on the server from the restaurant's own menu. If the kitchen changes
a price while the dish is open, the add stops and says *"The price changed"* with
the new figure — it never quietly charges the old one, and it never quietly
charges the new one either.

**A paid extra is never ticked for you.** A restaurant can configure a default,
and where it does — Mild, on the spice question — that default is free. Nothing
that costs money arrives pre-selected. The bill at the bottom only grows because
the customer made it grow.

**Special instructions are a request, not a promise.** The field says the
kitchen *"will do what they can"*, and it never says *guarantee*. Anything that
has to be true — what a dish contains, whether it is vegetarian — is structured
data or it is absent; it is not something a customer types into a free-text box
and hopes somebody reads.
