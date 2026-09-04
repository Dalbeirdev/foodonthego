# 22 — Restaurant discovery along the route

Module 07 answers one question:

> Which FoodOnTheGo restaurants can I conveniently stop at while travelling on
> **this** route?

Not "what is near me". The difference is the whole product. A restaurant a
kilometre away but behind the driver is a worse stop than one forty kilometres
ahead beside the road, and no amount of proximity sorting discovers that.

---

## The number that decides everything

**Proximity is not detour**, and confusing the two is the single mistake this
module exists to avoid.

| | Restaurant A | Restaurant B |
| --- | --- | --- |
| Distance from the road | 300 m | 1.2 km |
| Driving detour | 18 min | 4 min |

A is nearer and worse. It is on the far side of a central reservation with no
junction for twenty kilometres; B is beside an interchange. Ranking by proximity
recommends A, and a traveller who takes that advice loses half an hour.

So the two figures are calculated separately, stored separately, named
separately, and shown separately:

- `proximity_meters` — straight-line distance to the route geometry. A **filter**,
  and a secondary signal shown as "1.8 km off your route".
- `detour_duration_seconds` — what stopping actually costs, from a routing
  provider. The **primary** signal, shown as "4 min detour", and the heaviest
  term in the ranking.

---

## The pipeline

```
selected route (Module 06)
        │
        ▼
  decode + simplify geometry          ── in memory, once per request
        │
        ▼
  bounding box + eligibility          ── one indexed query
        │  (hundreds of rows → tens)
        ▼
  exact point-to-polyline distance    ── PHP, no I/O
        │  (tens → the ones on the road)
        ▼
  detour, for the closest N only      ── billed provider calls, capped
        │
        ▼
  availability, ranking, limit
        │
        ▼
  journey order
```

Each stage is cheaper per row than the one after it, and each one exists to keep
the next one small. Collapsing them would mean either scanning the restaurant
table for every trip, or asking a routing provider about restaurants three states
away.

---

## Stage one — the candidate query

One `SELECT`, answered from an index:

```sql
WHERE status = 'APPROVED'
  AND verification_status = 'VERIFIED'
  AND is_discoverable = 1
  AND latitude  BETWEEN ? AND ?
  AND longitude BETWEEN ? AND ?
LIMIT 300
```

The box is the route's own bounding box grown by the corridor width. It
**over-selects** — a box has corners a corridor does not — and that is
deliberate: its job is to turn "every restaurant in the country" into "a few
hundred that could plausibly be on this road", cheaply. The exact geometry then
rejects what it let through.

### Why a bounding box and not MySQL spatial types

MySQL 8 supports `POINT` columns with SRID 4326 and `SPATIAL INDEX`, and a
spatial index would be the better tool — **once coordinates are mandatory**. It
cannot be used yet, because a spatial index requires a `NOT NULL` column and
this schema deliberately permits a restaurant with no coordinates. A restaurant
whose position has never been established is not route-discoverable, and the
alternative to a nullable column is a fabricated point.

So `latitude`/`longitude` (`DECIMAL(10,7)`) are the single source of truth, with
a B-tree index on the pair. There is **no parallel `POINT` column** to drift out
of step with them.

Latitude leads the index because it is the selective half: the Delhi–Jaipur
corridor spans about three degrees of latitude out of the thirty India covers.

**The upgrade path**, for whoever needs it: when a restaurant onboarding module
makes geocoding a precondition of approval, add a stored generated
`location POINT SRID 4326 NOT NULL` derived from the two decimals, put a
`SPATIAL INDEX` on it, and replace the `BETWEEN` clauses with
`ST_Within(location, ST_GeomFromText(?, 4326))`. Coordinate order inside a
4326 `POINT` is **latitude, longitude** — the opposite of most GeoJSON — which is
the detail that silently puts every restaurant in the wrong hemisphere if it is
got wrong.

---

## Stage two — the geometry

`App\Support\Geo\RouteGeometry` is built once per request from the selected
route's polyline and reused for every candidate.

### Simplification

Ramer–Douglas–Peucker with a **150 m** tolerance
(`DISCOVERY_SIMPLIFY_TOLERANCE_METRES`). On a motorway this removes most points;
on a hairpin it removes none.

