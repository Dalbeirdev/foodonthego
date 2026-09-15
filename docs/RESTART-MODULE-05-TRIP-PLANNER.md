# RESTART MODULE 05 — TRIP PLANNER

Customer Web + Android + iOS. Origin, destination, saved addresses, current
location and place search.

Branch `claude/foodonthego-s0x2vt`. Continues Restart Modules 01, 02 and 03.
**Restart Module 04 was never run** — see [Restart Module 04's gap](#restart-module-04-was-skipped) below,
which changed what this module had to build.

---

## 1. What was actually there before

The audit found something the original Module 05 completion report did not say:
**the backend was complete and good, and no browser could reach any of it.**

| Layer | Before this module |
| --- | --- |
| Trip model, migration, `TripService` | Complete. Ownership, endpoint resolution, coordinate validation, same-place rule, pending-trip limit. |
| `POST/GET /api/v1/customer/trips` | Complete, with 30 API tests and 14 ownership/injection tests. |
| `PlaceProvider` abstraction | Complete: interface, `GooglePlacesProvider`, `DevelopmentGazetteerProvider`, `UnconfiguredPlaceProvider`. |
| `/api/v1/customer/places/{search,reverse-geocode,{place}}` | Complete and authenticated. |
| Saved addresses (Module 04) | Complete backend. |
| Flutter planner | Present in source: `trip_planner_screen.dart`, `location_picker_sheet.dart`, `place_search_controller.dart`, `current_location_controller.dart`. |
| **Customer Web planner** | **Did not exist.** `/trips/plan` rendered `SectionComingLater`. |
| **Customer Web trips tab** | **Did not exist.** Same placeholder. |
| **Customer Web saved addresses** | **Did not exist.** `/profile` had a sign-out card and nothing else. |

Before-state evidence: `docs/evidence/restart-module-05/restart-m05-before-web-*.png`.

So this module is almost entirely a **Customer Web** module. Nothing in the
backend needed building; three things in it needed fixing, all found by running
the thing rather than by reading it.

---

## 2. Restart Module 04 was skipped

Module 05's brief requires, twice and in bold:

> SAVED ADDRESSES — Reuse real Restart Module 04 API. Origin/Destination selectors must offer: Home / Work / Other.
>
> SAVED ADDRESS INTEGRATION — Restart Module 04 Home/Work/Other must appear in planner. **Mandatory.**

Restart Module 04 was never run — the sequence went 03 → 05. Its **backend** is
complete and tested; its **Customer Web** surface did not exist, so a browser had
no way to create a saved address and the planner's mandatory Home/Work/Other
could never appear for a web customer.

Rather than ship the planner with the mandatory requirement unmet, this module
built **the minimum saved-address surface the planner needs**: list, create,
delete, at `/profile/addresses`. Explicitly *not* built: editing an address,
changing the default, and the profile fields (name, phone, email). Those remain
Restart Module 04's, and are recorded as **MF-26**.

One design consequence worth stating: an address created here is created **from a
place the customer picked** through this server's own provider, so it always
carries real coordinates and is always usable for a journey. The "saved address
with no map location" case the server guards against cannot be created by this
screen — though the planner still renders one as unusable, with the reason,
because the Flutter app and the API can both still produce one.

---

## 3. Architecture

### Place search goes through this server

The browser never talks to a place provider. `GET /api/v1/customer/places/*` is
authenticated, the provider key lives in the server's configuration, and the
customer's own session gates every call.

That is the whole of the key-security answer for Customer Web: **the bundle
contains no provider key of any kind**, restricted or otherwise, because it never
makes a provider request. Verified by searching the production bundle — see §7.

### Files

| Concern | File |
| --- | --- |
| Normalised selection, request body, same-place rule | `web/apps/customer/src/trips/location.ts` |
| Every API call the planner makes | `web/apps/customer/src/trips/tripsApi.ts` |
| Customer-safe error copy (allow-list) | `web/apps/customer/src/trips/tripErrors.ts` |
| Autocomplete: debounce, abort, session token | `web/apps/customer/src/trips/usePlaceSearch.ts` |
| Browser geolocation state machine | `web/apps/customer/src/trips/useCurrentLocation.ts` |
| Choosing one end of a journey | `web/apps/customer/src/trips/LocationPicker.tsx` |
| The planner screen | `web/apps/customer/src/trips/TripPlannerScreen.tsx` |
| Trips tab | `web/apps/customer/src/trips/TripsScreen.tsx` |
| One journey — the Module 06 handoff | `web/apps/customer/src/trips/TripScreen.tsx` |
| Saved places | `web/apps/customer/src/addresses/AddressesScreen.tsx` |
| Backend service (unchanged) | `backend/app/Services/Trip/TripService.php` |
| Place provider (unchanged) | `backend/app/Services/Places/PlaceProvider.php` |

### The normalised selection

`LocationSelection` carries `sourceType`, a display name, an optional formatted
address and place id, coordinates, and an optional saved-address id. The CTA
rule, the summary, the validation and the request body all read the same fields
whichever of the three sources filled them.

`sourceType` is carried explicitly and never inferred from which fields happen to
be populated.

### What each source submits

| Source | Request body for that end |
| --- | --- |
| `SAVED_ADDRESS` | `{source_type, saved_address_id}` — **and nothing else** |
| `PLACE_SEARCH` | `source_type`, `place_id`, name, address, coordinates, locality |
| `CURRENT_LOCATION` | `source_type`, name, coordinates (no place id) |

A saved address sends its identifier alone because the server resolves the row
through Module 04's ownership-scoped lookup and reads the position from it. A
client that sent coordinates would be sending values that are ignored — and
sending them anyway would create the appearance of a trust boundary that is not
there. Proved in both directions in §6.

---

## 4. Cost control — measured, not estimated

Measured in a real browser against the real API, by recording every request the
page made.

| Action | Autocomplete | Place details | Reverse geocode | Routes | Razorpay |
| --- | --- | --- | --- | --- | --- |
| Typing `jaipur air` — **10 characters** | **1** | 0 | 0 | 0 | 0 |
| Selecting one suggestion | 0 | **1** | 0 | 0 | 0 |
| Selecting a saved address | **0** | **0** | **0** | 0 | 0 |
| "Use my current location" (granted) | 0 | 0 | **1** | 0 | 0 |
| Creating the journey | 0 | 0 | 0 | **0** | **0** |

Debounce: **350 ms** (`DEBOUNCE_MS`). Minimum query length: **2** characters,
matching the server's own `min:2` — a one-character request could only ever be a
422.

Session tokens: one is minted when a search begins and sent with **every query
and the details call that ends it**, so the provider bills one autocomplete
session rather than one per keystroke. It is rotated when a place is chosen or
the picker closes. Both properties are asserted in
`usePlaceSearch.test.ts`.

Creating a journey calls **no** routing provider. `TripService::create()` reads
the database and writes one row; `route_status` is written as
`NOT_CALCULATED`. Routing is Restart Module 06's.

---

## 5. Location, honestly

Permission is requested **only** when the customer taps "Use my current
location". Nothing runs on mount, there is no `watchPosition` anywhere in the
app, and no background or always-on location is requested.

| State | What the customer sees |
| --- | --- |
| Granted, provider can name it | The place name, over the device's own coordinates |
| Granted, nothing can name it | **"Current location"** over the real coordinates — no invented street |
| Blocked / denied | What is blocked, and that saved places and search still work |
| Insecure page (http) | That browsers need https — checked *before* the API is touched |
| No geolocation API | That this browser cannot share a location |
| Timeout | To try again, or choose another way |
| **No answer at all** | That the browser did not answer, after a 15 s application-side watchdog |

The last row is not theoretical. In the live run, an origin with geolocation
blocked made Chromium call **neither** callback and **not honour its own
`timeout` option**: the button span for twenty seconds and the only escape was a
reload. The watchdog is the fix, and the whole of it is that a screen must not
depend on a third party calling it back to leave a loading state.

Accuracy is shown, never used to reject a fix. A 900 m wifi lookup still names
the right town, and refusing it would fail exactly the customers whose GPS is
worst.

**Reverse geocoding is awaited, not fired and forgotten.** The first version
resolved on the device fix and improved the label when the lookup returned —
which read well and did not work, because a resolved fix *is* the choice, so the
picker closed, the hook unmounted, and the answer arrived for a component that no
longer existed. The call was paid for and the label discarded. It is now awaited
with a 3 s bound: past that the fix resolves unnamed, exactly as it does when the
provider has no name for it.

---

## 6. Security, driven live

Every row below was run against the live API with two real customer sessions.

| Attack | Result |
| --- | --- |
| Home → Home | `SAME_LOCATION`, refused |
| Ananya submits Rahul's saved-address id | `ADDRESS_NOT_FOUND` — the same 404 a direct read gives, so the endpoint is not an oracle |
| `customer_id` in the create body | Ignored; the trip belongs to the authenticated caller. Rahul then gets 404 on it |
| Foreign trip read | 404, **byte-identical** to a nonexistent uuid |
| **Saved address + tampered coordinates** | Stored as the saved row's own position and label. `19.0760, 72.8777` and `"NOT MY HOUSE"` never reach the database |
| Latitude 999 | `VALIDATION_FAILED` |
| (0, 0) | `INVALID_COORDINATES` — its own code |
| Idempotency-Key replayed | Same trip id, `Idempotency-Replayed: true` |
| **Negative control:** same body, no key | **Two different trips** — so the replay above is the mechanism working, not the request being rejected |
| **Negative control:** same tampered coordinates via `PLACE_SEARCH` | **Honoured** — so the row above is the saved address overriding them, not a validator dropping unknown keys |
| 401 mid-search | Token cleared, redirected to `/login`, no anonymous trip |
| Sign out, sign in as another customer | Empty planner, no saved places, only her own trips |

The last two negative controls matter more than the positives. A green security
result is worth nothing until the check has been seen to fail.

### Privacy

`trip.created` records the actor uuid, the trip uuid, the two **source types** and
the route status. It records **no place, no address and no coordinate**. Search
queries were never logged (the query string is not part of the logged path, and
request bodies are never logged at all).

One leak was found by reading the live log: `api.request` wrote the concrete
path, so `GET /customer/places/{place}` put a provider place id next to
`actor_id` — a record of where a named customer was going. Fixed by redacting
private route-parameter values from the logged path, by value, so a url-encoded
id cannot survive.

The existing `TripLoggingTest` had stayed green throughout because its round
called search and create but never the details endpoint — the one endpoint that
puts a place identifier in a URL. The round now calls it, and the new assertion
was confirmed to fail without the fix.

---

## 7. Provider keys in the client

| Artefact | Result |
| --- | --- |
| Customer web production bundle | No provider key, no Google endpoint, no `maps.googleapis.com` — the browser never calls a provider |
| Repository, tracked files | No API key literal |
| Docs | None |

Android and iOS carry no Maps key either, which is **MF-08** and is why map tiles
will not render on any platform — unchanged by this module, which draws no map.

---

## 8. Route handoff to Restart Module 06

On success the planner navigates to `/trips/{tripId}` with `replace: true`, and
**only the id is carried across**. The journey screen loads the trip from the
server by id, so it renders the same thing whether it was opened from the
planner, a bookmark or a refresh — the row is authoritative, and a screen that
rendered what the previous screen *said* would happily show a journey that was
never saved.

A foreign trip id answers the same 404 as one that does not exist.

The journey screen says **"Route not calculated yet"** in words. No map, no
distance, no travel time, no ETA — none of them exist, and a blank map would read
as a feature that failed rather than one that has not arrived.

### What Module 06 receives

`GET /api/v1/customer/trips/{uuid}` returns `id`, `status` (`ROUTE_PENDING`),
`route_status` (`NOT_CALCULATED`), and for each of `origin` and `destination`:
`source_type`, `display_name`, `formatted_address`, `latitude`, `longitude`,
`place_id`, `city`, `region`, `country_code`, `postal_code`.

`POST /api/v1/customer/trips/{trip}/route/calculate` already exists and is
Module 06's entry point. Its provider configuration (`ROUTES_PROVIDER`) is a
separate blocker — **MF-12**.

---

## 9. Tests

| Suite | Count | Command |
| --- | --- | --- |
| Backend | 1,344 tests | `backend && vendor/bin/phpunit` |
| Customer web | 74 tests | `web && npx vitest run --root apps/customer` |
| Mobile | 1,063 tests | `mobile && flutter test` |

Added by this module:

- `location.test.ts` — 10. Request bodies per source, distance, the same-place
  rule including a threshold control that must change its answer either side of
  75 m.
- `usePlaceSearch.test.ts` — 7. Six keystrokes → one request; nothing below two
  characters; one session token across a search; a new one after a selection;
  no-results distinct from failure; 401 to the session, not to the screen.
- `useCurrentLocation.test.ts` — 7. No prompt on mount; insecure context refused
  before the API is touched; coordinates kept when nothing can name them; label
  taken but position never; denied ≠ timeout; the watchdog.
- `TripPlannerScreen.test.tsx` — 13. Through the real API client, so the assertions
  are on real request bodies.
- `TripsScreen.test.tsx` — 5, `AddressesScreen.test.tsx` — 4.
- `TripOwnershipTest.php` — 2, the coordinate-tamper test and its control.
- `TripLoggingTest.php` — 1, the place-identifier redaction.

---

## 10. Responsiveness and accessibility

Zero horizontal overflow at 360, 390, 430, 768, 1024, 1280, 1440 and 1920 — for
the planner **and** for the picker dialog open, which is the easiest thing to
overflow and the hardest to notice. The measurement was negative-controlled: a
deliberate 900 px child at 360 reported 540 px of overflow, so the check can fail.

Keyboard only, no mouse, verified in a browser: Tab to the origin field → Enter
opens the dialog → focus lands in the search box → type → ArrowDown/ArrowUp move
`aria-activedescendant` through the options → Enter selects → Escape closes
without choosing.

The field's accessible name carries the label *and* the choice, so a screen
reader announces "Starting point, Home, Green Park, New Delhi. Change" rather
than leaving the listener to work out which field they are on.

Every interactive target is at least 44 px; the two location fields are 56 px,
which is what somebody can hit at a set of lights. The spinner honours
`prefers-reduced-motion` and the loading state is carried in words as well.

---

## 11. What is not done

- **Android and iOS were not looked at by a person.** No Android SDK, no
  emulator, no Apple hardware is reachable from this environment. The Flutter
  planner exists in source and is covered by unit and widget tests. iOS is
  **PENDING — runtime environment unavailable**; it is not a pass.
- **The live Places provider has never been called.** `PLACES_PROVIDER=development`
  serves twelve real places at their real published coordinates. Google's session
  tokens, quota errors and key restrictions are untested against Google. **MF-29.**
- **Browser geolocation cannot work on the review deployment**, which is plain
  http. The insecure-context message is what every visitor there will see.
  **MF-28**, blocked on **MF-16**.
- **Restart Module 04's remaining surface.** **MF-26.**
