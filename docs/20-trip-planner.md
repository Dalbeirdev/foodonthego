# 20 — Trip planner

A trip is an origin and a destination. That is the whole of Module 05, and the
restraint is the point: the product's centre of gravity is the *timing* — food
ready when a traveller arrives — and everything that decides timing depends on a
route, which nothing in the system can compute yet.

So this module answers one question well ("where are you going, and where from")
and refuses to answer the next one at all.

---

## The boundary

Module 05 ends where Module 06 begins, and the line is drawn in the schema rather
than in a convention somebody has to remember.

| In Module 05 | Explicitly Module 06's |
| --- | --- |
| Choosing an origin | Route calculation |
| Choosing a destination | Route polyline and geometry |
| Place search, and resolving a place to a position | Distance |
| The device's current location | Travel duration, traffic-aware or otherwise |
| Selecting a saved address | Route alternatives |
| Creating a trip, and persisting both ends | Displaying a route, or validating one |

**Modules 06 and 07 have since been built**, and they did not change a word of
the above.
Routing lives in its own table (`trip_routes`) and its own endpoints; `trips`
still has no distance, duration or polyline column, and a trip that has never been
routed still reports `NOT_CALCULATED`. What Module 06 added to this module's
surfaces is a *summary* — distance and duration, no geometry — attached to a trip
only when the status is `READY` **and** the endpoints have not moved since. See
[21-maps-and-routing.md](21-maps-and-routing.md).

There is **no** `distance`, `duration`, `polyline` or `eta` column on `trips`,
and no such key in any API response. A column is an invitation to fill it, and a
nullable one is an invitation to render "0 km" while it is still null.

The one thing this module *does* record about routing is that none has happened:
`route_status` is `NOT_CALCULATED` on every row Module 05 can create. The app
reads that value rather than assuming it — which is why Module 06 moving that
value cost this module's screens nothing but a new branch for `READY`.

---

## Two statuses, not five

`TripStatus` has `ROUTE_PENDING` and `CANCELLED`. That is all this module can
honestly observe.

"On the road", "arrived" and "completed" are claims about a traveller's physical
position. Module 05 has no way to establish any of them: no route, no arrival
signal, and — deliberately — no ongoing knowledge of where anybody is. It could
ask the customer to tap a button, but a self-reported travel state is a claim the
platform cannot verify, and the restaurant queue is eventually sorted by
**expected arrival**. An invented travel state becomes an invented cooking time,
which is the one failure this product cannot absorb.

There is no "past" scope either, for the same reason: nothing here observes a
journey happening, so a tab for finished journeys is a tab that never fills.

---

## Places come through this server, never from the device

The app holds no provider key and makes no provider call. Every lookup goes to
`/api/v1/customer/places/*`, which is authenticated — an open endpoint on a
server holding a metered key is somebody else's free geocoder, and the bill
arrives here.

Three providers sit behind one `PlaceProvider` interface, following the pattern
Module 03 established for OTP delivery:

| Provider | Role |
| --- | --- |
| `GooglePlacesProvider` | The real one. Places API (New) autocomplete and details, plus Geocoding for reverse lookup. |
| `UnconfiguredPlaceProvider` | Refuses every call, loudly, and blocks a production boot through `ProductionConfigGuard`. |
| `DevelopmentGazetteerProvider` | A dozen real places with their real published coordinates, for development and automated verification. Refuses to be constructed in production. |

The gazetteer's identifiers are namespaced `dev:` so a row in the database or a
line in a log can never be mistaken for a provider place id, and so a query for
real place ids finds none of them. Its coordinates are the **real published
positions of real places**, because a fabricated coordinate is indistinguishable
from a true one to the routing it will feed; what is limited is the *size* of the
gazetteer, which is a limitation anybody can see rather than one hiding inside
plausible-looking data.

### API key handling

The key lives in the backend's environment (`GOOGLE_PLACES_API_KEY`) and is sent
in the `X-Goog-Api-Key` **header**, never in a query string — a key in a URL ends
up in access logs, proxy logs and referrer headers. A `X-Goog-FieldMask` header
accompanies every Details call, because Google bills by the fields requested and
the default is everything.

Because no key ever reaches a device, the restrictions that apply are the
server-side ones:

| Restriction | Value |
| --- | --- |
| Application restriction | **IP addresses** — the backend's egress addresses only |
| API restriction | Places API (New) and Geocoding API, nothing else |
| Android package/signing restriction | Not applicable — the app never calls the provider |
| iOS bundle-id restriction | Not applicable — same reason |

`.env.example` carries this guidance next to the key itself, so whoever
configures it reads it at the moment it matters. Unrestricted keys are what turn
a quota into a bill.

### Session tokens