The tolerance is an order of magnitude below the 5 km corridor, and that ratio is
the safety argument: simplification can never move a restaurant across the
threshold that decides whether it is a candidate. Measured on a 501-point curved
route, simplification to 22 points changed a probe's proximity by **8.5 m**.

### Projection

For each candidate, every segment is tested for its closest approach. One pass
yields both figures, because they are the same question asked twice and
computing them separately is how they come to disagree:

- `proximityMetres` — distance from the restaurant to that closest point.
- `alongRouteMetres` — cumulative distance from the origin to that point.

The inner loop uses an equirectangular (flat-Earth) metric, whose error over a
few kilometres is under a tenth of a percent and which costs one trigonometric
call instead of seven. The **reported** figure is always recomputed with the
exact haversine distance: the cheap metric chooses the segment, it does not get
to be the answer.

### The self-crossing case

A route that passes near itself — a ring road, a return leg, a cloverleaf —
offers two segments at almost the same distance from a restaurant beside it.
Picking the numerically smallest is a coin flip that decides whether the
restaurant is reported as 20 km ahead or 200 km ahead.

So ties are broken deliberately: among segments within **10 m** of the best, the
**earliest along the route wins**. A traveller setting off wants the first chance
to stop, and being early is the error that costs them nothing.

Verified: on a route that runs 100 km east and returns 100 km west slightly to
the north, a point between the two legs projects to 49 km along — the outbound
leg — not 149 km.

---

## Distance ahead

`distance_ahead_meters` is the cumulative distance from the route origin to the
restaurant's projection. `time_ahead_seconds` scales the route's own duration by
`alongRouteMetres / totalMetres`.

That is an **interpolation of a real figure**, not a speed model, which is why it
is presented as "About 1 hr ahead" rather than as a time of arrival. The
traffic-aware duration is preferred where the provider gave one, so this figure
and the route screen's travel time come from the same source.

### Behind the origin

A restaurant behind the start of the route has nowhere earlier to project to, so
it lands on the first point and reports zero metres along. That signature —
`alongRouteMetres ≈ 0` **and** proximity well above 500 m — is how backtracking is
detected without a live position to compare against.

Such a restaurant is:

- **halved** in the relevance score, so it rarely survives the result limit;
- **sorted last** in the list, whatever its distance-ahead says;
- **labelled** "Behind you" on its card rather than "0 m ahead".

It is not hidden. The customer may be standing next to it.

### Ready for live position

`RestaurantDiscoveryService` measures from the route origin because that is the
only reference point that exists today. When a live-GPS module arrives, the
reference becomes the customer's current projection and everything downstream —
distance ahead, time ahead, backtracking, ranking — follows from the same
arithmetic. Nothing about the design assumes the origin specifically.

---

## The detour

Measured as the same journey with the restaurant inserted as an intermediate
point:

```
detour = cost(origin → restaurant → destination) − cost(selected route)
```

Both halves come from the same provider on the same request, so
provider-to-provider differences in distance or speed model cancel rather than
accumulate. Both figures are clamped at zero: a provider can return a route
through a waypoint marginally *shorter* than the one it recommended, and
"stopping here saves you two minutes" is not a claim this module will make.

### When it cannot be measured

The answer is **null**. Not an estimate, not the straight-line distance doubled,
not zero. A null detour reaches the client as "Detour unknown"; the restaurant
keeps its exact geometric figures, which were never in doubt.

A null detour scores 0.35 in the ranking — below a measured short one, above a
measured long one. A deliberate statement of ignorance: we will show you this, we
cannot tell you what it costs, and we will not put it first.

### Cost control

Every detour is a billed provider call, so almost all of this is about not making
them:

| Control | Effect |
| --- | --- |
| Corridor filter first | A restaurant 40 km off the road never costs a call |
| `max_detour_evaluations` (12) | The hard ceiling per request |
| Closest-first ordering | The budget is spent where it is most likely to buy a result |
| Per-route, per-restaurant cache (1 h) | A second customer on the same road pays nothing |
| Failure short-circuit | The first provider failure stops the remaining calls |
| Failure cached (60 s) | One outage does not become a bill |
| Result cache (5 min) | A reopened screen costs nothing |

The detour cache is keyed by **route uuid**, so a recalculated or different route
never inherits an answer.

---

## Ranking

