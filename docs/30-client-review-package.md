# 30 — Client review package (end of Module 17)

Everything a reviewer needs to look at the product as it stands after Module 17,
and an honest account of what they will not be able to do.

Written to be read by somebody who has not been following the build. Where a
thing is missing, this document says it is missing and why, rather than
describing something that would look better.

**Nothing in this document is a production credential.** No API keys, no
database passwords, no Razorpay secrets, no signing certificates, no customer
data. The two accounts named below are development personas that exist only in a
local development database.

---

## A — What Modules 14 to 17 deliver

A customer can plan a journey, find a restaurant on their route, browse its
menu, configure a dish, put it in a cart, choose a pickup window, and reach a
**checkout screen showing an authoritative payable amount**.

Behind that screen, the whole path from a payment to a collectable order is now
built and tested: a payment can be opened against an order, a provider's result
is verified by the server rather than believed from the app, and **a verified
capture creates exactly one order** with a number the customer can read out and
a pickup credential that is never stored in readable form.

**Where it stops, and why.**

- **No payment provider credentials exist for this project**, so no payment has
  ever been taken and no order has ever been created from a real capture. The
  app says exactly that on the payment screen rather than opening a checkout
  sheet that cannot work.
- **Nothing scans a pickup code.** It is minted, shown and verifiable
  server-side; the counter flow that would redeem it is a later module.
- **An order can now move through its whole lifecycle** — accepted, cooking,
  ready, picked up — and the customer app shows where it stands, when each step
  happened, and what happens next. Every transition is validated, locked,
  audited and tenant-checked.
- **But nothing a restaurant can press exists yet.** The service is built and
  tested; the screens that will call it are a later module. In a production
  deployment today, every order would sit at PLACED and the app would
  faithfully report that (KI-028).

---

## B — Web review URLs

| Surface | URL | State |
| --- | --- | --- |
| Customer app (web) | — | `EXTERNAL REVIEW URL = PENDING` |
| Restaurant dashboard | — | `EXTERNAL REVIEW URL = PENDING` |
| Admin panel | — | `EXTERNAL REVIEW URL = PENDING` |
| API | — | `EXTERNAL REVIEW URL = PENDING` |

**`EXTERNAL REVIEW URL = PENDING — NOTHING IS DEPLOYED`.**

There is no hosting environment for this project yet. Everything above runs on a
developer machine at `localhost`, and a localhost address is not a review URL:
it would resolve to the reviewer's own computer, where nothing is listening.

What exists instead: the deployment topology is designed and written down in
[10-deployment.md](10-deployment.md), and the environment contract that a
staging deployment must satisfy is in [04-environments.md](04-environments.md).
Standing one up is a decision with a cost attached and has not been approved.

---

## C — Android review build

**Available.** Built by CI on the same commit the test suites ran against, and
downloadable from the workflow run.

| | |
| --- | --- |
| Artefact | `android-review-build-<commit>.zip` |
| Contains | `app-release.apk`, `app-release.aab`, `BUILD-INFO.txt` |
| Where | the **Mobile — Android review build** job of a CI run on this branch |
| Retention | 30 days on `main`; 1 day on a pull request, where the artefact exists so the emulator job can install it |
| Version | `1.0.0+1` |
| Application id | `com.foodonthego.foodonthego` |
| Environment | `FOTG_ENV=staging` — **not** a production build |
| Signing | Android **debug** key |

`BUILD-INFO.txt` travels inside the zip and records the version, the branch
head commit, the workflow run URL, the Flutter version, the API address compiled
in, and the SHA-256 of both binaries.

The digests for the Module 17 build, taken from the CI job that produced it
rather than retyped from anywhere:

| Binary | SHA-256 | Commit |
| --- | --- | --- |
| `app-release.apk` | `7f2e57b41397da903df21c126641786a9739ce026cd24bc95a8c6d7d2dede5ea` | `b688c9b` |
| `app-release.aab` | `42fe4429386dea9ddcb93f0f53dffa1fef60509d9eafc32aa85479572bd58036` | `b688c9b` |

