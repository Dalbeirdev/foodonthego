# 31 — Customer mobile app: a guide for reviewers

How to use the FoodOnTheGo customer app, screen by screen, as it stands at the
end of Module 14.

Every screenshot referenced here was produced by rendering the **real app**
against a **real server**. Where a step has no screenshot, this guide says so
rather than pointing at a picture of something else.

Before you start, read section C of
[30-client-review-package.md](30-client-review-package.md): with nothing
deployed, the app needs a backend you can run.

---

## 1. Signing in

There is **no password**. Sign-in is a phone number and a one-time code.

1. Open the app. Tap **Continue with mobile number**.
2. Enter a number. In development, `+91 99999 00401` and any
   `+91 999990xxxx` number work.
3. Tap **Send code**. In development the code is written to the server's
   `backend/storage/logs/otp-development.log` — there is deliberately no
   endpoint that hands it back over HTTP.
4. Enter the six digits.
5. First time only: enter a first and last name and tap **Create account**.

Screenshots: [`evidence/module-03/`](evidence/module-03/) — 22 states including
the code entry, resend cooldown, wrong code, expired code and rate limiting.

**What to look for.** The app never tells you whether a number is registered
before you have proved you hold it, the resend has a visible cooldown, and a
wrong code says how many attempts remain without saying anything about the
account.

---

## 2. Your profile and saved addresses

Profile tab → **Edit profile** to change your name or email; **Saved addresses**
to add home, work or any other place you set off from often.

Screenshots: [`evidence/module-04/`](evidence/module-04/) — 24 states.

---

## 3. Planning a journey

Trips tab → **Plan a journey**.

1. **Choose your starting point** — use your current location, a saved address,
   or search for a place.
2. **Choose your destination** — the same three ways.
3. Tap **Create journey**.

Screenshots: [`evidence/module-05/`](evidence/module-05/) — 28 states including
every location-permission outcome, a device that never answers, and an
approximate fix being labelled as approximate.

---

## 4. The route

On the journey, tap **Calculate route**.

The map draws the route with both ends marked, and the distance and travel time
appear beneath it.

Screenshots: [`evidence/module-06/`](evidence/module-06/) — 20 states.

**Worth knowing.** Route calculation is a billed call to a routing provider. The
app will not silently re-ask for a route a journey already has.

---

## 5. Finding food on the route

**Find food on this route** opens discovery.

Restaurants are shown **because they are on your way**, not because they are
nearby in a straight line: the engine works in a corridor around the route and
ranks by how far along it a place is and how much of a detour it costs.

Search, filter by cuisine, diet, price and rating, and sort. Toggle between the
list and the map.

Screenshots: [`evidence/module-07/`](evidence/module-07/) (21) and
[`evidence/module-08/`](evidence/module-08/) (28).

---

## 6. A restaurant

Tap a card to open it: photographs, cuisine, rating, opening hours with today
highlighted, facilities, and how far off your route it is.

Screenshots: [`evidence/module-09/`](evidence/module-09/) — 25 states.

---

## 7. The menu

**View menu** opens it: categories down the page, search across the whole menu,
and dietary markers on every dish.

Screenshots: [`evidence/module-10/`](evidence/module-10/) — 30 states, including
a 500-item menu.

---

## 8. Choosing a dish

Tap a dish to open it.

- **Choose a size.** The size *is* the price, not a surcharge on top of one.
- **Answer the required questions** — spice level, for instance. The button
  will not price the dish until you have.
- **Add extras** if you want them. **Nothing that costs money is ever ticked
  for you.**
- Set a quantity and add a note for the kitchen.

The button at the foot shows what you will be charged, and it is the **server's**
figure rather than the app's arithmetic.

Screenshots: [`evidence/module-11/`](evidence/module-11/) — 36 states, including
a sold-out size, a full extras group, a price that changed while you were
looking, and a cart that already holds another restaurant's food.

---

## 9. Your cart