Deterministic and explainable by rule: same inputs, same order; every term is a
number somebody can point at; no model.

| Term | Weight | Rewards |
| --- | --: | --- |
| Detour | 0.45 | Costing little to stop at |
| Availability | 0.30 | Being open, and taking orders |
| Proximity | 0.15 | Sitting close to the road |
| Quality | 0.10 | Being well rated, where a rating exists |

Backtracking halves the total.

**Detour dominates on purpose** — it is the reason this is a route product.
**Quality is last and lightest**: sorting by rating is what a generic listings app
does, and it would put a five-star restaurant forty minutes off the route above a
good one on it. Today it is inert in any case, because there is no reviews module
and every real row's rating is null (scoring 0.5, which affects everything
equally and therefore nothing).

**Distance ahead is deliberately not in the score.** A restaurant 20 km along is
not better or worse than one 120 km along — it is a different meal. The score
decides *which* restaurants make the list; **journey order** decides how they
read, because a traveller scans the list as a sequence of chances to stop.

---

## Eligibility

One service, `RestaurantDiscoveryEligibilityService`, called from one place. A
restaurant is discoverable only if **all** of:

| Rule | Why |
| --- | --- |
| `status = APPROVED` | Not draft, suspended, disabled or permanently closed |
| `verification_status = VERIFIED` | Onboarding actually finished |
| `is_discoverable = true` | The operator has switched it on |
| Not soft-deleted | |
| Has both coordinates | It cannot be placed on a route without them |

The same rule exists as `Restaurant::scopeDiscoverable()` so it can be pushed
into the index rather than applied to rows already read. Two expressions of one
rule is a duplication with a cost, and it is paid by a test that builds all **72
combinations** of the inputs and asserts the two never disagree.

**Coordinates are a hard requirement.** Deriving a point from an address string
would put a marker on a map and a customer in a field. A restaurant without
coordinates is not route-discoverable until somebody establishes where it is.

### Availability is not eligibility

Being closed or paused does **not** hide a restaurant. A traveller two hours away
cares about one that opens at six, and "there is somewhere and it is shut" is a
different, more useful answer than "there is nothing on this road".

---

## Availability

Two independent facts, resolved in one order that never varies:

1. Do the opening hours cover this moment, in the **restaurant's own timezone**?
2. Is the restaurant accepting orders?

| State | Meaning |
| --- | --- |
| `OPEN` | Both |
| `CLOSING_SOON` | Open, and shutting within 30 minutes |
| `OPENING_SOON` | Shut, and opening within 30 minutes |
| `NOT_ACCEPTING_ORDERS` | Open by the clock, kitchen paused |
| `CLOSED` | Shut |
| `UNKNOWN` | No opening hours on file — an absence, not a claim |

**A paused restaurant is never reported as open.** Sending somebody forty
kilometres for food nobody will cook is the worst thing this module could do.

**Time comes from the server and the zone from the restaurant.** Never the
device's clock, which a customer can set to anything, and never the server's
zone, which would open a Goa restaurant on Delhi's schedule the day this product
leaves one time zone. A restaurant whose timezone is unusable falls back to the
configured default **and says so in the log** — a silent assumption about where a
restaurant is would be a wrong answer that looks exactly like a right one.

Overnight windows (18:00–02:00) belong to the day they **open**, so at 01:00 on
Tuesday the covering window is Monday's. Reading only today's rows reports a
roadside dhaba shut at exactly the hour a night driver needs it.

---

## The data model

`restaurants` carries what discovery needs and no more. Menus, staff,
settlements and the operator dashboard belong to the modules that own them.

| Group | Columns |
| --- | --- |
| Identity | `uuid`, `name`, `display_name` |
| Position | `latitude`, `longitude` (nullable), `formatted_address`, `city`, `region`, `country_code`, `postal_code`, `timezone` |
| Visibility | `status`, `verification_status`, `is_discoverable`, `is_accepting_orders` |
| Preview | `price_level`, `rating_average`, `rating_count`, `logo_url`, `cover_image_url`, `default_preparation_minutes` |
| **Never customer-facing** | `owner_name`, `owner_phone`, `owner_email`, `tax_identifier`, `bank_account_reference`, `commission_rate`, `internal_notes` |