A digest is only meaningful next to the commit it was built from, so both are
given. Commits after `b688c9b` on this branch change documentation and CI
tooling only — no Dart, no Kotlin, no Gradle configuration — so the binary a
reviewer downloads from a later run is the same application, but its digest
will differ, because a Flutter build is not byte-reproducible. Trust the
`BUILD-INFO.txt` inside the zip you actually downloaded over this table.

### It has been installed and launched

Not "an APK was produced" — the artefact itself is downloaded by the Android
emulator job, installed on a Pixel 6 running Android 14, and started. On the run
for `549be29`:

```
Performing Streamed Install
Success
Starting: Intent { cmp=com.foodonthego.foodonthego/.MainActivity }
2780                                    <- still running twenty seconds later
    versionCode=1 minSdk=24 targetSdk=36
    versionName=1.0.0
```

and nothing belonging to this package in the crash buffer. The check greps for
this package rather than asserting an empty buffer: a headless emulator crashes
something of Google's often enough, and a check that fails on that is a check
somebody reruns until it passes.

### What the signing means

`android/app/build.gradle.kts` still carries Flutter's placeholder release
config, which signs release builds with the debug key. So:

- The **APK can be sideloaded** onto a review handset. That is what it is for.
- The **AAB cannot be uploaded to Google Play.** It is included because a build
  that is never attempted is a build that breaks later, not because it is
  publishable.

`ANDROID PLAY-READY BUILD = PENDING — NO UPLOAD KEYSTORE CONFIGURED`. An upload
keystore is a credential the client owns and must create; inventing one here
would put the identity of the published app in a repository.

### Installing it

1. Download the artefact zip from the CI run and unzip it.
2. On the handset, allow installation from the source you will use (Settings →
   Apps → Special access → Install unknown apps).
3. `adb install app-release.apk`, or copy the APK across and open it.
4. Android may warn that the app is from an unknown developer. It is: it is
   signed with a debug key, which is exactly what that warning is for.

### What it can do once installed

**Very little on its own, and this matters.** The app talks to a backend, and
there is no deployed backend. With no `FOTG_REVIEW_API_BASE_URL` set, the build
points at `http://10.0.2.2:8000` — an Android emulator's alias for the host
machine — so it can reach a developer running the API locally and nothing else.

On a physical handset with no reachable API, the reviewer will see the app
launch, the design system, navigation, and the offline and error states. They
will not be able to sign in, because sign-in is a real server round trip.

To make the build useful, set the `FOTG_REVIEW_API_BASE_URL` repository variable
to a reachable API address and re-run CI. The manifest records which address the
binary was built with, so a reviewer never has to guess.

---

## D — iOS review build

`iOS REVIEW BUILD = PENDING — APPLE SIGNING/TESTFLIGHT ENVIRONMENT UNAVAILABLE`

There is no Apple Developer account, no provisioning profile, no distribution
certificate and no App Store Connect access configured for this project. An iOS
build that a reviewer can install requires all four.

An iOS build **is** compiled on every CI run — `flutter build ios --no-codesign`
on a macOS runner — so the iOS target is known to build. That is a compile, not
an installable app, and it is not an IPA.

**An iOS build is never an APK.** An `.apk` is an Android package; iOS uses
`.ipa`. No `.ipa` exists and none has been fabricated.

**What iOS *is* verified to do**, as of Module 17: the full on-device suite runs
on an iPhone simulator on every pull request — the same 29 tests as Android,
driving a real Laravel backend over HTTP — and passes. That is a genuine runtime
result on Apple's own simulator runtime and it is how the Module 17 tracking
defect was found. It is still not an installable build, and this section stays
PENDING until there is an Apple signing environment.

---

## E — Responsive web review on a mobile browser

`PENDING — NOTHING IS DEPLOYED` (see section B).

The customer app is built for web as part of the screenshot process and renders
correctly at 393 × 852; the restaurant and admin shells are screenshotted at
390 × 844 as well as 1440 × 900 (section H). What is missing is a URL a reviewer
can open on their own phone, and that is a deployment, not a build.