One token spans a whole search: minted when the search sheet opens, sent with
every autocomplete request, sent once more with the Details call that resolves
the chosen place, then discarded. A token per keystroke bills exactly like no
token at all; a token that lives forever is a session that never closes.

### Debounce and the stale-answer guard

Autocomplete waits **350 ms** after typing stops before dispatching, and every
dispatch carries a generation number. An answer whose generation is no longer
current is discarded rather than rendered.

Both are necessary and neither is sufficient. Without the debounce, a six-letter
word costs six metered requests. Without the generation guard, a slow answer for
`jai` arriving after a fast one for `jaipur airport` overwrites the correct list,
and the customer reads results for a word they finished typing seconds ago. The
race is exercised directly in `test/place_search_test.dart`.

---

## Each end is a snapshot, not a foreign key

A trip copies the values out of whatever produced them. The saved-address id is
kept only as provenance, with `ON DELETE SET NULL`.

Editing the address a journey was planned from does not move the journey, and
deleting it does not take the journey with it. Both are verified against a real
database in the integration run. The alternative — a foreign key read at display
time — means somebody correcting a typo in their home address silently rewrites
where a journey started.

Coordinates on `trips` are **NOT NULL** at both ends. A trip that cannot be
routed should never have been created, and pushing that judgement downstream is
how Module 06 ends up drawing a corridor from a guess.

---

## Coordinates are never invented

The rule, in the four places it applies:

- **A saved address with no position** cannot be one end of a journey. The picker
  says so and points at the search box. Nothing geocodes the typed address lines
  behind the customer's back — an address is a description a person wrote, and a
  coordinate is a claim about a point on the earth.
- **A place with no position** in a Details response is a failure, not a place.
  The adapter raises rather than deriving one from the address text.
- **A device fix that cannot be named** is still a device fix. The coordinates
  stand; the endpoint is labelled "Current location", which is true of any
  coordinate. Reverse geocoding never *replaces* the caller's coordinates with a
  landmark's — snapping a fix to the nearest known place moves somebody's
  starting point by kilometres.
- **(0, 0)** is refused outright. It is a real point in the Gulf of Guinea and the
  usual value of an uninitialised coordinate, so a journey drawn to it crosses an
  ocean while looking entirely ordinary in a list.

Module 04 accepted `latitude`/`longitude` on an address but the app never sent
any, so no saved address could ever be used here. Module 05 closes that: the
address form offers **Find this address**, which opens place search — search
only, because offering the device's position would pin an address somebody is
describing from memory to wherever they happen to be standing.

---

## Location: asked for once, in the tap that needs it

Permission is requested from exactly one place — the "Use my current location"
row — and nowhere else. Not at launch, not on a splash screen, not as the price
of opening the planner. An app that asks before the customer has any reason to
say yes is an app most people say no to, and a denial is much harder to undo than
a question deferred.

Every outcome gets its own screen, its own words and its own way onwards:

| Outcome | What the customer is told | What they can do |
| --- | --- | --- |
| Granted | — (the origin is filled in) | Carry on |
| Granted, but coarse (> 500 m) | "This location is approximate" | Keep it or choose another |
| Denied | "Location not shared" | Try again · Search instead |
| Denied permanently | "Location is blocked" | Open settings · Search instead |
| **Services switched off** | "Location is switched off" | Try again · Search instead |
| Timed out | "We could not find you" · "common indoors" | Try again · Search instead |
| Platform failure | "Location unavailable" | Try again · Search instead |

Two of those rows carry most of the weight.

**Services off is not a denial.** The permission may be granted and the answer
still be this one. Reporting it as a refusal sends somebody to an app-permission
screen where everything already looks correct.

**Every screen offers a search box.** A permission wall with no alternative is
how an app traps a customer, and there is nothing here that search cannot do
instead.

There is no ongoing location tracking anywhere in Module 05: one fix, on demand,
discarded once the trip is created. No position stream, no background permission,
no "always" authorisation.

### The hard deadline

`Geolocator`'s own `timeLimit` is advisory — on the web it is not honoured at
all, and an unanswered permission prompt leaves the underlying future pending
forever. The picker sat on "Finding you…" indefinitely in a browser that never
resolved the prompt.

So the operation carries a Dart-side deadline of 25 seconds
(`kLocationDeadline`), applied in the controller so it holds for *any*
`LocationService` implementation, present or future. It is generous because on a
phone that window is mostly a system dialog with a person deciding behind it. If
it does expire, the screen says so and offers another go — recoverable. A spinner
with no end is not.

---

## Ownership is the shape of the API

No route in this module takes a customer id. `TripService::ownedByOrFail()` is
the only path to a trip, and both "no such trip" and "not yours" answer **404**,
so the API cannot be used to discover which ids are real.

