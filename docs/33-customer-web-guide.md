# 33 — Customer web app: planning a journey

How a customer plans a journey in a browser, step by step, as it stands at the
end of Restart Module 05.

Every screenshot below is of the **real application** against a **real server**.
Where a step has no screenshot on a platform, this guide says so rather than
pointing at a picture of something else.

---

## Before you start

The customer web app is the React app in `web/apps/customer`. It needs the API
on the same origin, which is what `deploy/nginx` serves in production and what
`npm run dev --workspace apps/customer` proxies locally.

There is **no password**. Sign-in is a phone number and a one-time code — see
section 1 of [31-customer-mobile-guide.md](31-customer-mobile-guide.md), which
is the same flow.

---

## 1. Open Home

`restart-module-05/restart-m05-web-home-active-trip.png`

The greeting, a **Plan a journey** button, and — once you have one — a card for
the journey in progress.

## 2. Tap Plan a journey

`restart-module-05/restart-m05-web-trip-planner-desktop.png`
`restart-module-05/restart-m05-web-trip-planner-mobile.png`

Two fields, **Starting point** and **Destination**, and a **Plan journey**
button that stays inactive until both are chosen and they are not the same
place.

## 3. Choose your starting point

`restart-module-05/restart-m05-web-saved-address.png`

Three ways:

- **Use my current location** — the browser asks for permission at this moment
  and not before. If you allow it, the coordinates come from your device; the
  name over them comes from the server, and if nothing can name them the field
  simply says "Current location" rather than guessing at a street.
- **Saved places** — Home, Work, or anything else you have saved.
- **Search for a place** — type at least two characters.

If you have not saved anything yet, the picker says so and offers a link to add
one: `restart-module-05/restart-m05-web-no-saved-addresses.png`.

## 4. Choose your destination

`restart-module-05/restart-m05-web-place-search.png`

Saved places and search. Current location is deliberately **not** offered for a
destination — a journey to where you already are is not a journey.

Suggestions appear about a third of a second after you stop typing, not on every
keystroke. You can drive the whole list from the keyboard: ↓ and ↑ to move,
Enter to take one, Escape to close without choosing.

## 5. Review

`restart-module-05/restart-m05-web-planner-ready.png`

Both fields show the place and its full address. **Swap** exchanges them. The ✕
beside a field clears it.

If you pick the same place twice, the planner says so and the button stays
inactive: `restart-module-05/restart-m05-web-same-location.png`.

## 6. Tap Plan journey

`restart-module-05/restart-m05-trip-created.png`

The journey is saved on the server and you are taken to it. Tapping twice does
not create two journeys.

The screen says **"Route not calculated yet"**, and it means it. Working out the
route, the distance, the travel time and the restaurants along the way is the
next thing being built — nothing on this screen estimates any of them.

## 7. Find it again

`restart-module-05/restart-m05-web-trips-tab.png`

**Trips** lists your journeys. Home shows the one in progress. Reloading the
journey's own page works, because the page loads it from the server.

---

## Saved places

`restart-module-05/restart-m05-web-saved-places-list.png`
`restart-module-05/restart-m05-web-saved-places-form.png`

**Profile → Manage saved places.** Add one by searching for the place, picking
it, and adding the flat or landmark if you want. Because an address is created
from a place you picked, it always has a location the planner can use.

Editing an address and changing your default are **not yet in the browser** —
they are on Android and iOS. That gap is recorded as MF-26.

---

## What this guide does not cover

- **Android and iOS.** The same planner exists in the mobile app and its tests
  pass, but no screenshot of it exists from this environment: there is no
  Android SDK, emulator or Apple hardware here. Pretending otherwise is exactly
  what these restart modules exist to stop.
- **Your current location on the review site.** `techpio.tech:8080` is plain
  http, and browsers only share a location over https. Saved places and search
  work there; "Use my current location" will tell you why it cannot.
- **Real place search.** Until a Places API key is supplied, search covers
  twelve real, well-known places at their real published coordinates — enough to
  drive the whole flow, and obviously not a gazetteer of India.