---

## F — Roles, access, and login credentials

### The honest position

The platform defines **seven roles** ([07-security.md](07-security.md)). After
fourteen modules, **one of them has a working login flow**.

| Role | Login flow exists | API surface exists | Credentials available |
| --- | --- | --- | --- |
| Customer | **Yes** — phone + OTP | Yes, 35 endpoints | Yes, below |
| Restaurant owner | **No** | Tenant-scoped, minimal (Module 14T) | **None — nothing to log in with** |
| Restaurant manager | **No** | Tenant-scoped, minimal | None |
| Restaurant staff | **No** | Tenant-scoped, minimal | None |
| Platform admin | **No** | Grant-scoped, minimal | None |
| Support agent | **No** | Grant-scoped, minimal | None |
| Super admin | **No** | Grant-scoped, minimal | None |

Module 14T changed one half of this and not the other. The six operator roles now
have a **tenant boundary that is built and tested** — 22 cross-tenant tests over
HTTP, seven negative controls — behind a deliberately minimal set of routes that
exists so the isolation can be tested at all, not as an operator dashboard.

**What still does not exist is a way for any of them to sign in.** No flow mints a
token for a restaurant or platform account, so there are no credentials to hand
over and none have been invented. The boundary was built first on purpose: login
arrives behind something already tested rather than alongside something new.

The two web shells still contain no login screen, no password field and no token
handling anywhere in their source.

**No credentials have been invented for the six roles that cannot log in.** A
username and password for a surface with no authentication would be a fiction
that reads as progress.

### The restaurant and admin web shells

They open without a login because there is nothing to log in to. Each says so on
its own front page: *"Nothing on this screen is live data. No orders, menu items
or earnings exist yet — there are no such tables in the database. Every link in
the sidebar marked with a dot is navigation scaffolding."*

They are real: real design system, real navigation architecture, a real API
connectivity indicator, and — in the admin panel — a **System Health** page that
genuinely queries the API. They are not an operator's dashboard, and the
document that says otherwise does not exist.

### Customer sign-in, for a reviewer with a running backend

Sign-in is **phone number plus a one-time code**. There is no password.

In development the OTP is written to `backend/storage/logs/otp-development.log`
on the **server**, and there is deliberately no endpoint that returns it — that
absence is what makes the development provider unusable in production, and it
will not be loosened to make a review convenient.

| | |
| --- | --- |
| Test persona | `+91 99999 00401` (any `+91 999990xxxx` number works) |
| Code | read from the server's `otp-development.log` |
| Password | none — the product has no customer password |

These numbers exist only in a local development database and carry no authority
anywhere else. **Do not create accounts in a production environment.** There is
no production environment, and if one is created later these numbers must not be
seeded into it.

### Login verification

The customer flow was verified end to end during this module's screenshot run
and on two device runs (Android emulator, iOS simulator): sign in → land on the
customer surface → reach the checkout → the server accepts the session. Recorded
in [15-test-evidence.md](15-test-evidence.md).

For the other six roles there is **no login to verify**, so no PASS is claimed.

---

## G — Feature completion status

Read this as *what a customer can do*, not *what a screen exists for*.

