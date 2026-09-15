# RESTART MODULE 06 — ROUTING & MAPS

Customer Web + Android + iOS. Route calculation, map, distance, travel time and
route selection.

Branch `claude/foodonthego-s0x2vt`. Continues Restart Modules 01, 02, 03 and 05.
Restart Module 04 remains partly unrun — see **MF-26**.

---

## 1. What was actually there before

| Layer | Before this module |
| --- | --- |
| Route model, migration, `TripRoute` | Complete |
| `RouteProvider` abstraction, Google / development / unconfigured | Complete |
| `RouteCalculationService`, `RouteSelectionService`, `RouteValidator`, freshness, endpoint invalidation | Complete |
| `GET /routes`, `POST /route/calculate`, `POST /routes/{route}/select` | Complete, with 26 API tests and 9 ownership tests |
| Flutter route screen, map view, option cards | Complete in source (708 lines), with a map-unavailable state |
| **Android Maps key wiring** | **MISSING** |
| **iOS Maps key wiring** | **MISSING** |
| **Customer Web route screen** | **MISSING** — `/trips/{id}` said "Route not calculated yet" whatever the route status was |

The before-state capture is the sharpest statement of it:
`restart-m06-before-web-route.png` is a trip whose `route_status` was **READY**,
with a calculated and selected route in the database, on a screen that said
**"Route not calculated yet"**, with no map, no distance, no travel time and no
way onward.

---

## 2. The finding that matters most

**A Maps API key had no path into either native platform.**

`MapsConfig.canRenderMap` (Flutter) turns the map on when `FOTG_MAPS_API_KEY` is
defined at build time. That was the only place the key went.

- The **Android** Maps SDK reads its key from a
  `com.google.android.geo.API_KEY` manifest meta-data element. There was no such
  element and no Gradle placeholder. A `--dart-define` never reaches it.
- The **iOS** Maps SDK requires `GMSServices.provideAPIKey` before the first map
  view. `AppDelegate.swift` never called it.

So the app was arranged to switch its map on the day a key arrived, and both
native SDKs were arranged to have nothing to authenticate with. Android renders
a blank grey map with an authorization failure in logcat; iOS throws. Both are
outcomes the completion rule names as blockers — arriving on the day the
credential did, long after this module was reported complete.

Nothing would have caught it. There is no key in this repository, so
`canRenderMap` is false, no map is ever attempted, and every test passes.

**Fixed, and it needed no credential to fix:** a Gradle `manifestPlaceholders`
entry fed from `-PmapsApiKey` or `FOTG_MAPS_API_KEY`, the manifest element that
reads it, `GMSServices.provideAPIKey` reading a `GMSApiKey` Info.plist value fed
from a `GMS_API_KEY` build setting, and
`mobile/test/maps_key_reaches_the_sdks_test.dart` — seven assertions that read
the build files themselves so the wiring cannot quietly disappear again.

Two things went wrong inside that fix, and both are worth reading:

1. The explanatory comment I put in the manifest contained a Dart define flag
   written with its leading dashes. **XML forbids a double hyphen inside a
   comment**, so the manifest — and `Info.plist`, which had the same text —
   became unparseable. `flutter test`, `flutter analyze` and `dart format` all
   passed, because none of them parses XML, and this environment has no Android
   SDK to build with. CI found it three minutes into `assembleDebug`.
2. The first attempt to guard against it parsed both files with the `xml`
   package. **That check could not fail:** reintroducing the exact double hyphen
   left it green, because that parser is more lenient than Android's manifest
   merger. Only running the control caught it. The dependency was removed and
   replaced with a lexical check of the rule that actually broke — which does
   fail on that input, and says which comment is at fault.

Supplying the key is now one build flag per platform:

```
flutter build apk  -PmapsApiKey=$KEY --dart-define=FOTG_MAPS_API_KEY=$KEY
flutter build ipa  --dart-define=FOTG_MAPS_API_KEY=$KEY --extra-xcode-args GMS_API_KEY=$KEY
```

