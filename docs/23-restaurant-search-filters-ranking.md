# 23 — Restaurant search, filters, sorting and ranking

Module 07 decides **which restaurants a customer may see** on their route.
Module 08 decides **which of those they are looking at right now**.

That sentence is the whole architecture. Module 08 never queries restaurants.
It receives a `DiscoveryResult` — a set Module 07 has already filtered by
approval, verification, discoverability, coordinates, corridor, proximity,
detour budget and route position — and narrows it. There is no code path from a
query string to the database, which is why no filter a customer can type can
reach a restaurant Module 07 removed.

```
Customer's route
      ↓
Module 07 — eligible restaurants on that route        (database, provider, cache)
      ↓
Module 08 — search · filters · sort · pagination      (in memory, no queries)
      ↓
One page of results
```

---

## The mandatory rule

> **A filter can only ever remove restaurants. It can never add one.**

`Search: "Suspended Dhaba"` returns **0 results**, even though the name matches
exactly, because the suspended restaurant was gone before the refiner ran.

This is guaranteed structurally rather than by a check. `DiscoveryRefiner`
takes a `DiscoveryResult` and a `DiscoveryQuery` and returns a
`RefinedDiscovery`. It has no repository, no query builder and no connection. A
future contributor cannot weaken the rule by forgetting a `where` clause,
because there is no `where` clause to forget.

Proven by `DiscoveryRefinerTest::test_a_search_cannot_resurrect_a_restaurant_eligibility_removed`,
by `TripRestaurantFilterApiTest::test_no_filter_combination_reaches_an_unverified_restaurant`
(which walks seven filter shapes), and live against the real Delhi → Jaipur
route in `tool/discovery_filters_smoke.dart`.

---

## Search

### What is searched

| Field | Why |
| --- | --- |
| `name` | What the customer is looking for |
| `cuisines[].cuisine` | "South Indian" is a search, not just a filter |
| `city` | Weakly — a locality match is a hint, not an answer |

Nothing else. Not the owner's name, not the phone number, not internal notes,
not the tax identifier, not the verification record. Those columns are not on
the model's discovery projection at all, so a search cannot reach them even by
accident.

### Normalisation

`SearchMatcher::normalise()` applies, in order:

1. `mb_strtolower` — case-insensitive.
2. Unicode canonical decomposition (`Normalizer::FORM_D`) and removal of
   combining marks, so `Café` matches `cafe`.