| Capability | Module | Status |
| --- | --- | --- |
| Sign in with phone and OTP | 03 | **Complete** |
| Profile and saved addresses | 04 | **Complete** |
| Plan a journey with real places | 05 | **Complete** |
| Route calculation and map | 06 | **Complete** |
| Find restaurants along the route | 07 | **Complete** |
| Search, filter and sort them | 08 | **Complete** |
| Restaurant detail page | 09 | **Complete** |
| Browse a menu | 10 | **Complete** |
| Configure a dish and add to cart | 11 | **Complete** |
| Manage the cart, revalidate prices | 12 | **Complete** |
| Choose a pickup window | 13 | **Complete** |
| Checkout with an authoritative total | 14 | **Complete** |
| Take a payment | 15 | **Built, never executed** — no provider credentials exist |
| Verify a payment server-side | 15 | **Complete** — signature, binding, amount; three paths, one implementation |
| Create an order from a capture | 16 | **Complete** — at most one order per captured payment, guaranteed by a unique index |
| Order number | 16 | **Complete** — CSPRNG, authorises nothing |
| Pickup code and QR token | 16 | **Complete** — derived, never stored in readable form |
| See your orders and confirmation | 16 | **Complete** |
| Order tracking and status timeline | 17 | **Complete** |
| Order state machine and transition validation | 17 | **Complete** — illegal and terminal transitions refused |
| Immutable status history and audit trail | 17 | **Complete** |
| Manual refresh | 17 | **Complete** |
| Temporary tracking refresh (polling) | 17 | **Complete** — 20s, configurable; **not realtime** |
| **Restaurant status controls** | later | **Not started** — no screen can move an order (KI-028) |
| **Collect food with a pickup code** | later | **Not started** — nothing scans or redeems one |
| **Realtime updates (WebSocket)** | 19 | **Not started** — and not claimed anywhere in the app |
| **Live ETA** | 18 | **Not started** — the app says "Not a live estimate" |
| **Push notifications** | 20 | **Not started** |
| **Customer cancellation** | later | **Not started** — no cancellation policy agreed (KI-030) |
| **Refunds** | later | **Not started** — nothing in the platform can refund |
| **Restaurant operations** | later | **Not started** — shell only |
| **Admin operations** | later | **Not started** — shell only |
| Support, finance, rider surfaces | later | **Not started** — nothing at all |

`orders`, `order_items`, `order_item_modifiers`, `payments`, `payment_events`
and `outbox_events` all exist as of Modules 15 and 16. There is no
`pickup_codes` table and there will not be one: a pickup code is derived from
the order rather than stored, so there is nothing for such a table to hold.

---

## H — Screenshots

Sixteen, in [evidence/module-14/](evidence/module-14/), indexed one by one in
[evidence/module-14/INDEX.md](evidence/module-14/INDEX.md). All produced by
rendering the real app or the real web shells against a real Laravel server —
nothing is a mock-up.

### Customer checkout (Flutter, 393 × 852)

| File | What it shows |
| --- | --- |
| `state-01-checkout.png` | the whole screen: restaurant, pickup window, journey, order, money |
| `state-02-no-charges-and-payment-notice.png` | no configured charges said in words; edit controls; the CTA; the payment notice; the hold time |
| `state-03-configured-charges.png` | the same order with tax and a packaging fee configured — ₹32.90 and ₹15, and the "no charges" sentence gone |
| `state-04-expired-quote.png` | a quote past its hold, asking to be refreshed |
| `state-05-blocked.png` | a sold-out line refused in the server's words, with no payment notice |
| `state-06-dark.png` | the same checkout on a phone set to dark |
| `state-07-cart.png` · `state-08-cart-foot.png` | the cart (Module 12) |
| `state-09-pickup-times.png` · `state-10-pickup-explanation.png` | the pickup windows, and how each was worked out (Module 13) |

States 02 and 03 are each other's control: the same screen and the same code
path, with only the restaurant's commercial configuration changed between them.

### Order tracking (Flutter, Module 17)

Eight more, in [evidence/module-17/screenshots/](evidence/module-17/screenshots/),
with a README beside them saying what each one evidences: `tracking-placed`,
`tracking-cooking`, `tracking-ready`, `tracking-picked-up`, `tracking-rejected`,
`tracking-status-unknown`, plus the same order at 320 dp and at 2× text scale.

Two are worth opening first. `tracking-status-unknown.png` is a cached order
rendered a day after it was read: the status and the timeline are **gone**,
replaced by a plain statement that the app cannot tell you where the order is,
while the order number, restaurant, items, amount paid and requested pickup all
stay. A screen still saying "Your food is being prepared" a day later answers
the customer's question confidently and wrongly.

