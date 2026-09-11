# 21 — Maps and routing

Module 06 turns a trip into a road route: a real distance, a real travel
duration, a real polyline, and — where the provider supplies one — a real
traffic-aware duration alongside it.

Nothing in this module estimates. Every figure a customer sees came out of a
routing provider's response, was validated on the way in, and is stored as the
provider gave it. Where a figure is absent, it stays absent: there is no fallback
straight line, no derived speed, and no zero standing in for "we do not know".

---

## Travel duration is not the ETA

The number this module produces is the **travel duration**: how long the routing
provider thinks the drive takes. That is all it is.

The FoodOnTheGo ETA — when a traveller will reach a particular restaurant, and
therefore when that restaurant should start cooking — is a later engine that
takes this duration as one of several inputs. It also needs the restaurant's
position along the corridor, its preparation time, its current queue, and the
traveller's live progress. None of those exist yet.

So the screen says **"Travel time"**, and underneath it, in words:

> Driving time from the route. Pickup timing arrives with restaurants.

The word "ETA" does not appear anywhere in this module's UI, and a live check of
the rendered app asserts its absence.

---

## What Module 06 does not own

| Module 06 | Later |
| --- | --- |
| The route between two places | Restaurants along it (**built — Module 07**) |
| Distance and travel duration | Cooking start prediction |
| Traffic-aware duration, when supplied | Restaurant preparation intelligence |
| Route alternatives and which one is chosen | Live GPS progress |
| The map that draws them | Dynamic ETA during a journey |

---

## The provider abstraction

`App\Services\Routing\RouteProvider` is a two-method interface over "give me
routes between these two points". Three implementations exist, and which one is
bound is a matter of configuration:

| `ROUTE_PROVIDER` | Behaviour |
| --- | --- |
| `google` | Google Routes API v2 `computeRoutes`. The real one. |
| `unconfigured` | Fails loudly on every call, and **blocks production boot** through `ProductionConfigGuard`. The default. |
| `development` | A straight line between the two points, for local work. Refuses to be constructed in production, labels itself `development` in the stored row, in the API response and in a warning banner on the screen. |

The development provider is a stand-in, not a fallback. It is never selected
automatically, it can never run in production, and it never invents a traffic
figure or a second route — the two things that would be indistinguishable from
real data once stored.

### Google Routes API v2 specifics

The request asks for exactly six fields:

```
routes.distanceMeters,routes.duration,routes.staticDuration,
routes.polyline.encodedPolyline,routes.description,routes.viewport
```

A field mask is not a nicety on this API — it is the difference between a cheap
response and an expensive one, and between receiving six fields and receiving
several hundred kilobytes of turn-by-turn steps this module has no use for.

With `routingPreference: TRAFFIC_AWARE`:

| Response field | Stored as | Meaning |
| --- | --- | --- |
| `staticDuration` | `duration_seconds` | The drive with no traffic model |
| `duration` | `traffic_duration_seconds` | The drive as the provider currently expects it |

When the two are equal, `traffic_duration_seconds` is stored as **NULL**. Equal
values mean the provider had nothing to say about traffic, and recording a
zero-second delay would be a claim about the roads dressed up as a measurement.

Durations arrive as strings (`"16200s"`) and are parsed to integers. A response
whose duration does not parse is rejected as invalid rather than read as zero.

---

## What is stored

`trip_routes`, one row per route the provider returned:

| Column | Notes |
| --- | --- |
| `uuid` | The only route identifier a client ever sees |
| `provider`, `provider_route_index` | Which provider, and its own ordering |
| `summary` | The provider's own description, e.g. "via NH 48" |
| `distance_meters`, `duration_seconds` | Required, positive |
| `traffic_duration_seconds` | Nullable, and null means "not supplied" |
| `encoded_polyline` | `MEDIUMTEXT`; the geometry as the provider encoded it |
| `bounds_north/south/east/west` | The viewport, so a camera can frame the route without decoding it |
| `is_recommended` | The provider's first route |
| `is_selected` | The customer's choice |
| `endpoints_fingerprint` | The endpoints this route was calculated for |
| `calculated_at` | When the provider answered |

`$fillable` is **empty**. Every field is assigned explicitly by the calculation
service from a validated provider response, so no request payload can reach a
column even by accident.

### One selected route, enforced by the database

```sql
selected_trip_id  AS (CASE WHEN is_selected = 1 THEN trip_id ELSE NULL END)
UNIQUE KEY trip_routes_one_selected_per_trip (selected_trip_id)
```

MySQL ignores NULLs in a unique index, so unselected rows do not collide and two
selected rows for one trip cannot exist. Two concurrent selections cannot both
win, whatever the application code does.

---

## Staleness is closed by construction

A route calculated for one pair of endpoints must never be shown for another.

The endpoints fingerprint is a SHA-256 of both ends' coordinates (7 decimal
places) and place ids. It is **stored** on each route row and **derived** on
demand for the trip — there is no second copy on `trips` to drift out of step.