---

## 3. Architecture

| Concern | Where |
| --- | --- |
| Route API | `POST /api/v1/customer/trips/{trip}/route/calculate`, `GET …/routes`, `POST …/routes/{route}/select` |
| Calculation | `App\Services\Routing\RouteCalculationService` |
| Selection | `App\Services\Routing\RouteSelectionService` |
| Provider interface | `App\Services\Routing\RouteProvider` |
| Google implementation | `App\Services\Routing\GoogleRouteProvider` |
| Persistence | `trip_routes`, one row per option, unique index over (trip, selected) |
| Web screen | `web/apps/customer/src/route/RouteScreen.tsx` |
| Web state machine | `…/useRoute.ts` |
| Web map | `…/RouteMap.tsx` → Google Maps JS, or `RouteShape.tsx` |
| Polyline decode | `…/polyline.ts` (one implementation, tested against Google's own fixture) |
| Formatting and honesty rules | `…/format.ts` |
| Flutter screen | `mobile/lib/features/routes/route_screen.dart` |

### GET never calculates

`GET /routes` reads; `POST /route/calculate` may spend money. The web screen
opens with the GET and only POSTs when there is nothing usable. That split is
the module's whole cost control and it is measured in §6.

### The client is authoritative for nothing

No request this module sends carries a distance, a duration, a traffic figure, a
polyline or a selection flag. The only thing a browser tells the server is
*which* calculated route the customer wants.

---

## 4. The map, and what has actually been verified

Two states of equal standing, mirroring the Flutter design.

**No Maps key exists (MF-08)**, so what this repository renders — and what every
screenshot shows — is the **map-unavailable** state: the route's real polyline,
decoded and drawn in Web Mercator with origin and destination markers and
correct bounds, under a notice saying plainly that tiles are missing and why.

That is not a picture of a map and does not pretend to be one. There is no
basemap, no roads and no labels. It exists because the alternative is the grey
box the brief names as a blocker, and because a customer can still see the shape
of the journey and how alternatives differ.

**The Google Maps path in `RouteMap.tsx` has never been run**, and in a build
with no key it is **not present at all**. `VITE_GOOGLE_MAPS_BROWSER_KEY` is
replaced at build time, so `canRenderGoogleMap()` constant-folds to `false` and
Rollup eliminates the loader, the API URL and everything behind it. Measured
both ways:

| Build | `maps.googleapis` in the bundle | loader id | the key |
| --- | --- | --- | --- |
| No key (what this repository ships) | **0** | 0 | 0 |
| A dummy key defined at build time | 1 | 1 | 1 |

Two things follow, and both matter operationally:

1. A keyless build ships **no Google code whatsoever** — the strongest possible
   form of "no provider key in the client".
2. **The browser Maps key is a build-time input, not a runtime one.** Supplying
   it means rebuilding the customer app with
   `VITE_GOOGLE_MAPS_BROWSER_KEY` set. Dropping it into a running deployment
   does nothing.

`loadGoogleMaps` resolves null rather than throwing on any failure, so a blocked
CDN or a rejected key falls back to the no-tiles state instead of a grey
rectangle — when that code is in the build at all.

---

## 5. Honesty rules in the rendering

| Rule | Where it lives |
| --- | --- |
| No traffic line without a traffic figure | `formatTrafficLine` returns **null**, not `traffic ?? duration` |
| No "Fastest" without a comparison that supports it | `optionLabel` compares like with like, and says nothing on a tie |
| No invented alternatives | One route renders "Your provider returned one route for this journey." |
| Synthetic figures are labelled | Any route whose `provider` is `development` or `unconfigured` gets a warning banner |
| Traffic ages | "Worked out 7 min ago" is shown, so a stale figure is not read as current |
| No ETA | Route duration only. Arrival time is Module 18, which does not exist |

---

## 6. Cost control — measured on the production build

React's StrictMode double-invokes effects in development, which doubles the read
in a `vite dev` run. These are from `npm run build` output served over a
same-origin proxy, which is what a customer gets.

| Action | Billed `calculate` | Free `GET /routes` | Maps | Restaurant | Razorpay |
| --- | --- | --- | --- | --- | --- |
| First open of a new journey | **1** | 1 | 0 | 0 | 0 |
| 5 page refreshes | **0** | 5 | 0 | 0 | 0 |
| 5 × Home → Route | **0** | 5 | 0 | 0 | 0 |
| Fresh session (app restart) | **0** | 1 | 0 | 0 | 0 |

At the API, within the 900-second freshness window:

- Second `calculate`: `calculated_at` **unchanged** — the provider was not called.
- `calculate?refresh=true`: `calculated_at` **changed** — and that is the
  negative control proving the check above can fail.

Maps tile requests are counted separately from Routes calls and were **0**,
because no key means no tiles. Restaurant-discovery calls before the Find Food
CTA: **0**. Razorpay: **0**.

---

## 7. Security, driven live

| Attack | Result |
| --- | --- |
| Ananya calculates on Rahul's trip | 404 `TRIP_NOT_FOUND` — and it would have spent our money |
| Ananya lists Rahul's routes | 404 |
| Rahul's route id used on Ananya's trip | `ROUTE_NOT_FOUND` |
| Ananya selects Rahul's route on his trip | 404 `TRIP_NOT_FOUND` |
| `distance_meters`, `duration_seconds`, `traffic_duration_seconds`, `encoded_polyline`, `is_selected`, `route_status`, `customer_id` in the body | **All ignored.** Stored values unchanged: 236,786 m, 14,179 s, null traffic, the real 154-character polyline |

Added to the suite because the brief calls them mandatory and they were not
covered: **concurrent selection** (two selections in flight leave exactly one
selected) and **`customer_id` injection on a route request**. The database also
carries a unique index over (trip, selected), which an existing test exercises
directly — so a true race is refused by the engine rather than by ordering alone.

### Privacy

`route.*` log events carry the trip uuid, the route uuid, the provider and the
outcome. No polyline, no endpoint coordinates, no key. An existing test greps the
log for `AIza` and for the endpoint names.

---

## 8. Handoff to Restart Module 07

"Find food on this route" is enabled only with a selected route, and carries
`tripId` in the path and `routeId` in the query — identifiers, not data. It lands
on a real screen that names both and says the listing is Module 07's. No dead
click, and nothing that could be mistaken for an empty result.

### What Module 07 receives

- **Trip id** — uuid, in the path.
- **Selected route id** — uuid, in the query, and authoritative on the server as
  the single `is_selected` row.
- **Polyline** — encoded, on the route row, plus `bounds`.
- **Distance / duration / traffic duration** — metres, seconds, nullable seconds.
- **Route status** — `READY`; `STALE` once the trip's endpoints move.
- **Provider** — on every row, so a synthetic figure stays identifiable.
- **Missing dependencies:** a routing credential (**MF-12**) and a Maps key
  (**MF-08**), both the client's to supply.

---

## 9. What is not done

- **Android and iOS were not looked at by a person.** No SDK, emulator or Apple
  hardware is reachable here. **MF-27.**
- **The Google Maps browser path has never executed.** **MF-08.**
- **No real routing provider has ever been called.** Every figure in this module
  comes from the straight-line development stand-in. **MF-12.**
- **Route alternatives have never been seen live.** The development provider
  returns one route by design and must not fabricate a second. The alternatives
  UI is covered by component tests with fixture data, and reported as
  **NOT RETURNED BY PROVIDER** live.
- **No offline route cache.** Losing the network shows an honest connection
  message and a retry; it does not serve a previously calculated route from
  local storage. **MF-30.**