Cart icon, or **Cart** from the menu screen.

Every line shows the dish, its configuration ("Large · Mild"), your note, the
quantity stepper and the line total. The subtotal is at the foot.

- The **minus stops at one** rather than quietly removing a line.
- **Emptying the cart asks first.**
- Prices are re-checked against the kitchen when you open the cart, and anything
  that has changed is shown before you go further.

Screenshots: [`evidence/module-14/state-07-cart.png`](evidence/module-14/state-07-cart.png)
and [`state-08-cart-foot.png`](evidence/module-14/state-08-cart-foot.png).

---

## 10. When you will collect

**Choose a pickup time** from the cart.

You get a row of ten-minute windows the kitchen can actually meet, and — the
part worth reading — **how each one was worked out**:

> You're about 66 minutes away · You arrive around 9:17 pm · The kitchen needs
> about 20 minutes · Plus 5 minutes to bag it up · Ready from 8:36 pm

Times are the **restaurant's** clock, and the card says which zone that is. A
phone set to another timezone still shows the time written on the counter's
wall.

Tap a window, then **Check my order**. The server answers with either "Your
order is ready to go" or the specific things in the way, in its own words.

Screenshots: [`evidence/module-14/state-09-pickup-times.png`](evidence/module-14/state-09-pickup-times.png)
and [`state-10-pickup-explanation.png`](evidence/module-14/state-10-pickup-explanation.png).

**Worth knowing.** The estimate assumes you set off now. It is not a live ETA —
that engine does not exist yet, and this is the largest approximation in the
product.

---

## 11. Checkout

**Continue to checkout** appears once the server has said the order is ready,
and not before.

The screen shows the restaurant, the pickup window, the journey, every line of
the order, and the money:

| | |
| --- | --- |
| Items subtotal | ₹658 |
| | *No additional charges are currently configured.* |
| **Total to pay** | **₹658** |

That sentence is about **configuration**, not about tax law. When commercial
rules are switched on, the same screen shows them as real rows — see
[`state-03-configured-charges.png`](evidence/module-14/state-03-configured-charges.png),
where a 5% tax rate and a ₹15 packaging fee produce ₹32.90, ₹15 and a total of
₹705.90.

**Edit cart** and **Change pickup time** go back. Both invalidate the price, and
the screen will tell you it needs refreshing rather than showing you a stale one.

The checkout is held for **ten minutes**; the hold time is printed at the foot.
After that, **Refresh checkout** fetches a current price.

Screenshots: [`evidence/module-14/`](evidence/module-14/) states 01–06.

---

## 12. Paying

**You cannot.** Payment is Module 15.

**Proceed to payment** is present and enabled when the server says your order is
ready. Tapping it asks the server one last time and then tells you plainly:

> **Payment arrives in the next release.** Your order is checked and ready.
> Card, UPI, wallet and net banking aren't switched on yet.

Nothing is charged, no order is created, and no payment record exists. The
database has no `orders` or `payments` table at all.

---

## 13. Orders, alerts and the rest

The **Orders** and **Alerts** tabs exist in the navigation and are empty. They
belong to modules that have not been built, and the app says so rather than
showing a spinner that never resolves.

---

## Coverage of this guide

| Step | Documented | Screenshots |
| --- | --- | --- |
| Sign in | Yes | Yes (module-03) |
| Profile and addresses | Yes | Yes (module-04) |
| Plan a journey | Yes | Yes (module-05) |
| Route | Yes | Yes (module-06) |
| Restaurant discovery | Yes | Yes (module-07) |
| Search, filters, sort | Yes | Yes (module-08) |
| Restaurant detail | Yes | Yes (module-09) |
| Menu | Yes | Yes (module-10) |
| Dish customization | Yes | Yes (module-11) |
| Cart | Yes | Yes (module-14) |
| Pickup time | Yes | Yes (module-14) |
| Checkout | Yes | Yes (module-14) |
| Payment | Yes — as unavailable | n/a |
