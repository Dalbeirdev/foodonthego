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
