# 20 — Trip planner

A journey is an origin, a destination and a departure time. That is the whole of
Module 05, and the restraint is the point: the product's centre of gravity is
the *timing* — food ready when a traveller arrives — and everything that decides
timing depends on a route, which nothing in the system can compute yet.

---

## What a journey is, and what it deliberately is not

A journey records **what the traveller said**. It does not record, imply or
compute anything about the physical world:

| Recorded | Not recorded, and why |
| --- | --- |
| Where they are setting off from | The route between the two — Module 09 owns corridors |
| Where they are going | The distance, the duration, the detour to any restaurant |
| When they are setting off | Where they are *now* — there is no GPS, and there will not be one here |
| When they expect to arrive, **if they say so** | An arrival time nobody computed |
| How many are travelling | Anything about who they are beyond the account |
| A short note, if they write one | Anything derived from that note |

The pattern repeats Module 04's, and for the same reason. A saved address stores
`latitude` and `longitude` as `NULL` until something really geocodes it; a
journey stores them the same way, at both ends. A fabricated coordinate is
indistinguishable from a real one to the module that will draw a corridor from
it, and a corridor drawn from a guess produces a restaurant list that is wrong in
a way nobody can see.

---

## Two statuses, not five

`TripStatus` has `PLANNED` and `CANCELLED`. That is all this module can honestly
observe.

"On the road", "arrived" and "completed" are claims about a traveller's physical
position. Module 05 has no way to establish any of them: no GPS, no route, no
arrival signal. It could ask the customer to tap a button — but a self-reported
travel state is a claim the platform cannot verify, and the restaurant queue is
eventually sorted by **expected arrival**. An invented travel state becomes an
invented cooking time, which is the one failure this product cannot absorb.

Module 09 adds the states it can actually establish, when there is movement to
watch.

**"Past" is not a status.** A journey is behind the traveller when
`departure_at` is behind the clock — a fact about time rather than a claim about
a person. It needs no column, and it cannot go stale.

One consequence worth stating: a cancelled journey whose departure is still
ahead is in *neither* the upcoming list nor the past list. It is not upcoming —
nobody is going — and calling it past would be a lie about a date. It lives in
its own scope and remains reachable by its id.

---

## Each end is a snapshot, not a foreign key

The single most important decision in the schema. A journey stores the place as
it was **when the journey was planned**:

```
origin_label, origin_formatted_address, origin_city, origin_country_code,
origin_latitude, origin_longitude, origin_place_id, origin_address_id
```

…and the same eight again for the destination.

Holding only `origin_address_id` would look tidier and would be wrong three ways:

1. **Editing a saved address would rewrite history.** A customer who renames
   "Home" after moving would silently change every journey they had already
   planned from the old one.
2. **Deleting one would orphan or block.** Module 04 deletes addresses for real,
   so a `RESTRICT` would stop a customer removing an address they no longer use,
   and a `CASCADE` would delete their journeys with it.
3. **A typed place has no id at all.** Half the journeys in the product would
   need a second representation, and two representations of one concept is how
   two screens come to disagree.

`origin_address_id` is kept alongside the snapshot as **provenance only**, with
`ON DELETE SET NULL`. Losing the link loses nothing.

This is asserted end to end: the integration run plans a journey from a saved
address, edits that address to a different city, re-reads the journey, and finds
it unchanged.

---

## Ownership, and the IDOR this module adds

The same structural rule as Module 04: **no route carries a customer
identifier.** The owner comes from the Sanctum token, `TripService::ownedByOrFail()`
is the only path to a journey, and "not yours" and "does not exist" give the
byte-identical 404 so the endpoint cannot be walked to discover which ids are
real.

Module 05 adds one surface Module 04 did not have. A journey can be planned
**from a saved address**, by id — so "plan a journey from somebody else's saved
address" is an ownership attack on Module 04 reached through a Module 05
endpoint.

It is closed by *reuse* rather than by a second check:

```php
if (is_string($savedAddressId) && $savedAddressId !== '') {
    return JourneyEndpoint::fromSavedAddress(
        $this->addresses->ownedByOrFail($customer, $savedAddressId),
    );
}
```

The service does not query `customer_addresses`. It asks Module 04's own
ownership-scoped lookup, which throws the same `ADDRESS_NOT_FOUND` it throws for
a direct read. So the attempt fails exactly the way reading the address directly
fails, and tells the caller nothing about whether it exists.

The form request is deliberately careless in one specific way that supports this:
`address_id` is validated as a *uuid* and never as `exists:customer_addresses,uuid`.
An existence rule would confirm that another customer's address is real before
anybody had checked who owns it.

---