The subtle one this module adds is planning a journey *from somebody else's saved
address*. It is closed by construction rather than by a check: `resolveEndpoint`
calls Module 04's `CustomerAddressService::ownedByOrFail()` instead of querying
the address table, so there is no code path in which an unowned address is read.
And `saved_address_id` is validated as a `uuid` and deliberately **not** with
`exists:customer_addresses,uuid` — an existence rule would confirm that another
customer's address is real before anybody had checked who owns it.

`StoreTripRequest` accepts exactly two keys, `origin` and `destination`. A body
carrying `customer_id`, `status`, `route_status`, `distance` or `eta` validates
fine and has no effect: `Trip` has an empty `$fillable`, and the service writes
every column by name. Verified against a real server in the integration run.

---

## What gets logged, and what does not

Where somebody is travelling from and to is the most sensitive thing this module
holds, and a search query is close behind: what a person types into a search box
is a statement about where they are going.

| Logged | Never logged |
| --- | --- |
| `trip.created`, `trip.discarded`, `trip.access_denied` | Any place name |
| The trip's uuid and the actor's uuid | Any coordinate |
| Which *kind* of source each end used | Any search query |
| `route_status` | The provider key, or any provider message |
| A request/correlation id on every line | Phone numbers |

The source kinds are worth keeping — how people actually choose places is an
operational question — and they say nothing about where. `TripLoggingTest` reads
what the application actually wrote to disk during a full round of operations
rather than asserting on a redaction helper: the risk is not a missed key, it is
a call site that logged the whole payload because it was convenient at the time.

The same rule governs analytics: no full addresses, no coordinates, no phone
numbers in any event.

---

## Cache and account isolation

The place-search cache is keyed by the **query and region bias only**, never by
the customer. Nothing customer-specific goes in, so nothing customer-specific can
come back out under another account, and two people searching for the same
airport cost one request.

Everything customer-specific is the opposite: the planner draft, the search
state and the session token live on `autoDispose` providers that die with the
sheet, and the trips list watches the session, so signing out disposes it. There
is nothing to remember to clear because there is nothing kept.

---

## The API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/customer/places/search?q=&session_token=` | Autocomplete. Minimum two characters. |
| `GET` | `/customer/places/{place}?session_token=` | Resolve one suggestion to a position. |
| `POST` | `/customer/places/reverse-geocode` | Name a coordinate. A null answer is a success. |
| `GET` | `/customer/trips?status=` | The customer's trips. `status` takes a `TripStatus` value. |
| `GET` | `/customer/trips/current` | The most recent open trip, or null. |
| `GET` | `/customer/trips/{trip}` | One trip. |
| `POST` | `/customer/trips` | Create. Two keys: `origin`, `destination`. |
| `POST` | `/customer/trips/{trip}/discard` | Call it off. |

There is no `DELETE`: a trip is discarded, never erased, and later modules' orders
will point at it. Discarding is a POST to a named action rather than
`PATCH {"status": "CANCELLED"}`, because `status` is never an accepted field
anywhere in this module — so no request shape can set a trip to an arbitrary
state.

The list filter is the server's own `status` vocabulary rather than words of the
client's. An unknown query parameter is *ignored* rather than refused, so a
client sending its own dialect gets a complete list back and looks entirely
healthy — which is exactly the defect that shipped briefly and is now pinned by
a test.

---

## Error codes

| Code | Status | Meaning |
| --- | --- | --- |
| `ORIGIN_REQUIRED` / `DESTINATION_REQUIRED` | 422 | An end was not supplied. |
| `SAME_LOCATION` | 422 | Both ends resolve to the same place (75 m, or a matching place id). |
| `INVALID_COORDINATES` | 422 | Out of range, or the (0, 0) sentinel. |
| `SAVED_ADDRESS_NOT_LOCATED` | 422 | The address has never been located. Locate it; do not retry. |
| `TRIP_LIMIT_REACHED` | 422 | Twenty open trips. |
| `TRIP_NOT_FOUND` | 404 | Missing, or not yours. Indistinguishable, deliberately. |
| `ADDRESS_NOT_FOUND` | 404 | Same, for a saved address. |
| `PLACE_NOT_FOUND` | 404 | The provider does not know that id. |
| `TRIP_CREATE_FAILED` | 500 | Ours. Offer a retry, not a field. |
| `PLACE_LOOKUP_FAILED` | 503 | The provider is down. Ours, not the customer's. |

Nothing from a provider's own message reaches a client: an upstream error names
our project, our key state and our quota.

---

## What the app shows, and what it refuses to

The planner is two rows and a button. No map, no route line, no distance, no
travel time, no arrival estimate — and it says so in as many words rather than
showing a placeholder that looks like it is loading something:

> Route and travel time arrive with the next release. This saves where you are
> going.

Every trip row and the trip detail screen say **"Route not calculated yet"**.
Several tests exist purely to fail the day somebody replaces that with a number.