And `tracking-rejected.png`. A refused order shows
the path **truncated** — Cooking and Ready are not left on screen pretending
still to be coming — with the restaurant's customer-safe reason above it and no
pickup credential. That is the behaviour that is easiest to get wrong and
hardest to see in a test name.

These were captured differently from the sixteen above: not a web build, but the
real widget tree under `flutter test`, with Roboto and MaterialIcons loaded out
of the Flutter SDK. So there is no stand-in font here — the type and icons are
the ones a real build ships. There is also no real server: the data is a fixture
chosen to put each timeline state on screen, and the same screen filled by a
real Laravel backend is in
[evidence/module-17/live-api-run.txt](evidence/module-17/live-api-run.txt).
One blemish is left visible rather than cropped, and the README explains it.

### Web shells (1440 × 900 and 390 × 844)

`restaurant-1440` · `restaurant-390` · `restaurant-dark` · `admin-1440` ·
`admin-390` · `admin-dark`.

### What is in the images, and what is not

Nothing in them contains an API key, a password, a payment card, a production
hostname or a real person's data. The customer is a development persona; the
restaurant is named `[TEST] Highway Spice Kitchen` precisely so that a test
fixture can never be mistaken for a real business.

Two things a careful reader will notice and should not be surprised by:

- **A small flask button floats over the bottom-left corner.** That is the
  development harness, which exists in non-production builds only. It is
  compiled out of a production build. It is in the pictures because it is in the
  binary a reviewer would install.
- **The screenshots were rendered by a web build with a stand-in font
  temporarily bundled.** Flutter web fetches its default font from a CDN this
  build environment blocks; without a substitute the app renders with no glyphs
  at all. The substitute was reverted immediately and the committed app is
  unchanged. Layout, colour, spacing, icons, navigation and every figure in the
  images are the product's own.

---

## I — How to review it, step by step

### With a backend you can run

1. Start MySQL 8 and Redis 7.
2. `cd backend && composer install && php artisan migrate --seed`
3. `php artisan db:seed --class=DiscoveryTestRestaurantSeeder --force`
4. `php artisan db:seed --class=MenuTestDataSeeder --force`
5. `php artisan serve --host=0.0.0.0 --port=8000`
6. Install the review APK (section C) on a handset on the same network, built
   with `FOTG_REVIEW_API_BASE_URL` pointing at that machine.
7. In the app: sign in with `+91 99999 00401`, reading the code from
   `backend/storage/logs/otp-development.log`.
8. Plan a journey — Green Park to Jaipur International Airport.
9. Calculate the route; open **Find food on this route**.
10. Open `[TEST] Highway Spice Kitchen` → **View menu** → **Paneer Tikka**.
11. Choose *Large*, choose a spice level, add to cart.
12. Open the cart; **Choose a pickup time**; pick a window; **Check my order**.
13. **Continue to checkout.**
14. Read the total. Tap **Proceed to payment** — the server re-checks and the
    app tells you payment arrives in the next release.

### Without a backend

Read section H. The screenshots show every state of the checkout screen, and
[15-test-evidence.md](15-test-evidence.md) records what was run and what passed.

### The guides

- [31-customer-mobile-guide.md](31-customer-mobile-guide.md) — the customer app
  screen by screen, with screenshots for every step.
- [32-restaurant-and-admin-web-guide.md](32-restaurant-and-admin-web-guide.md) —
  what the two web applications are, and what they are not.
- [evidence/module-14/INDEX.md](evidence/module-14/INDEX.md) — every screenshot,
  what it evidences, and the screenshot QA result.

---

## J — Commercial policy

**`COMMERCIAL POLICY PRODUCTION READINESS = PENDING CLIENT DECISION`**

Today, for the seeded restaurant:

```
Items subtotal:                ₹658
Payable amount:                ₹658
Configured additional charges: none
```

This means **no additional charges are currently configured**. It does **not**
mean no tax is legally applicable, and nothing in this build makes that claim.