## The API

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/customer/trips` | List, `?scope=upcoming\|past\|cancelled\|all` |
| POST | `/api/v1/customer/trips` | Plan a journey |
| GET | `/api/v1/customer/trips/next` | The soonest journey still ahead, or `null` |
| GET | `/api/v1/customer/trips/{uuid}` | Read one |
| PATCH | `/api/v1/customer/trips/{uuid}` | Change a planned journey |
| POST | `/api/v1/customer/trips/{uuid}/cancel` | Cancel it |

**There is no DELETE.** A journey is history: cancelling records a decision, and
a later module's orders will point at the record. The absence is asserted — a
`DELETE` returns 405.

**`/next` is declared before `/{trip}`** so it is matched as a literal. The
reverse order would send the string "next" to `ownedByOrFail()` and answer 404 to
the home screen.

**`/next` returns `data: null`** for a customer with nothing planned. That is an
ordinary state, not a 404: the home screen renders nothing for journeys when it
gets one, and a 404 would make an empty account look like a failure.

Three error codes are new:

| Code | HTTP | Meaning |
| --- | --- | --- |
| `TRIP_NOT_FOUND` | 404 | No such journey, or not this caller's |
| `TRIP_LIMIT_REACHED` | 422 | Too many journeys still ahead |
| `TRIP_NOT_EDITABLE` | 422 | Departed or cancelled — nothing left to change |

`is_editable` and `has_departed` are **sent by the server** rather than derived
by the client. A handset with a slow clock would otherwise offer an edit the
server then refuses.

---

## Cancelling refuses to be idempotent

Cancelling an already-cancelled journey returns `TRIP_NOT_EDITABLE`, not a
cheerful 200.

The usual argument for idempotence is retry safety, and it does not apply: the
customer is looking at a screen that is out of date, and answering "done" would
hide that from them. The same holds for a departed journey — there is nothing
left to call off.

---

## Validation, and where it lives

| Rule | Enforced by |
| --- | --- |
| Departure is in the future | Form request **and** service, with the same configured grace |
| Departure is within the planning horizon | Form request (`before_or_equal`) |
| Arrival, if given, is after departure | Service — it knows both values even when a PATCH sends one |
| Origin and destination are different places | Service, compared against what the journey *will be* |
| A coordinate is a complete pair | Form request |
| A typed place has a city and a country | Form request, only for an endpoint the request carries |
| At most N journeys still ahead | Service, under a row lock |

Two of these are worth their explanation.

**The grace on departure is applied in both places, with the same number.** If
the layers disagreed, a request the validator accepted would be refused by the
service, and the customer would see a failure with no field to correct. It exists
so that "leaving now" works: a handset's clock runs a little behind the server's,
and a departure two seconds past is not a mistake anybody can fix.

**Origin-versus-destination is compared after the change is applied**, not
against what was sent. Moving only the origin onto the existing destination is
the same mistake as sending both the same, and a check on the request body would
miss it.

**Endpoint sub-fields are only declared for an endpoint the request carries.**
Declaring them unconditionally made `required_without:origin.address_id` fire on
a PATCH that never mentioned the origin — asking for a city for a place the
customer was not changing.

---

## In the app

The Trips tab is the module's home: three scopes over one list, with the four
states every list in this app has — loading skeleton, empty, error with retry,
data. The scope lives in a provider rather than in the widget, because the list
provider watches it; a `setState` would leave the segment and the data one
rebuild out of step.

**Nothing is optimistic.** A journey is not shown as saved until the server has
saved it, not shown as cancelled until the server has cancelled it, and never
removed from a list on the strength of a request that failed. Every write
re-reads.

**Cache isolation is structural.** `TripsController.build()` *watches* the auth
session, so signing out disposes the state. One customer's journeys cannot
survive into another's session, because there is no state that outlives a
session to forget to clear. Where somebody is going is at least as sensitive as
where they live.

### The planner

One screen for planning and editing, because they are the same fields.

A place is **chosen, not typed into the form**: a sheet offers the customer's
saved addresses first — this is what Module 04 was for — and a short form for
anywhere else. There is no map and no autocomplete, and the typed branch produces
no coordinates. A "suggestion" here would be a guess presented as a fact.

Two layout rules, both learned in Module 04 and both pinned by tests here:

- The form scrolls in a **non-lazy `Column`**, never a `ListView`. A `ListView`
  builds lazily, so a field scrolled out of view is never registered with its
  `Form` and `validate()` skips it in silence.
- The primary action is **pinned above the keyboard**, not placed after the last
  field where a small screen puts it under the bottom navigation bar.

The picker sheet repeats both, because it has a validated form of its own.

### On the home screen

The home screen shows the customer's real next journey, from `/trips/next`.

It uses a new card rather than Module 02's `RouteSummaryCard`. That card drew
progress, remaining time and a next pickup — none of which exists — and a
progress bar at zero would imply the app is tracking a journey it cannot see.
The new card shows where, when and how many, and nothing else.

Module 02's `ActiveTripSummary`, `RouteSummaryCard` and `HomeDashboard.activeTrip`
were removed with it. They were scaffolding for exactly this moment, and keeping
a second fixture-shaped journey alongside the real one is how two halves of one
screen come to disagree about whether somebody is travelling. The greeting's
`isTravelling` branch went too: nothing observes travel yet, and greeting a
traveller with "here is how your journey is going" three days before they leave
is worse than saying nothing.

---

## What this module deliberately did not build

- **Routing, corridors, distance and duration** — Module 09.
- **Google Maps rendering and Places autocomplete** — the schema carries
  `place_id` at both ends and nothing fills it.
- **Geocoding** — coordinates stay `NULL`.
- **GPS and live tracking** — and the status enum reflects the absence rather
  than papering over it.
- **Restaurant discovery along the route** — Module 09.
- **The ETA engine** — the thing the product lives by, scheduled with Modules
  08 and 09.
- **Orders against a journey** — Module 08.

Each of these is a reason a field in this schema is nullable rather than absent.
The shape is ready; the data is honest about not being there yet.
