# RESTART MODULE 06 — BUG REGISTER

| ID | Requirement | Platform | Severity | Screen / API | Actual | Expected | Root cause | Fix | Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **B06-01** | RM06-001 | Customer Web | **P0** | `/trips/{id}` | "Route not calculated yet" — for a trip whose `route_status` was READY with a selected route in the database. No map, no distance, no duration, no CTA | The route | Restart Module 05 shipped a placeholder journey screen and left the content to this module | Built the route screen, state machine, map layer and handoff | Driven end to end against the real API | **FIXED** |
| **B06-02** | RM06-027, RM06-028 | Android, iOS | **P0** once a key exists | Native map | A supplied Maps key would reach `MapsConfig` and neither native SDK. Android would render a blank grey map with an authorization failure; iOS would throw | The map, or the honest map-unavailable state | The Android SDK reads a manifest meta-data element that did not exist; `GMSServices.provideAPIKey` was never called. A `--dart-define` reaches neither | Gradle `manifestPlaceholders` + manifest element; `provideAPIKey` from Info.plist; a 7-assertion guard test that reads the build files | Guard test passes; the wiring is one build flag per platform | **FIXED** |
| **B06-03** | RM06-013 | Customer Web | P2 | Route error | A real 503 carrying "We could not work out a route right now." rendered as "Something went wrong. Please try again." | The server's own words | The customer-safe allow-list was written for Restart Module 05 and had never heard of the route codes | Read each route code, confirm none names a provider, project, key or quota, then add it | Asserted in `RouteScreen.test.tsx`; re-captured live | **FIXED** |
| **B06-04** | RM06-026, RM06-057 | Customer Web | P2 | Route map | At 1024 the map was 338 px wide — smaller than the 710 px it gets at 768. The map shrank as the screen grew | A map that grows with the space | The split layout started at 1024, where the 272 px rail leaves too little to split | Split at 1200; widen the container above it | Re-measured at all eight widths: 678 → 514 → 606 → 679 | **FIXED** |
| **B06-05** | RM06-025 | Customer Web | P2 | Route map | A wide, shallow route sat in a tall frame it filled about a twelfth of | A drawing shaped like the journey | The SVG had a fixed 3:4 viewBox on desktop | Derive the viewBox height from the route's own projected bounds, clamped | Re-captured at 1280 and 390 | **FIXED** |
| **B06-06** | RM06-070 | Customer Web | P3 | Find Food CTA | The filled CTA rendered underlined, because it is a link | A button that looks like a button | Inherited the global link underline | `text-decoration: none` on the CTA only | Re-captured | **FIXED** |

## Not defects, recorded so they are not mistaken for them

| ID | Finding | Why it is not a bug |
| --- | --- | --- |
| **B06-07** | The route is a straight line | The development provider returns one by design, and says so in `summary` and `provider`. The screen renders a warning banner over it. Fixing it needs a routing credential — **MF-12** |
| **B06-08** | No traffic figure anywhere | The provider returns none, and the screen says so rather than reusing the base duration. **MF-12** |
| **B06-09** | Only one route, so alternatives were never driven live | The provider returns one and must not fabricate a second. Covered by component and backend tests; reported as NOT RETURNED BY PROVIDER. **MF-35** |
| **B06-10** | No map tiles | No Maps key exists. **MF-08** |
| **B06-11** | Two `GET /routes` per open in `vite dev` | React StrictMode double-invokes effects in development only. The production build issues one, which is what the cost table measures |