The mechanism exists and is tested with non-zero values — section H's
`state-03-configured-charges.png` is the same order with a 5% tax rate and a ₹15
packaging fee switched on, priced correctly at ₹705.90. What is missing is the
business decision about what the rates should be.

Before commercial launch somebody must decide, in writing:

| Rule | Where it would be configured | Decided? |
| --- | --- | --- |
| GST / tax rate | `restaurants.tax_rate_bps`, or the platform default | **No** |
| Packaging fee | `restaurants.packaging_fee_minor` | **No** |
| Platform / service fee | `foodonthego.cart.platform_fee_minor` | **No** |
| Convenience fee | not implemented | **No** |
| Commission to restaurants | not implemented | **No** |
| Discounts and promotions | not implemented | **No** |
| Rounding and invoice presentation | integer minor units, half-up on tax | partially |

**None of these has been invented.** A charge nobody has configured is absent
from the response and absent from the screen, and the difference between "not
configured" and "configured as zero" is enforced in code and in tests.

---

## K — Known limitations

1. **No restaurant can move an order.** The transition service is built,
   locked, audited and tested, but no screen calls it — so a production
   deployment would leave every order at PLACED (KI-028).
2. **No payment has ever been taken.** The integration is written and tested
   against a deterministic double; no provider credentials exist, so it has
   never spoken to Razorpay (KI-022, KI-026).
2. **No order has ever been created from a real capture**, for the same reason.
   Every path downstream of a capture is proven against the fake gateway.
3. **Nothing collects food.** No redemption endpoint, no scanner — and so no
   attempt limit on guessing a pickup code, which is recorded now rather than
   discovered later (KI-024).
4. **An order cannot move past PLACED** (KI-027).
5. **Nothing deployed.** No review URL for any surface.
4. **Six of seven roles have no login and no API.**
5. **The AAB cannot go to Play** — debug-signed, no upload keystore.
6. **No iOS installable build** — no Apple signing environment.
7. **Commercial rules are unset** — see section J.
8. **The pickup time is not a live ETA.** Travel comes from the planned route on
   the assumption the customer sets off now. This is the largest approximation
   in the product and is stated wherever it is relied on.
9. **No inventory is reserved.** Preparing a checkout holds nothing.
10. **The quote holds for ten minutes** and then must be refreshed.
11. **Development personas are in non-production binaries**, by design.
12. Full list, with severities and history:
    [13-known-issues.md](13-known-issues.md).

---

## L — Test evidence

| | |
| --- | --- |
| Backend | **1,294 tests**, Pint clean |
| Flutter | **984 tests**, `analyze --fatal-infos` clean, `format` clean |
| Web | typecheck, tests and both builds clean |
| Android device run | **29 integration tests on an emulator** |
| iOS device run | the same suite on a simulator |
| Review APK | downloaded, installed and launched on the emulator; alive, correct version, clean crash buffer |

The device runs install the shipping app on a real emulator and simulator and
drive it against a real Laravel server writing to a real MySQL database. Nothing
in them is stubbed. Full detail, including the negative controls run against
this module's own tests, in [15-test-evidence.md](15-test-evidence.md).

---

## M — What must happen before this is a product

In the order it matters:

1. **Decide the commercial rules** (section J). Everything downstream of money
   waits on this.
2. **Stand up a staging environment** so a reviewer can open a URL and a review
   build has something to talk to.
3. **Razorpay test credentials and a public HTTPS webhook endpoint**, both
   owned by the client. Until these exist, no payment can be taken and no order
   can be created from one — the code is written and waiting on configuration.
4. **A restaurant order screen.** Everything else in the fulfilment chain now
   exists; this is the missing link that makes the platform usable end to end.
5. **Pickup verification** — scanning, redemption, and the attempt limit that
   must come with it.
5. **A restaurant operations surface** — the kitchen cannot see an order today,
   and an order cannot move past PLACED.
6. **An upload keystore and an Apple Developer account**, both owned by the
   client, before either store can be reached.
7. **The live ETA engine**, replacing the planned-route approximation.