3. Apostrophes (`'`, `’`, `` ` ``) **removed**, so `rajeshs` finds
   `Rajesh's Dhaba`. An apostrophe is an elision, not a word boundary.
4. Every other non-alphanumeric run becomes a single space.
5. Runs of whitespace collapse; the result is trimmed.

`iconv('UTF-8', 'ASCII//TRANSLIT')` is deliberately **not** used: it turns
`शर्मा ढाबा` into `????? ?????`, which would make every Devanagari restaurant
name unsearchable.

### Relevance tiers

A match is scored, not just accepted, because the score feeds the recommended
ranking. Highest tier wins.

| Tier | Score |
| --- | --- |
| Exact name | 1.00 |
| Name starts with the term | 0.90 |
| Name contains every term | 0.75 |
| Name contains the term | 0.60 |
| Exact cuisine | 0.55 |
| Partial cuisine | 0.40 |
| City | 0.20 |

This is what makes `"Highway Spice"` put *Highway Spice Kitchen* first rather
than letting a city match outrank it.

### Length policy

| Length | Behaviour |
| --- | --- |
| 0 | No search. The route's own results. |
| 1 | **Treated as no search.** Not an error — a customer mid-keystroke. |
| 2 – 100 | Searched. |
| > 100 | `422 VALIDATION_FAILED`, field `search`. |

One character would match most of a corridor and cost a request per keystroke.
Rejecting it with a 422 would put an error on screen between the first letter
and the second, so it is silently treated as no search and the response's
`meta.applied.search` comes back `null` — the client can see exactly what the
server made of its request.

### Debounce and stale responses

The client waits `DiscoveryController.searchDebounce` = **350 ms** after the
last keystroke. Typing "spice" at speed is one request, not five.

Every request takes a generation number; only the newest may write to state. A
slow request for `"spi"` finishing after a fast one for `"spice"` is discarded,
so the customer never reads the results for a word they have already finished
typing. Pressing the search key skips the debounce.

---

## Filters

| Filter | Parameter | Values | Source |
| --- | --- | --- | --- |
| Cuisine | `cuisines` | slugs | `restaurant_cuisines.slug` |
| Facilities | `facilities` | slugs | `restaurant_facilities.slug` |
| Price | `price_levels` | 1–4 | `restaurants.price_level` |
| Availability | `availability` | `open_now`, `accepting_orders` | Module 07 availability |
| Maximum detour | `max_detour_seconds` | 1 … `max_detour_duration_seconds` | Module 07 detour |
| Distance ahead | `max_distance_ahead_meters` | 1 … 5 000 000 | Module 07 route position |
| Minimum rating | `min_rating` | 0.0 – 5.0 | `restaurants.rating_average` |

### Slugs, not labels

`slug` is a **stored generated column**:

```sql
LOWER(REGEXP_REPLACE(TRIM(cuisine), '[^a-zA-Z0-9]+', '_'))
```

so `North Indian` is always `north_indian`, the database maintains it, and it
cannot drift from the label. Filtering by the display label would break the day
the interface is translated or an operator renames "Restroom" to "Toilets".

### OR and AND

| Group | Within the group | Why |
| --- | --- | --- |
| Cuisines | **OR** | "North Indian or Cafe" — either will do |
| Price levels | **OR** | "₹ or ₹₹" — either will do |
| Facilities | **AND** | "parking **and** a restroom" — both, or the stop is no use |
| Availability | single choice | Two answers to one question |

**Across** groups it is always AND. `cuisines=north_indian,cafe` +
`facilities=parking,restroom` means *(North Indian OR Cafe) AND parking AND
restroom*.

The facilities rule is the one worth stating twice: a customer who filtered for
parking and a restroom and was sent somewhere with only parking has been
misled about the thing they stopped for.

### Null handling

| Situation | Behaviour |
| --- | --- |
| Restaurant has no price level | Excluded by any `price_levels` filter |
| Restaurant has no rating | Excluded by any `min_rating` filter |
| Detour unknown (no provider answer) | Excluded by any `max_detour_seconds` filter |

In each case the filter asks a question the restaurant cannot answer, and
"we don't know" is not "yes". An unrated restaurant is shown as **New**, never
as zero stars.

### Availability: two different questions

`open_now` and `accepting_orders` are not the same filter.

| State | `open_now` | `accepting_orders` |
| --- | --- | --- |
| Open | ✓ | ✓ |
| Closing soon | ✓ | ✓ |
| Not accepting orders | ✓ | ✗ |
| Opening soon | ✗ | ✗ |
| Closed | ✗ | ✗ |
| Hours unknown | ✗ | ✗ |

A restaurant with its lights on that has paused its own orders **is open** and
**cannot serve you**. Collapsing the two would send somebody to a counter that
cannot take their order.

Availability is evaluated in the restaurant's own timezone against
authoritative server time, never the device clock. That is Module 07's rule and
Module 08 does not touch it.

### Rating: deferred, honestly

There is no reviews module, and no restaurant has a rating. So:

- `rating_average` is `null` for every row.
- The facets block reports `rating_available: false`, and the client renders
  **no rating control at all** — not a greyed-out one, not one showing zero
  stars.
- `sort=highest_rated` is refused with a 422 naming the reason, rather than
  silently downgraded to recommended.
- `min_rating=4` is accepted, validated, and matches nothing. That is the
  truthful answer.

The filter, the sort and the ranking term are all implemented and tested with
controlled data. They switch themselves on the day a reviews module writes the
first rating; nothing needs to be deployed for that to happen.

**No rating is ever invented.** A hopeful 4.5 on a card is a claim a customer
would act on.

---

## Sorting

| Sort | Ascending on | Available |
| --- | --- | --- |
| `recommended` | ranking score, descending | ✓ (default) |
| `lowest_detour` | `detour_duration_seconds` | ✓ |
| `soonest_along_route` | `distance_ahead_meters` | ✓ |
| `price_low_to_high` | `price_level` | ✓ |
| `highest_rated` | `rating_average`, descending | ✗ — nothing is rated |

An unavailable sort stays in the facets with `available: false` and a reason,
so the sheet can show it and explain it. A missing row reads as a lost feature;
a greyed-out row with no explanation reads as a bug.

### Backtracking is a tie-break, not an override

Every comparator carries `requiresBacktracking` **immediately after its primary
key**, then falls through to `alongRouteMetres` and finally the uuid, so the
order is total and deterministic.

The consequence is deliberate. Under `price_low_to_high`, a cheap stop behind
the customer can rank above a pricier one ahead — they asked for cheapest
first, and its card says "Behind you". What it can never be is *first*, which
is the answer to "where should I stop?".

Under `recommended`, `lowest_detour` and `soonest_along_route` — the orders
that are about the journey rather than the menu — a backtracking stop sorts
last outright.

Without this, a price sort in which every restaurant declares the same level is
decided entirely by tie-breakers, and puts the stop behind you at the top. That
happened, and is now covered by
`test_a_stop_behind_the_customer_is_never_first_in_any_sort`.

---

## Recommended ranking

Deterministic, explainable, no machine learning. Four normalised terms, each in
`[0, 1]`, combined as a weighted mean, plus search relevance when the customer
has searched.

```
score = Σ(weightᵢ × termᵢ) / Σ(weightᵢ)
```

| Term | Weight | Config key | What it measures |
| --- | --- | --- | --- |
| Detour | 0.45 | `DISCOVERY_WEIGHT_DETOUR` | Extra travel time, against the ceiling |
| Availability | 0.30 | `DISCOVERY_WEIGHT_AVAILABILITY` | Can they serve you now |
| Proximity | 0.15 | `DISCOVERY_WEIGHT_PROXIMITY` | Distance off the road |
| Rating | 0.10 | `DISCOVERY_WEIGHT_RATING` | Only where real |
| Search relevance | 0.60 | `DISCOVERY_WEIGHT_SEARCH_RELEVANCE` | Only when searching |

All five live in `config/foodonthego.php` under `discovery.weights` and are
environment-overridable. There are no ranking constants anywhere else in the
codebase, and none of these numbers is ever shown to a customer.

### Why the weights are shaped this way

**Convenience dominates popularity.** A 5-star restaurant twenty minutes off
the road must not outrank a 4.4-star one two minutes off it. Detour and
availability together carry 0.75 of the weight; rating carries 0.10. That
ordering *is* the product: FoodOnTheGo is worth using because it saves a
traveller time, not because it knows which restaurant has the best reviews.

**A term with no data does not vote.** The denominator is the sum of the
weights actually applied, so an unrated restaurant is not punished for being
unrated — its score is the mean of the terms it does have.

> A note for whoever changes this next. The terms were once written as a map
> keyed by weight — `[0.45 => …, 0.30 => …]`. PHP casts float array keys to
> `int`, so all four collapsed into key `0`, the denominator became zero, and
> **every restaurant scored 0.0000**. It surfaced as "Behind You Diner" sorting
> first. `test_every_weight_actually_reaches_the_score` exists so it cannot
> happen again.

---

## The API

```
GET /api/v1/customer/trips/{trip}/restaurants
```

Authenticated (Sanctum), rate limited, and resolved through
`TripService::ownedByOrFail()` — a journey belonging to somebody else is *not
found* rather than found-and-refused. There is no route identifier in the
request: the route is whichever one the customer selected on their own trip, so
there is nothing for a caller to substitute.

### Query parameters

| Parameter | Type | Rules |
| --- | --- | --- |
| `search` | string | 2–100 chars after normalisation; shorter is ignored |
| `cuisines` | comma-separated slugs | `^[a-z0-9_]{1,60}$`, ≤ 25 values |
| `facilities` | comma-separated slugs | `^[a-z0-9_]{1,60}$`, ≤ 25 values |
| `price_levels` | comma-separated ints | 1–4, ≤ 25 values |
| `availability` | enum | `open_now` \| `accepting_orders` |
| `max_detour_seconds` | int | 1 … `max_detour_duration_seconds` (900) |
| `max_distance_ahead_meters` | int | 1 … 5 000 000 |
| `min_rating` | float | 0.0 – 5.0 |
| `sort` | enum | The allow-list above; unavailable sorts refused |
| `page` | int | ≥ 1 |
| `per_page` | int | 1 – 50 |

Every failure is a `422` with `error.code = VALIDATION_FAILED` and
`error.details.fields.<name>` naming the parameter. Nothing is silently ignored
or silently clamped: a client sending `max_detour_seconds=-500` has a bug, and
answering it with a full unfiltered list hides that bug from whoever has to
find it.

### Response

```jsonc
{
  "data": {
    "route": { "route_id": "…", "distance_meters": …, "provider": "…" },
    "restaurants": [ … ],
    "meta": {
      "returned": 5, "total": 5, "page": 1, "per_page": 25,
      "last_page": 1, "has_more": false,
      "eligible_total": 5,      // before the customer refined anything
      "filtered_empty": false,  // the filters emptied a non-empty route
      "from_cache": true,
      "corridor_meters": 5000,
      "applied": { …the query as the server understood it… }
    },
    "filters": {                // facets for *this* route
      "cuisines":   [{ "slug": "north_indian", "label": "North Indian", "count": 2 }],
      "facilities": [{ "slug": "parking", "label": "Parking", "count": 4 }],
      "price_levels": [{ "level": 1, "count": 1 }],
      "availability": [{ "value": "open_now", "label": "Open now", "count": 4 }],
      "rating_available": false,
      "sorts": [{ "value": "highest_rated", "available": false,
                  "unavailable_reason": "…" }],
      "max_detour_seconds": 900
    }
  }
}
```

`meta.applied` echoes the **normalised** query, which is the fastest way for a
client to notice a parameter it thought it sent and did not.

### Why facets, and why in the same response

The client renders only filters this route can satisfy. Offering "Chinese" on a
road where no partner serves it produces a control whose only outcome is an
empty screen.

They ride along with the discovery response rather than living at a second
endpoint, because they are computed from the same in-memory set and cost
nothing extra. A separate `…/restaurants/filters` call would double the request
count on the most expensive endpoint in the application to save no work at all.

Counts are taken **before** the customer's filters are applied, so selecting
"North Indian" does not collapse the list of cuisines to the one already
chosen.

### Error codes

`VALIDATION_FAILED` covers every malformed filter, with the field named in
`details.fields`. Beyond that the endpoint returns the codes Module 07 already
defines: `TRIP_NOT_FOUND`, `ROUTE_NOT_READY`, `ROUTE_STALE`, `DISCOVERY_FAILED`,
`DISCOVERY_RATE_LIMITED`, `RATE_LIMITED`, `UNAUTHENTICATED`, `SERVER_ERROR`.

A separate code per filter (`INVALID_CUISINE`, `INVALID_PRICE_LEVEL`, …) was
considered and rejected: the client's handling is identical for all of them —
show the field's message — and the field name in `details` already carries the
information a second code would.

---

## Cost control

**The central guarantee: changing a filter never calls the routing provider.**

The endpoint makes two calls, and they are separate for exactly this reason:

```php
$discovered = $this->discovery->discover($found, CarbonImmutable::now());
$refined    = $this->refiner->refine($discovered, $query);
```

`discover()` is cached per (route uuid, config hash) for 5 minutes and is the
only thing that can reach a provider. `refine()` is pure computation over what
it returns.

| Cache | Key | TTL |
| --- | --- | --- |
| Discovery selection | route uuid + config hash | 300 s |
| Detour per restaurant | route uuid + restaurant uuid | 3600 s |

The filters are **not** part of either key, and they do not need to be: the
thing being cached is the eligible set, and every filter runs over it fresh.
`facilities=parking,restroom` and `facilities=restroom,parking` normalise to
the same query object before anything is looked up, so equivalent requests are
equivalent all the way down.

Only the *selection* is cached. Eligibility and availability are re-checked on
every cache hit, which is why suspending a restaurant removes it from the very
next response even with a warm cache, and why a five-minute TTL is safe for
"Open now".

Measured, in `docs/evidence/module-08-verification-run.txt`: eleven different
filter, search, sort and page combinations, **zero database queries each**, and
`StubDetourProvider::$calls` unchanged across all of them.

---

## Pagination

`page` and `per_page` (default 25, max 50). `meta` carries `total`, `page`,
`per_page`, `last_page` and `has_more`.

**Any change other than an explicit page returns to page 1.** A customer who
adds a cuisine while on page 3 is asking a new question, and answering it with
the third page of it is how a filter comes to look as though it returned
nothing.

The client appends pages rather than replacing them, and de-duplicates by id:
pages are computed from a snapshot that can shift underneath them, and a
restaurant that appears on both page 1 and page 2 must not appear twice.

### Filtering sees the whole route, not the first page

Module 07 used to truncate to `result_limit` inside `discover()`. Module 08
moved that limit to pagination, after the filters.

The reason is a bug that would otherwise be invisible: with the limit applied
first, a "Parking" filter over the top 25 by relevance would silently hide the
26th restaurant on the route, which might be the only one with parking.
`DiscoveryRefinerTest::test_filtering_sees_the_whole_eligible_set_not_a_page_of_it`
places 29 restaurants on a route, gives only the last one a charging point, and
asserts that filtering for it finds it.

`DISCOVERY_MAX_CANDIDATES` (300) still bounds the whole set, so the cached
payload cannot grow without limit.

---

## Client state

```
searchText          what is in the field right now
query.search        what the server was last asked  (differ during the debounce)
query.<filters>     applied filters
draft (in sheet)    filters being edited, discarded on dismiss
query.sort          the chosen order
discovery           the last page received, with its facets and totals
```

Search, filters and sort are three separate dimensions. Changing the sort never
clears the filters; changing a filter never resets the sort.

### Draft versus applied

The filter sheet edits a **draft**. Nothing is applied until the customer
presses *Show results*; dismissing the sheet discards the draft entirely.
Applying each toggle as it happened would send a request per checkbox and
re-sort the list under the customer's finger while they were still choosing.

`applyQuery()` compares the incoming query with the applied one and does
nothing when they match, so *Show results* on an untouched sheet costs no
request against the rate limit.

### Clear all keeps the search

*Clear all* sits under the filter chips and removes filter selections. It
leaves the typed search term, because the chips are not an undo for text the
customer is still looking at. Clearing the search is the field's own button.

### Filter state across views and trips

| Transition | Filters |
| --- | --- |
| List ↔ Map | Kept, and no refetch — the same result set drives both |
| Selecting a marker or card | Kept |
| A new result set arriving | Selection cleared, so no card survives for a restaurant that is no longer shown |
| A different trip | Cleared — the controller is `autoDispose` and the screen is per-trip |
| Signing out | Cleared with the provider container |

Filters are never persisted to disk. A "next 25 km" filter silently applied to
a different journey would be worse than no memory at all, and there is nothing
here worth surviving an app restart.

---

## The three empty screens

They mean different things and need different words and different buttons.

| State | Words | Way out |
| --- | --- | --- |
| `eligible_total = 0` | "No stops on this route yet" | Back to journey |
| `filtered_empty`, no search | "No stops match your filters" + how many there are | Clear filters |
| `filtered_empty`, searching | "Nothing matched your search" + the term | Clear search |

Showing the first when it is the second tells a customer there is no food on a
road that has six restaurants on it.

The search field and the filter chips stay on screen through all three. A
screen that swaps its whole body for an empty state takes away the only way out
of the state it is in.

---

## Security

| Control | How |
| --- | --- |
| Authentication | Sanctum; unauthenticated is 401 with or without `Accept: application/json` |
| Trip ownership | `TripService::ownedByOrFail()`; somebody else's trip is 404 |
| Route required | 409 `ROUTE_NOT_READY` before any filter is even read |
| Eligibility | Structural — the refiner has no database access |
| SQL injection | No filter value ever becomes SQL. Slugs are shape-checked, numbers cast, sorts are enum cases with hand-written comparators. Search is matched in PHP against values already in memory |
| Search length | 100 characters |
| Filter array size | 25 values per group |
| Sort | Allow-list by construction |
| Rate limiting | `RATE_LIMIT_DISCOVERY` = 30/min, unchanged from Module 07 and applied to filtered calls too |
| Private fields | The response is built from `Restaurant::toDiscoveryArray()`, an allow-list. Asserted against the **raw body**, so a leak three levels down inside a relation would still fail the test |

`sort=commission_rate desc` cannot become a column name, because the only thing
a sort value can become is an enum case.

---

## Privacy and observability

No search term is logged. No filter selection is stored against a customer. No
cuisine profile is built. Personalised recommendation is out of scope, and
building the data for it silently would be the wrong way to start it.

The structured log records the request id, the route uuid, timings and counts —
never the search text, never coordinates, never a phone number. The Module 07
fix that reduced throwables in log context to class/file/line (M07-B08) covers
this endpoint too.

---

## Handoff to Module 09

Module 09 — restaurant details, facilities, availability and customer preview —
receives:

- `DiscoveredRestaurant`, with its route relation intact through every filter
  and sort. Search and filtering never strip `detour_duration_seconds`,
  `distance_ahead_meters`, `proximity_meters` or `availability`.
- The restaurant `uuid` as the only identifier a client ever sees. There is no
  sequential id anywhere in the response.
- `Restaurant::toDiscoveryArray()` and `privateColumns()` as the allow-list a
  details endpoint should extend rather than bypass.
- The facets vocabulary — cuisine and facility slugs — which a details screen
  can reuse for its own labels.

What Module 09 must not assume: that a restaurant on screen is still open. The
availability in a discovery response is a snapshot re-checked on each request,
and a details screen opened five minutes later has to ask again.