Plus `restaurant_cuisines`, `restaurant_facilities` and
`restaurant_opening_hours` — tables rather than JSON columns, because Module 08
filters on all three and a JSON column that has to be filtered is a table that
has not been written yet. All three are eager-loaded in one query each.

`$fillable` is **empty**. Nothing here comes from a customer request.

### The private columns are there on purpose

A privacy test that asserts a response contains no owner phone number proves
nothing if no owner phone number exists to leak. They are populated by the
factory and asserted absent from the raw response body.

### Rating

Null on every real row, because there is no reviews module. The card renders
nothing where a rating would go — not a zero, and not a hopeful 4.5.

`default_preparation_minutes` exists but is **not** combined with travel time.
"Ready when you arrive" is the ETA engine's claim to make, and inventing it here
would be a promise nobody checked.

---

## The API

```
GET /api/v1/customer/trips/{tripId}/restaurants
```

Authenticated, `role:customer`, `abilities:customer`, `throttle:discovery`.

No route id in the path: the route searched is whichever one the customer
selected on their **own** trip, so there is nothing to substitute for somebody
else's. No filters and no sort order: those are Module 08's, and fixing their
shape now would fix it before that module has been designed.

`GET` rather than `POST` even though it can reach a billed provider. Discovery is
a read — it writes nothing, and a customer reopening it expects what they saw
before. The spending is controlled by a cache and a hard evaluation budget rather
than by making the verb inconvenient.

### Preconditions

Discovery runs only if the trip exists, belongs to the caller, and has a selected
route that is `READY` **and** current for the trip's endpoints. That last check is
Module 06's `selectedRouteFor()`, which Module 07 depends on rather than
re-implementing: a route whose endpoints have moved is refused with
`ROUTE_NOT_READY`, and the app sends the customer back to the route screen.

### Response

```json
{
  "data": {
    "route": { "route_id": "…", "distance_meters": 236786, "duration_seconds": 14179, "provider": "google" },
    "restaurants": [
      {
        "id": "…", "name": "Highway Spice Kitchen", "short_name": "…",
        "location": { "latitude": "28.0685728", "longitude": "76.8239377" },
        "city": "Behror", "formatted_address": "…",
        "cuisines": ["North Indian", "Vegetarian"],
        "facilities": ["Parking", "Restroom"],
        "price_level": 2, "rating": null, "review_count": null,
        "availability": "OPEN", "is_accepting_orders": true,
        "route": {
          "proximity_meters": 900,
          "detour_distance_meters": 1700, "detour_duration_seconds": 240,
          "detour_provider": "google",
          "distance_ahead_meters": 66304, "time_ahead_seconds": 3970,
          "progress_fraction": 0.28, "requires_backtracking": false
        }
      }
    ],
    "meta": {
      "returned": 5, "candidates_considered": 6, "within_corridor": 5,
      "detour_evaluated": 5, "closed_only": false, "from_cache": false,
      "corridor_meters": 5000, "max_detour_duration_seconds": 900
    }
  }
}
```

Every route figure can be null, and null means **not established** — never zero.

`meta` is returned so a client can say something useful about an empty screen
("nothing within 5 km of your route") instead of guessing, and so the performance
evidence is a measurement rather than an assertion.

### Error codes

| Code | HTTP | When |
| --- | --- | --- |
| `ROUTE_NOT_READY` | 409 | No usable selected route — go back to the route screen |
| `DISCOVERY_FAILED` | 500 | The search could not complete |
| `DISCOVERY_RATE_LIMITED` | 429 | Too many searches |
| `RESTAURANT_DATA_UNAVAILABLE` | 503 | The restaurant store is unreachable |
| `DETOUR_PROVIDER_UNAVAILABLE` | 503 | The routing provider is down |
| `TRIP_NOT_FOUND` | 404 | No such journey, or not the caller's |

---

## Caching

Two caches, at different layers and with different lifetimes.

| Cache | Key | TTL | Why |
| --- | --- | --- | --- |
| Detour | route uuid + restaurant uuid | 1 h | The road network does not change on the minute, and this is the expensive figure |
| Result selection | route uuid + hash of the discovery config | 5 min | Saves the corridor work on a reopened screen |

**Only the selection is cached, never the rendered payload.** On a cache hit the
restaurants are re-read from the database, re-checked for eligibility, and their
availability is recomputed from live time. So:

