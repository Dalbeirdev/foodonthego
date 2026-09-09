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

**Not in this build, and the app says so in those words.**

**Proceed to payment** is present and enabled when the server says your order is
ready. Tapping it places a payment target — the order the payment will attach
to — and opens the payment screen, which reports:

> **Payment isn't enabled yet.** No card, UPI, wallet or net banking provider is
> configured for this deployment.

That is the literal state of this deployment rather than a placeholder. The
payment code is built and tested: an order can have a payment opened against it,
a provider's result is verified by the server, and a verified capture creates
the order. **No payment provider credentials exist for this project**, so none of
it has ever run against a live provider, and the app refuses to pretend
otherwise rather than showing a checkout sheet that cannot work.

Nothing is charged. The row created when you reach this screen is not an order:
it has no order number, and it does not appear in your Orders tab.

---

## 13. After paying — your order number and pickup code

This is what a customer sees once a payment goes through. It is built and
tested; you cannot reach it in this build because no payment can be captured
without a provider.

**The moment the payment succeeds, you leave the payment screen.** There is no
way back to it — no *Pay Again*, no *Back to Payment*, at any point. That is
deliberate: once your money has left, a button offering to pay again is a button
that charges you twice for one meal.

### While your order is being written

You may see a brief wait that says your payment is confirmed and your order is
being prepared. If something goes wrong behind the scenes, you still see that
same message — never a payment failure — because your money is safe and the
order will be created either way. If the app cannot reach the server at all, it
says exactly that and offers to check again. It never guesses that your payment
failed, because it has no way of knowing.

### Your order number

Something like **FOTG-260917-94FBX0ZS1M** — a real draw from the generator this
build ships, not a made-up example.

This is your reference. Read it out, quote it in a message, screenshot it — it
is safe to share. **It does not collect your food.** Knowing an order number is
never enough for anyone, including you, to be handed a meal.

### Your pickup code

Eight characters, shown on the confirmation screen along with a QR code.

**This is the one you keep to yourself.** It is what proves the order is yours
at the counter. A few things worth knowing about it:

- It is never stored in readable form anywhere — not in the app, not on the
  server, not in a backup. It is worked out fresh each time you ask for it.
- It belongs to that one order at that one restaurant. It will not work for
  another order, or at another restaurant, even a different branch.
- A screen reader reads it out character by character, because "7K4M9PQ2" said
  as a word is no use to anyone standing at a counter.

**Scanning is not built yet.** The QR code is generated and shown; nothing reads
it. Collecting food with it belongs to a later module.

### Your Orders tab

Orders you have paid for appear here, newest first, with the restaurant, the
total and the order number. A basket you started paying for and did not finish
does not appear — it is not an order.

---

## 14. Tracking your order

Once an order exists, the **Orders** tab lists it. Active orders come first,
sorted by the one you have to collect soonest — not the one you bought last.

Tap **Track order** on a card.

### What you see

**Your current status, in the largest type on the screen.** That is the thing
you opened the screen to find out. Your order number is there too, smaller,
because it is a reference rather than an answer.

**A timeline**, showing what has happened and what has not:

> ✓ Order placed — 4:01 PM
> ✓ Restaurant accepted your order — 4:03 PM
> ● Your food is being prepared — 4:05 PM
> ○ Ready for pickup
> ○ Picked up

A step with no time next to it has not happened yet. **The app never guesses a
time for a step that has not happened** — if there is no time, there is no time.

Below that: your requested pickup window, the restaurant, what you ordered at
the prices you paid, and what the payment came to.

### If your order is refused or cancelled

The timeline stops where the order stopped. You will not see "Cooking" and
"Ready" sitting ahead of a refused order as though they are still coming,
because they are not.

If the restaurant gave a reason that is safe to pass on, you will see it. If
they did not, you will see the status and nothing invented to fill the gap.

### Refreshing

Pull down, or use the refresh button in the top corner. The screen also checks
by itself every twenty seconds while you have it open — and stops when you leave
the app, and stops once your order is finished.

**It does not say "Live", and that is deliberate.** Live updates arrive in a
later release. Until then the screen tells you when it last checked rather than
implying it is watching continuously.

### If you lose signal

You keep the last status the app managed to load, with a note saying you are
offline and that it may have changed. Nothing is hidden from you, and nothing
stale is presented as current.

### Your pickup code

Available from the moment your order exists. The tracking screen reminds you to
use it when your order is ready.

### What this release cannot do

- **Nobody can move your order yet.** The restaurant screens that accept and
  prepare orders are a later release, so in practice an order stays at "Order
  placed".
- **No live estimate.** The pickup window is the time you asked for, not a
  prediction. The screen says so.
- **No notifications.** You will not be told when something changes; you have to
  look.
- **No cancelling.** There is no cancel button, because the rules for
  cancelling have not been decided.

---

## 15. Alerts and the rest

The **Alerts** tab exists in the navigation and is empty. It belongs to a module
that has not been built, and the app says so rather than showing a spinner that
never resolves.

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
| Order confirmation | Yes — built, unreachable without a provider | n/a |
| Order number | Yes | n/a |
| Pickup code and QR | Yes — minted and shown; scanning not built | n/a |
| Orders tab | Yes | Yes (module-02, empty state) |
| Order tracking | Yes | n/a — needs an order past PLACED |
| Status timeline | Yes | n/a |
| Refresh and offline | Yes | n/a |