Every read, calculation and selection first calls
`invalidateIfEndpointsChanged()`. When the derived fingerprint no longer matches
the stored one, the routes are deleted and the trip returns to
`NOT_CALCULATED`. There is no window in which a stale route is visible, because
the check runs before the response is built rather than on a schedule.

`Trip::selectedRouteSummary()` is guarded twice over: the status must be `READY`
**and** the route's fingerprint must match. A summary is never rendered from a
status alone.

---

## Route status

| `route_status` | Meaning | Retryable |
| --- | --- | --- |
| `NOT_CALCULATED` | Nothing asked for yet | yes |
| `CALCULATING` | A calculation is in flight | no |
| `READY` | Routes are stored and usable | no |
| `NO_ROUTE` | The provider considered it and found none | **no** |
| `FAILED` | The provider could not answer | yes |
| `STALE` | Endpoints moved under a stored route | yes |

`NO_ROUTE` is not retryable on purpose. It is the provider's considered answer,
and offering a "try again" button spends a request to be told the same thing.

---

## The API

Three endpoints, all under the authenticated customer scope. No path carries a
customer id; the trip is resolved through the same ownership path Module 05 uses,
and a route is then resolved *within that trip*.

| Method | Path | Calculates? |
| --- | --- | --- |
| `GET` | `/api/v1/customer/trips/{trip}/routes` | **Never** |
| `POST` | `/api/v1/customer/trips/{trip}/route/calculate` | Yes, subject to the freshness window; `?refresh=1` forces |
| `POST` | `/api/v1/customer/trips/{trip}/routes/{route}/select` | No |

A `GET` that can spend money spends it every time a screen rebuilds. That is why
reading and calculating are different verbs on different paths.

All three return the same shape — the trip and its routes together — so a client
never has to hold two responses side by side, and `route_status` can never
disagree with the routes rendered beside it.

```json
{
  "data": {
    "trip": { "id": "…", "route_status": "READY", "selected_route": { "…" } },
    "routes": [
      {
        "route_id": "…",
        "provider": "google",
        "summary": "via NH 48",
        "distance_meters": 278000,
        "duration_seconds": 16200,
        "traffic_duration_seconds": 17100,
        "traffic_delay_seconds": 900,
        "encoded_polyline": "…",
        "bounds": { "north": "…", "south": "…", "east": "…", "west": "…" },
        "is_recommended": true,
        "is_selected": true,
        "calculated_at": "2026-09-05T09:00:00+00:00"
      }
    ]
  }
}
```

`selected_route` on the trip is a **summary**: distance, duration and identity,
with no geometry. Lists and home cards do not need a polyline, and shipping one
to every surface that shows a journey is bandwidth spent on nothing.

### Error codes

| Code | HTTP | When |
| --- | --- | --- |
| `ROUTE_INPUT_INVALID` | 422 | The trip's own endpoints cannot be routed between |
| `ROUTE_NOT_FOUND` | 404 | No such route on this trip |
| `ROUTE_SELECTION_INVALID` | 422 | The route id is not one of this trip's |
| `ROUTE_STALE` | 409 | The endpoints moved while the screen was open |
| `ROUTE_ALREADY_CURRENT` | 409 | That route is already selected |
| `ROUTE_NO_ROUTE_FOUND` | 422 | The provider found no road route |
| `ROUTE_PROVIDER_UNAVAILABLE` | 503 | The provider is down or unreachable |
| `ROUTE_PROVIDER_RATE_LIMITED` | 429 | The provider refused on quota |
| `ROUTE_TIMEOUT` | 504 | The provider did not answer in time |
| `ROUTE_RESPONSE_INVALID` | 502 | The provider answered with something unusable |
| `ROUTE_CALCULATION_IN_PROGRESS` | 409 | One is already running for this trip |

The app tells all eleven apart, because the customer's next move differs for each
and a single "something went wrong" offers the same useless button to all of
them.

---

## Nothing measured comes from the client

The customer sends exactly one thing to this module: which route they want.

`distance_meters`, `duration_seconds`, `traffic_duration_seconds`,
`encoded_polyline`, `is_selected`, `provider` and `route_status` are all
server-owned. A request carrying them is not rejected with a lecture — the fields
simply have no route into the model, because `$fillable` is empty and every
assignment is explicit. A tamper attempt sending `distance_meters: 1`,
`duration_seconds: 1` and `route_status: READY` changes nothing, and the
integration run asserts it.

---

## Cost control

Every provider call is billed, and the route screen is the one people reopen.

| Control | Effect |
| --- | --- |
| `GET` never calculates | Opening the screen costs nothing when a route exists |
| Freshness window (`ROUTE_FRESHNESS_SECONDS`, 900) | A recalculation inside the window returns the stored route without a call |
| Cache lock keyed by trip uuid | Two concurrent calculations for one trip make one provider call |
| Field mask | Six fields, not a full turn-by-turn response |
| `max_alternatives` (3) | Each alternative costs the same as the primary route |
| One auto-calculation per trip in the client | A rebuilt screen does not re-ask |

Six backend tests and several Flutter tests assert the provider was **not**
called, which is the only way this stays true as the code changes.