- a restaurant **suspended thirty seconds ago cannot ride a warm cache** onto a
  customer's screen — if any cached uuid is no longer discoverable the whole
  result is recomputed rather than served short;
- opening times are always current, because availability is never cached.

The result key includes a hash of the discovery configuration, so changing a
threshold invalidates every cached answer rather than leaving a mixture of old
and new rules in flight. Changing or recalculating the route produces a new route
uuid and therefore a new key.

---

## Configuration

| Setting | Default | What it means |
| --- | --: | --- |
| `DISCOVERY_CORRIDOR_METRES` | 5 000 | How far off the road is still worth evaluating |
| `DISCOVERY_MAX_CANDIDATES` | 300 | Bound on the geometric work |
| `DISCOVERY_MAX_DETOUR_EVALUATIONS` | 12 | **The cost ceiling** — billed calls per request |
| `DISCOVERY_MAX_DETOUR_DISTANCE_METRES` | 15 000 | Beyond this it is a different journey |
| `DISCOVERY_MAX_DETOUR_DURATION_SECONDS` | 900 | Likewise |
| `DISCOVERY_RESULT_LIMIT` | 25 | What a customer is given |
| `DISCOVERY_CACHE_TTL_SECONDS` | 300 | Result-selection cache |
| `DISCOVERY_SIMPLIFY_TOLERANCE_METRES` | 150 | Geometry simplification |
| `DISCOVERY_DEFAULT_TIMEZONE` | `Asia/Kolkata` | Fallback only, and logged |
| `RATE_LIMIT_DISCOVERY` | 30/min | Per authenticated customer |

Every one is a pilot assumption rather than a fact about the world, which is
exactly why none is written into a service.

---

## Privacy and security

**A route is a description of where somebody will be. A discovery is that plus
where they intend to stop and roughly when**, which is worse.

- Discovery is scoped to the trip's **owner**, even though restaurants themselves
  are public. A foreign trip is **not found**, indistinguishable from one that
  never existed.
- The log carries counts and uuids — candidates, corridor survivors, detours
  evaluated, duration — and **never** a restaurant name, a coordinate, or route
  geometry.
- No private restaurant column reaches a customer. The API shape is an
  **allow-list** built by hand in `toDiscoveryArray()`, not `$hidden`: a deny-list
  exposes the column somebody adds next month until they remember to hide it.
- Restaurants are told nothing. A restaurant does not need to know a customer is
  browsing it, and Module 07 tells it nothing.
- Analytics receives no route, no destination and no restaurant selection.

---

## Test fixtures

`DiscoveryTestRestaurantSeeder` creates eight rows, every name prefixed
**`[TEST]`**, and it **refuses to run in production**. Positions are computed —
a stated fraction along the pilot route, offset perpendicular by a stated
distance — so "900 m off the route" is a fact the seeder guarantees rather than a
coordinate somebody hoped looked right.

| Fixture | Condition | Expected |
| --- | --- | --- |
| Highway Spice Kitchen | 900 m off, 28% along, open | Discovered |
| Rajasthan Highway Bites | 2.4 km off, 62% along, open | Discovered |
| Paused Highway Grill | 1 km off, open, not accepting orders | Discovered, marked paused |
| Closed Route Cafe | 1.1 km off, hours already ended | Discovered, marked closed |
| Behind You Diner | 600 m off, **before** the origin | Discovered, flagged, listed last |
| Far Away Kitchen | 60 km off | Not discovered |
| Suspended Dhaba | 800 m off, suspended | **Never** discovered |
| Pending Restaurant | 700 m off, unverified | **Never** discovered |

They are fixture positions, not real addresses. Nothing claims a business exists
at these points.

---

## Module 08 handoff

Left deliberately unbuilt, with the fields ready:

- **Filters** — cuisine, price level, rating, availability, facilities and detour
  are all stored, indexed where it matters, and returned.
- **Sorting** — nearest along route, lowest detour, highest rated. The ranking
  service is a single deterministic function with named weights; a customer-chosen
  sort replaces the final ordering without touching the pipeline.
- **Search** — no text search exists here.
- **Clustering** — the map draws one marker per result. With a result limit of 25
  that is legible; the marker layer is built so clustering can be introduced
  without changing the data.