---

## API keys

Two different keys, and the difference is the whole of the key security here.

| Key | Lives | Restricted by |
| --- | --- | --- |
| Routing (Routes API) | **Backend only** | Server IP where supported, plus API scope: Routes API alone |
| Maps SDK | Inside the app | Android package name **and** signing certificate; iOS bundle identifier; API scope: Maps SDKs alone |

The Maps SDK key ships inside the binary — that is unavoidable for a native map —
so it is restricted to the point of being worthless to anyone who extracts it: it
cannot calculate a route, cannot search a place, and cannot be used from any
other application. The routing key never leaves the server, and the app has no
routing key of any kind.

Neither key is committed. The Maps key is supplied at build time
(`--dart-define=FOTG_MAPS_API_KEY=…`), the routing key through the environment
(`GOOGLE_ROUTES_API_KEY`). Neither is ever logged: the provider's failure path
logs a failure kind, never the request URL or the key.

---

## The route screen

Map above, summary sheet below, in a 4:5 split. The map takes what is left after
the sheet rather than framing itself for the whole screen and then being covered
by it.

- **Camera** frames the whole route once per route, with 72dp of padding, and
  does not re-frame on every rebuild. A camera that resets while somebody is
  panning is a map fighting its user.
- **Markers** at both ends, labelled with the place names.
- **Polylines** distinguish the selected route from alternatives by width *and*
  z-order, not by colour alone.
- **Alternatives** are tappable on the map and selectable from the list, because
  a 4dp line is not a touch target.
- **Selection** is never optimistic. The server decides, and the screen shows
  what came back.

### States

| State | What it shows |
| --- | --- |
| Loading | A skeleton, not a spinner over an empty screen |
| Ready | Map, distance, travel time, traffic delay where supplied, "Calculated N minutes ago" |
| No route | The two places, and no retry button |
| Timeout / rate limited / provider down | What happened, and a retry |
| Offline with a stored route | The route, and a banner saying the figures are the last calculated ones |
| Offline with nothing | An offline state, and no empty map frame |
| Map unavailable | The full route summary, and the two place names — never a blank map |

The map-unavailable state is a first-class state, not a fallback bolted on. A
customer whose tiles will not load still needs to know where they are going, how
far it is and how long it takes.

---

## What Module 07 took from here

Module 07 consumes this module rather than reimplementing any of it, and the two
seams are worth naming because they are the ones a later module will use too.

**The selected route is read through `selectedRouteFor()`**, which already
refuses a route whose trip's endpoints have moved. Module 07 does not re-check
staleness; it depends on that guarantee, and a stale route reaches it as a
refusal rather than as geometry.

**The provider gained waypoints, not a second method.** A detour is "the same
journey, through here", which is one intermediate point on the request already
defined — so `RouteRequest` grew a `waypoints` field, `GoogleRouteProvider` maps
it to `intermediates` with `optimizeWaypointOrder: false` (an optimised ordering
answers a question nobody put), and `DevelopmentRouteProvider` bends its straight
line through them. Every Module 06 call passes an empty list and is unaffected.

The consequence of the second seam is worth being blunt about: **a detour is only
as real as the routing provider**. With the development stand-in the road network
is a straight line, so every stop near the road costs almost nothing to reach and
the detour threshold cannot exclude anything. See KI-012 and M07-055.

## Privacy

A route is a statement about where somebody is going.

- Route geometry is **never logged**, never sent to analytics, and never included
  in a list or summary response.
- Log lines carry the trip uuid, the customer uuid, the provider and the outcome
  — no coordinates, no place names, no polyline.
- Routes are scoped to their trip's owner at every entry point. A route belonging
  to another customer's journey is **not found**, not found-and-refused, so the
  refusal leaks nothing about whether it exists.

The privacy sweep in `docs/evidence/module-06-verification-run.txt` searches the
day's log for thirteen needles — place names, the four test coordinates, polyline
markers, key prefixes and phone numbers — and finds none.

---

## What Module 08 took from here

Nothing new. That is the point.

Module 08 adds search, filters, sorting and pagination on top of Module 07's
discovery result, and reaches a routing provider **zero** additional times to do
it. The detour figures it filters and sorts on are the ones Module 06's provider
produced and Module 07 cached; a customer toggling "Parking" is not a routing
question.

Measured across eleven filter, search, sort and page combinations: zero database
queries and zero provider calls each. See
`docs/evidence/module-08-verification-run.txt`.

The one thing Module 08 reads from this module's configuration is
`discovery.max_detour_duration_seconds` (900 s), which becomes the ceiling of
the customer's detour filter and is published in the response's facets. A
customer cannot ask for a detour limit above the business maximum, because
above it there is nothing to find.

KI-012 still applies. With `ROUTE_PROVIDER=development` the road network is a
straight line, so every in-corridor detour is a few seconds and a detour ceiling
cannot exclude anything at runtime. The detour filter is therefore tested with
detours the test controls, and the integration run reports it as NOT APPLICABLE
rather than letting a reader assume it was exercised.
