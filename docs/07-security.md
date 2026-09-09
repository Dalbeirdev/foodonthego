# 07 — Security

## Secrets

No credential is ever committed. `backend/.env` and `web/apps/*/.env*` (except `.env.example`) are
gitignored. `.env.example` contains placeholders only.

If a secret is ever committed: rotate it first, then rewrite history. Removing it from `HEAD` does
nothing — it is in the clone every developer already has.

### Two Maps Platform keys, restricted differently

The routing key and the Maps SDK key are separate credentials on purpose, because
one of them has to ship inside the app and the other must never.

| Key | Where it lives | Restrictions |
| --- | --- | --- |
| Routes API (routing) | Backend environment only (`GOOGLE_ROUTES_API_KEY`) | Server/IP where the platform supports it, plus API scope: Routes API alone |
| Maps SDK (drawing) | Inside the app binary (`--dart-define=FOTG_MAPS_API_KEY`) | Android package name **and** signing certificate; iOS bundle identifier; API scope: Maps SDKs alone |

A key inside a mobile binary is extractable — that is a property of the platform,
not a mistake — so the Maps key is restricted until it is worth nothing to
whoever extracts it: it cannot calculate a route, cannot search a place and
cannot be used from another application. The app holds **no** routing key of any
kind, and no unrestricted production key is committed anywhere.

Neither key is ever logged. The routing provider's failure path records a failure
kind and the trip uuid; it records neither the request URL nor the key, and a
test asserts that `AIza` never appears in the log.

## Roles

Seven roles in `App\Enums\Role`, stored as strings so a database row is self-describing and
re-ordering the enum cannot silently promote anyone.

`customer`, `restaurant_owner`, `restaurant_manager`, `restaurant_staff`, `support_agent`, `admin`,
`super_admin`.

**Authorisation is enforced server-side.** Hiding a button is a courtesy to the user, never a
control: the endpoint is reachable with `curl` regardless. Every future module authorises in the
request path.

New accounts default to `customer` — the least privileged role — and role escalation is never
self-service.

## Multi-tenancy and tenant isolation

**A restaurant is a tenant.** Restaurant owners, managers and staff may reach only the restaurants
they are *explicitly assigned to*. `super_admin` may reach more than one tenant, and which ones is
an RBAC decision rather than an implicit consequence of the role string.

This is a platform-wide constraint, recorded here rather than in the module that first needs it, so
that every future module is written against it instead of discovering it.

### The rules

1. **Isolation is enforced in the query, not after the fetch.** A lookup that finds a row and *then*
   compares a tenant id has already decided the row exists, and the difference between "not yours"
   and "not real" is what an attacker is trying to learn. Scope in the `where`, as
   `TripService::ownedByOrFail()` and `CheckoutController::quoteOrFail()` already do for customers.
2. **Isolation is enforced by Laravel authorisation, policies and query scoping, and by database
   relationships.** Never by frontend filtering. A hidden button is a courtesy; the endpoint is
   reachable with `curl` regardless.
3. **Assignment is a row, not a role.** `restaurant_manager` says what somebody may do; it never
   says *where*. Membership of a tenant is an explicit record with its own lifecycle, and a role
   with no assignment reaches nothing.
4. **A missing assignment answers 404**, with the same body as a restaurant that does not exist.
5. **Cross-tenant reach is a test, not a review comment.** Every read, write, list, API route and
   id-substitution path gets an explicit test that a member of tenant A cannot reach tenant B —
   including the indirect routes, which is where the real holes are: a menu item reached through
   *its own* id rather than through its restaurant, an order reached through a payment, a report
   filtered by a tenant id supplied in the request.
6. **`super_admin` is scoped too.** "May access multiple tenants" is not "may access all tenants
   implicitly". Whatever grants the breadth is checked in the same place as everything else.

### Where this stands today

**Built in Module 14T.** Full design:
[33-multi-tenancy-and-tenant-isolation.md](33-multi-tenancy-and-tenant-isolation.md).

| Piece | State |
| --- | --- |
| `Role` enum with all seven roles | **Exists**, with `isRestaurantRole()` and `isPlatformRole()` |
| `TenantRole` — capability *within* one restaurant | **Exists**, ordered so owner ⊇ manager ⊇ staff |
| `restaurant_user` assignment table | **Exists** — one row per person per restaurant, unique in the database |
| `platform_tenant_grants` | **Exists** — a super administrator with no row reaches nothing |
| `restaurants.owner_id` | **Deliberately does not exist** — an owner is an assignment whose role is `owner`, so there is one place to revoke |
| `TenantAccessService` | **Exists** — the only implementation of reachability |
| `app/Policies/RestaurantPolicy` | **Exists** — no `before()` hook, on purpose |
| `BelongsToTenant` scope for child models | **Exists** — closes the indirect path |
| Guarded routes for the restaurant and platform surfaces | **Exist**, minimal and deliberately not a dashboard |
| Cross-tenant security tests | **22**, over HTTP, with 7 negative controls all of which fired |

**A login for the six operator roles is still not built**, and that is unchanged. The boundary
exists first so that login arrives behind something already tested rather than alongside something
new.

### The precedent to follow

Customer scoping is already the right shape and should be the model:

- `Trip::query()->ownedBy($customer)` — a scope, applied in the query.
- `CheckoutQuote` looked up by `uuid` **and** `customer_id` **and** `cart_id` in one `where`, each
  clause sufficient alone and the redundancy deliberate and measured.
- The same 404 for "not yours" and "not real", everywhere.

Tenant scoping is that pattern with a different subject. What it additionally needs is a policy
layer, because a restaurant resource is reachable by more than one role — which is precisely the
condition this document already set for introducing one.

## Transport and headers

Every API response carries:

| Header | Value |
| --- | --- |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `no-referrer` |
| `Cross-Origin-Resource-Policy` | `same-site` |
| `Permissions-Policy` | `geolocation=(), camera=(), microphone=()` |
| `Content-Security-Policy` | `default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'` |
| `Cache-Control` | `no-store, private` |
| `Strict-Transport-Security` | only over TLS |

The API serves no HTML, so the restrictive CSP is correct: a response coaxed into rendering as a
document cannot execute anything. HSTS is withheld over plain HTTP so local development does not pin
a developer's browser to `https://localhost` for a year.

## CORS

An exact-match allow-list from `FRONTEND_URLS`, never a reflection of the inbound `Origin`.
`supports_credentials` is on, which is precisely why a wildcard origin is refused at boot: wildcard
plus credentials is the configuration that leaks them.

## Authentication and sessions

The customer flow, its threat model and every decision behind it are documented in
[18-customer-authentication.md](18-customer-authentication.md). The rules that matter platform-wide:

- One-time codes are generated with `random_int`, stored as a **peppered SHA-256 HMAC** (the pepper
  is `APP_KEY`, which is not in the database), and compared with `hash_equals`.
- A code is never returned, logged, or stored in plaintext. The attempt counter lives in **MySQL**,
  not Redis — losing a rate-limit counter is generous, losing an attempt counter is dangerous.
- Registration is bound to the completed challenge by an encrypted token. The registration endpoint
  accepts **no phone number at all**, so verifying one number and registering another is not a check
  that could be forgotten — it is structurally impossible.
- Access tokens are stored as `sha256` hashes, carry a single ability, and expire.
- The OTP request response is identical whether or not an account exists (no enumeration).
- A production or staging deployment **refuses to boot** on an OTP sender that reports it cannot
  reach a real handset, and the development sender refuses to be constructed in production at all.

## Owning your own data

Module 04 is the first module where one customer's request could, if written carelessly, reach
another customer's row. Four controls, each independent of the others:

- **No identifier to tamper with.** Self-service routes name the resource, never the owner:
  `PATCH /api/v1/customer/profile`, `DELETE /api/v1/customer/addresses/{uuid}`. The owner comes from
  the Sanctum token. There is no `customer_id` in any path, query or body that the server reads.
- **One door to an address.** Every handler reaches a row through
  `CustomerAddressService::ownedByOrFail()`, which scopes by the authenticated customer before it
  looks anything up. Not-found and not-yours return the identical 404 body, so the endpoint is not an
  oracle for which identifiers exist. A denied attempt logs `address.access_denied` with the actor id
  and the requested uuid, and no address content.
- **Allow-lists, three deep.** The form request declares the three fields a customer may send
  (`first_name`, `last_name`, `email`); the model's `$fillable` excludes `customer_id`, `uuid` and
  `is_default`; and the service reads keys by name rather than passing an array through. A payload
  carrying `phone_e164`, `phone_verified_at`, `role`, `status`, `created_at` or `customer_id`
  succeeds and changes none of them, because nothing ever reads them.
- **The verified phone is identity, not profile.** It is displayed read-only and there is no route
  that changes it. Changing a verified number will be a re-verification flow of its own, not a field
  in a form.

Changing the email address clears `email_verified_at`. The app never labels an email verified on the
strength of the customer having typed it.

### Addresses are sensitive

A saved address is where someone lives. It is treated as application-sensitive data, not as ordinary
content: it is returned only to its owner, never included in an analytics event, and never written to
a log. Operational logs for this module carry record ids and actor ids and nothing else — verified
against the real 1,634-line application log, which contains zero address lines, zero email addresses
and zero complete phone numbers.

**Coordinates are never invented.** If the customer has not located an address, `latitude` and
`longitude` are `NULL`. A plausible-looking coordinate derived from a text address is worse than no
coordinate, because the routing module in Module 06 would trust it. Module 05 makes the consequence
visible rather than papering over it: an unlocated address cannot be one end of a journey, the picker
says so, and the address form offers to find the real place instead.

### Cache isolation between accounts

The Flutter addresses provider watches the auth session rather than listening for a logout event, so
the session ending disposes the state; there is no per-customer cache that can outlive the customer.
Verified end-to-end: signing out of one account and into another shows no trace of the first, not
even for a frame.

## Ownership of a customer's own records

Three modules now hold records a customer owns and writes — saved addresses,
journeys and the routes calculated for them — and all three follow the same rules.
Any later module that adds one is expected to follow them too.

1. **No self-service route carries a customer identifier.** The owner is read
   from the token. There is nothing in the request to tamper with, so an
   ownership bug would have to be introduced by *adding* a parameter rather than
   by forgetting a comparison.
2. **One method is the only path to a record**, and it answers the identical 404
   for "does not exist" and "belongs to somebody else". Distinguishing them turns
   the endpoint into an oracle for which identifiers are real.
3. **Cross-module reads go through the owning module's own lookup.** Module 05
   resolves a saved address named in a journey request through
   `CustomerAddressService::ownedByOrFail()`, not through a query of its own. So
   planning a journey from somebody else's address fails exactly the way reading
   that address fails — and a second, parallel ownership check is not something
   anybody has to remember to keep correct.

4. **A child record is resolved inside its parent, never globally.** A route id
   is looked up among *this trip's* routes after the trip's ownership has been
   established. Selecting another customer's route on your own journey is not a
   refusal — there is no such route to find.

A corollary that has bitten before: **do not validate an identifier with an
existence rule** (`exists:customer_addresses,uuid`) on a resource the caller may
not own. It confirms the record is real before anybody has checked who owns it.

## Personal data that is not a name

Addresses and journeys are location data, and a journey is worse than an address:
it says where somebody will be, and *when their home is empty*. The rule for both
is the same and is enforced by tests that read the log file on disk:

- Never logged. Not the places, not the times, not the note the customer typed.
- Operational lines carry the event, the record uuid and the actor uuid — enough
  to answer "who changed what" in an incident, and nothing more.
- A creation logs which *kind* of source each end used — current location, saved
  address, place search — because how people choose places is an operational
  question and the answer says nothing about where.
- Never in analytics events.
- A denied access is logged as an attempt, without the content of what was
  reached for.

**A search query is location data too.** What somebody types into a place search
is a statement about where they are going, whether or not they ever create the
trip. No query text reaches a log line, including the line written when the
provider fails.

**A discovery is denser still.** Which restaurants somebody was offered, on which
road, at what time, is a description of where they will be *and where they intend
to stop*. Discovery is therefore scoped to the trip's owner even though
restaurants themselves are public information: the restaurant is not the secret,
the journey is. A foreign trip is **not found**, indistinguishable from one that
never existed, and the refusal names nothing.

The log carries counts and uuids — candidates considered, corridor survivors,
detours evaluated, duration — and never a restaurant name, a coordinate or route
geometry. Restaurants are told nothing at all: a restaurant does not need to know
that a customer is browsing it, and Module 07 does not tell it.

**A customer-facing response shape is an allow-list.** `Restaurant` has owner
contact details, a tax identifier, a bank reference, a commission rate and
internal notes, and none of them can reach a customer because
`toDiscoveryArray()` names the fields that may — one at a time, by hand. A
`$hidden` deny-list would expose the column somebody adds next month until they
remembered to hide it. Those private columns exist and are populated in tests on
purpose: a privacy test that asserts a response contains no owner phone number
proves nothing if there is no owner phone number to leak.

**A route is location data too, and denser than either end of it.** The polyline
is a minute-by-minute description of where a person intends to be. It is never
logged, never sent to analytics, and never included in a list or home-card
response — those carry a summary of distance and duration with no geometry at
all. The route events (`route.calculated`, `route.no_route`,
`route.calculation_failed`, `route.invalidated`, `route.provider_rejected`,
`route.response_rejected`, `route.selection_denied`) carry the trip uuid, the
actor uuid, the provider and the outcome. The verification sweep greps the day's
log for place names, the test coordinates, polyline markers and key prefixes, and
finds none.

### Third-party credentials never reach a device

The app holds no place-provider key and makes no provider call. Every lookup goes
through `/customer/places/*` on our own server, which is authenticated — an open
endpoint on a server holding a metered key is somebody else's free geocoder.

The key is sent to the provider in an `X-Goog-Api-Key` header and never in a
query string: a key in a URL ends up in access logs, proxy logs and referrer
headers. Because it never ships to a device, the restrictions that apply are the
server-side ones — IP restriction to the backend's egress addresses, and API
restriction to Places (New) and Geocoding. Android package/signing and iOS
bundle-id restrictions do not apply, because the app never calls the provider;
the guidance sits in `.env.example` next to the key itself.

If no key is configured, the provider resolves to `UnconfiguredPlaceProvider`,
which refuses every call and **blocks a production boot** through
`ProductionConfigGuard`. The development gazetteer refuses to be constructed
outside development at all.

### Location, and asking for it

The device's position is the most sensitive thing this app can read. Three rules:

1. **Requested contextually.** Permission is asked for from exactly one place —
   the "Use my current location" row — and never at launch. An app that asks
   before the customer has any reason to say yes is an app most people say no to.
2. **Read once, never watched.** One fix on demand, discarded once the trip is
   created. No position stream, no background permission, no "always"
   authorisation anywhere in the app.
3. **Never a trap.** Every refusal — denied, denied permanently, services
   switched off, timed out, platform failure — offers a search box that does not
   need location at all, and "services switched off" is never reported as a
   denial. The whole operation carries a hard 25-second deadline so a pending
   permission prompt cannot leave a customer watching a spinner with no way out.

### A driver error is a data leak waiting to happen

Found in Module 07 by grepping a real application log rather than by grepping for
the values a module had just written: **a customer's phone number was on disk**,
38 times in one day, because a unique-constraint violation names the value that
violated it.

Two mechanisms, and it is worth knowing both:

1. A PDO driver puts the offending value in its message, and Laravel appends the
   whole statement to every `QueryException` **with the bindings inlined and
   unquoted** — so there is nothing narrower to scrub than the `(Connection: …)`
   tail itself.
2. A throwable in log context is serialised through its **public** properties,
   and `PDOException::$errorInfo` is public. A redaction layer that matches by
   key and descends only into arrays never sees it.

Both are handled in `StructuredFormatter`, which is where this codebase puts
redaction precisely so that a call site cannot forget. The constraint name
survives — it is the half an engineer can act on, and it identifies nobody.

The general rule for anything added later: **never log a message produced by a
storage layer verbatim.** It was written to help a developer debug, not to be
safe.

## Logging

Structured JSON, one object per line, carrying `request_id`, `actor_id` and `actor_role`.

**Redaction happens in the formatter, not at the call site.** A call site that forgets is the normal
case, and a password on disk cannot be un-written. Any key containing `password`, `secret`, `token`,
`authorization`, `auth`, `otp`, `pin`, `cvv`, `cvc`, `card`, `pan`, `api_key`, `private_key`,
`credential`, `session`, `cookie` or `signature` is replaced with `[REDACTED]`, case-insensitively,
at every depth. Recursion is bounded so a cyclic payload cannot turn a log write into a crash.

Request **bodies are never logged at all**. The formatter would redact known keys, but the safer
default for an API that will carry addresses, payment intents and OTPs is not to write them.

## Input validation

Every endpoint validates before acting. A validation failure returns `VALIDATION_FAILED` with the
offending fields — all of them, not the first.

## Rate limiting and idempotency

See [05-api-standards.md](05-api-standards.md). Both are security controls: the first limits
brute-force and scraping, the second prevents a retried payment being charged twice.

## Not yet built

Named rather than implied:

- **Authentication for the restaurant and admin surfaces** — those shells still render
  clearly-labelled test personas. The **customer** surface is built: phone + OTP, Sanctum sessions,
  role and ability gates. See [18-customer-authentication.md](18-customer-authentication.md).
- **Token revocation on account suspension** — a suspended account cannot obtain a new session, but
  an existing token keeps working until it expires. KI-008; the fix belongs with the admin module
  that does the suspending.
- **Per-resource authorisation policies** — with the modules that own the resources. Module 04's
  saved addresses are authorised in one service method rather than a policy class; a policy layer
  arrives with the first resource that more than one role can reach. A restaurant is that resource.
- **Authentication for the six operator roles** — the tenant boundary they will sign in behind is
  built and tested (Module 14T); minting them a token is not.
- **Staff management endpoints** — assignments and grants are rows today. The screens that create
  them belong to the operator module; `manageStaff` exists on the policy so the depth is already
  decided.
- **Email verification** — an email address on a profile is stored unverified and shown unverified.
- **Address geocoding** — no Places or Geocoding call is made yet, so coordinates stay `NULL`.
- **File upload scanning** — with the first module that accepts an upload.
- **Webhook signature verification** — with the payment module.
- **Audit log** — Module 18.

## Dependency security

`composer audit` and `npm audit` run in CI. The build fails on a high or critical advisory.

**Known gap:** PHPStan/Larastan could not be installed in the build environment used for Module 01 —
Composer's dist downloads resolve to GitHub zipball URLs, which that environment's egress policy
denies. Static analysis for PHP is therefore **not** in CI yet. Laravel Pint (code style) runs in its
place. This is a real gap, tracked in [13-known-issues.md](13-known-issues.md).

---

## Module 08 — filters that cannot become an attack surface

A filter set is user input that historically becomes SQL. Here it cannot,
because there is no SQL beneath it.

`DiscoveryRefiner` receives a `DiscoveryResult` — restaurants already selected,
already eligible, already in memory — and a validated `DiscoveryQuery`. It has
no repository, no query builder and no connection. Every claim below follows
from that rather than from a check somebody has to remember.

| Attack | Why it fails |
| --- | --- |
| `?search='; DROP TABLE restaurants; --` | The term is matched in PHP against strings already loaded. It never reaches a driver. Returns an empty page |
| `?cuisines=' OR 1=1 --` | Refused at the shape: a slug is `^[a-z0-9_]{1,60}$`. 422 before anything is built |
| `?sort=commission_rate desc` | A sort value's only destination is an enum case. Unknown value, 422 |
| `?search=<100 KB>` | 100-character limit, 422 |
| `?cuisines=<200 values>` | 25 values per group, 422 |
| `?max_detour_seconds=-500` | Bounded integer, 422 |
| Searching a suspended restaurant by exact name | The row was removed before the refiner ran. 0 results |
| Filtering to reach an unverified restaurant | Same. Seven filter shapes are asserted against it |
| A filtered call on somebody else's trip | `ownedByOrFail()` — 404, not 403, and the body says nothing about their journey |

### What a filter response may contain

Unchanged from Module 07: the body is built from
`Restaurant::toDiscoveryArray()`, an allow-list, and the test asserts against
the **raw response body** rather than parsed keys — a leak three levels down
inside a relation would still be a leak, and a structural assertion would not
see it.

Owner name, owner phone, owner email, tax identifier, bank reference, commission
rate and internal notes are absent from a filtered response for the same reason
they are absent from an unfiltered one.

### Rate limiting

`RATE_LIMIT_DISCOVERY` (30/min) applies to filtered calls exactly as to
unfiltered ones. A filter is cheap to serve and is not a way around the budget
on the most expensive endpoint in the application. The client's 350 ms search
debounce exists partly to keep an ordinary customer well clear of it.

### What is not logged

No search term, no filter selection, no coordinates. Filter usage is preference
data and this module builds no behavioural history from it.

---

## Module 09 — a uuid is not a key

The restaurant detail endpoint takes an identifier in the path, which is the
shape of every IDOR bug ever written. Here it cannot be one, because the
identifier is never used to *fetch* anything the customer was not already
entitled to: it is used to *find* an entry in a result Module 07 produced.

```php
$result = $this->discovery->discover($trip, $now);   // eligibility, corridor, route
foreach ($result->restaurants as $found) {
    if ($found->restaurant->uuid === $restaurantUuid) return $found;
}
throw $this->absent($restaurantUuid);
```

| Attack | Why it fails |
| --- | --- |
| Detail on a suspended restaurant's uuid | Not in the discovery result. 404 `RESTAURANT_UNAVAILABLE`, and the body names nothing |
| Detail on an unverified or disabled uuid | Same |
| Detail on a permanently closed uuid | Same |
| Detail on a restaurant in another city | 409 `RESTAURANT_OUTSIDE_ROUTE` — trading, and not on this journey |
| Detail on somebody else's trip | `ownedByOrFail()` — 404, and the body says nothing about their journey |
| Detail with no calculated route | 409 `ROUTE_NOT_READY`, before the restaurant is even looked at |
| A malformed uuid | Matches nothing. Answered identically, so the shape of a guess tells a prober nothing |
| `PUT`/`PATCH`/`DELETE`/`POST` on the path | 404 or 405. There is no customer-facing write route for a restaurant |

### Why suspended and missing share a status

A `403` on a suspended restaurant and a `404` on a missing one lets anybody
holding a list of uuids enumerate exactly which businesses this platform has
suspended — commercially sensitive information about somebody else's business.
Both answer `404`. The distinction survives in the error *code* so the client
can choose its words, and the code says nothing a prober did not already
supply.

### What a detail response may contain

Built from `Restaurant::toDiscoveryArray()` plus the profile fields Module 09
added, and asserted against the **raw body** — a leak nested three levels down
inside a relation would still be a leak, and a structural assertion would not
see it.

Absent: owner name, owner phone, owner email, tax identifier, bank reference,
commission rate, internal notes, verification status, discoverability flag,
soft-delete timestamps, and the sequential primary key.

`public_phone` is a different column from `owner_phone` and is the only contact
detail a customer ever sees.

### Media URLs

The API returns delivery URLs and never composes a storage path. Nothing in the
customer projection reveals bucket structure, and an unmoderated image is
unreachable because the relation itself filters it.

### Text an operator typed

Restaurant names and descriptions are stored and returned verbatim, as data.
Flutter draws text and cannot execute it. A future React surface must not hand
these values to `dangerouslySetInnerHTML`. Silently stripping markup on the way
out was rejected: it hides the problem from whoever eventually finds it, and
`RestaurantDetailApiTest::test_markup_in_a_restaurants_own_text_comes_back_as_text`
locks the behaviour down either way.

### Rate limiting

The detail endpoint shares the discovery throttle (`RATE_LIMIT_DISCOVERY`, 30
a minute). Opening a page calls no provider, but it does reach `discover()`,
and a cold cache there costs what the list costs. Sharing the budget is what
stops a loop over restaurant uuids from being a cheaper way to spend it.

---

## Module 10 — a menu is read-only, and the schema says who owns what

### There is no write endpoint to secure

A customer may `GET` a menu and `GET` one item. There is no `POST`, `PATCH`,
`PUT` or `DELETE` on any menu path, no image-upload route, and no write method
on `MenuRepository` in the Flutter app. The integration run tries six verb/path
combinations a modified client would try — including `POST …/menu/items` and
`POST …/menu/items/{item}/image` — and every one is refused.

This is the strongest form of "customers cannot change a menu": not a policy
check that could be bypassed, but an endpoint that does not exist.

### IDOR, answered in the query and in the schema

| Attack | Answer | Enforced by |
| --- | --- | --- |
| Restaurant A's context, restaurant B's item id | `ITEM_NOT_FOUND` | `where('restaurant_id', …)` in `CustomerMenuService::item()` |
| An item stored against the wrong restaurant | Cannot exist | Composite foreign key — MySQL refuses the row |
| A withdrawn item's id | `ITEM_NOT_FOUND` | `where('is_active', true)` |
| An item inside a withdrawn category | `ITEM_NOT_FOUND` | `whereHas('category', active)` |
| A suspended restaurant's menu, by uuid | 404 | `orderingContext()` refuses before the menu service is reached |
| Another customer's trip | `TRIP_NOT_FOUND` | `TripService::ownedByOrFail()` |

A withdrawn item and a nonexistent one answer **identically**, on purpose:
telling them apart would let anybody with a list of ids map a competitor's menu
by elimination.

### The customer payload is an allow-list

`MenuItem::toCustomerArray()` names every field it emits. Cost price, margin,
vendor, supplier, recipe, internal notes, staff notes, stock quantity and
commission are not filtered out — there is no line that could emit them. A test
asserts each string is absent from the raw response body, and the integration
run repeats it against real rows.

The same method takes its category as an **argument** rather than reading the
relation, which is a performance decision that happens to be a security one too:
nothing here can lazily reach a row the query did not deliberately fetch.

### A search term never becomes SQL

Menu search runs in memory over items already loaded. There is no query for a
term to become part of, so injection has nothing to inject into — and, just as
usefully, a search **cannot reach** an item the visibility rules already
excluded, because such items were never fetched. The integration run sends four
injection probes and asserts each returns nothing and the table still exists.

### One residual disclosure, inherited from Module 09

A restaurant that exists but is ineligible answers `404 RESTAURANT_UNAVAILABLE`;
one that never existed answers `404 RESTAURANT_NOT_FOUND`. The status is the
same — which is what defeats a bulk uuid sweep — but the code differs, so a
careful prober can tell a suspended business from a nonexistent one.

Module 09 chose this deliberately: the customer's next move genuinely differs,
and the wording on screen differs with it. Module 10 inherits rather than
diverging. Recorded here as a known trade-off; if it is ever judged wrong, the
fix is in `RestaurantDetailService::absent()` and changes both modules at once.

---

## Module 11 — the client cannot decide what anything costs

### The strongest form of "do not trust the client"

Not validation. **Absence.** `CustomizationSelection` has no price field, no
total, no discount and no tax, so there is nothing in the request for a modified
client to lie about and nothing a reviewer has to remember not to read.

An integration check sends `unit_price_minor`, `unit_price`, `line_total_minor`,
`subtotal`, `discount`, `tax`, `final_total` and `price` in a single body, and
the cart line stores ₹329 — which is what the dish costs.

### Every id in the request is proved, not assumed

| Claim in the request | How it is checked |
| --- | --- |
| "This variant is for this dish" | Looked up in the dish's **own** variant collection |
| "This option is in this group" | Looked up in a map built from the dish's own groups |
| "This option belongs to that group" | The client's pairing is **ignored**; the option knows |
| "This dish is at this restaurant" | `where('restaurant_id', …)` on the lookup |
| "This trip is mine" | `TripService::ownedByOrFail()` — not found, not refused |

And beneath all of it, seven composite foreign keys mean the wrong relationship
cannot be *stored* even if a future service forgets to check it. See
[06-database-conventions.md](06-database-conventions.md).

### The cart is reached through the trip

There is no `/carts/{id}` endpoint. A customer's cart is found by looking up
their journey and reading the active cart on it, so "another customer's cart"
is not an authorisation failure — it is a lookup that returns nothing, because
the journey was never theirs.

### Races are closed inside the request that writes

Everything is re-read at the moment of adding: the dish, the size, every option,
the restaurant's ordering state. The customer's screen may be ten minutes old
and the kitchen may have run out of mushrooms since. Five separate refusals
exist for the five ways that can go, so the client can say which.

### Notes are stored exactly as written

Markup, quotes, emoji, Devanagari and line breaks all go in verbatim. Escaping
on the way in would double-escape on the way out, and the place to make markup
safe is where it is rendered.

**A note that reaches the restaurant dashboard is untrusted text written by a
member of the public.** That dashboard is a later module; this is recorded here
so its author does not have to rediscover it.

### One thing a free-text field is not

An allergen control. The note's caption says the kitchen will see it and do what
they can, and the screen never suggests it is a way to declare an allergy. When
structured allergen data exists it will be a field with a schema, not a sentence
somebody typed.

### The residual disclosure, still inherited

Suspended and nonexistent restaurants both answer 404 with different error
codes, as documented in Module 09 and again in Module 10. Module 11 inherits it
rather than diverging.

---

## Module 13 — pickup times

### The client is trusted with nothing about time

A pickup window is chosen by sending an **opaque id the server minted**, and
there is no field in either the options or the selection request that could
carry a time. Not "the server validates the time it is sent" — there is nothing
to send. A test posts a body carrying `requested_pickup_start_at`,
`pickup_selection_status`, `version`, `restaurant_id` and `ready_for_checkout`
and none of them changes anything.

Deliberately not a signed timing payload. A signed payload still has to be
verified correctly on every path, and the day one path forgets, a customer names
their own pickup time. An opaque id that resolves to a server-written record has
nothing in it to tamper with.

### Option IDOR is structural, not checked

Option ids live under a cache key scoped to the customer, so another customer's
id is looked for under the wrong prefix and simply is not there — no branch to
get wrong, no comparison to forget. The record it would resolve to also carries
the customer, and the selection service compares it with `hash_equals`. Two
mechanisms for the guarantee the specification calls mandatory.

### One answer for three different failures

Expired, never existed, and belonging to somebody else all return
`PICKUP_OPTION_EXPIRED`. Distinguishing them would answer "does this id exist"
for anyone who asked, and the only person who asks is somebody trying ids.

### Server time, always

Every instant in this module comes from the server's clock. `$now` is injectable
only so tests can fix a moment and is never populated from a request. A device
whose clock is an hour fast would otherwise be handed windows in the past and
told they were fine.

### What does not reach the wire

No internal notes, commission rate, owner contact details, bank reference or tax
identifier; no per-line preparation breakdown; no capacity or staffing figure;
and **not the planning fingerprint**, which is an internal comparison value.
Asserted by searching the raw response body rather than the parsed shape.

A refusal never names *why* a restaurant is unavailable. "Suspended" tells
anybody who can guess a name something the platform has not published.

## Payment (Module 15)

**A client's word about money is evidence to check, never a fact to accept.**

No endpoint accepts an amount. Not one that is validated — one that exists. A
request carrying `amount`, `total` or `payable_total_minor` parses to exactly
the same object as one without.

An order is marked paid only after three checks, all of which run on all three
paths that can reach that state:

1. **Signature** — HMAC-SHA256 over `order_id|payment_id` with the API secret,
   compared in constant time.
2. **Binding** — the provider's own order id for that payment must match the
   provider order this server created for this order. A correctly signed payment
   belonging to somebody else is still correctly signed.
3. **Amount and currency** — against the order's total, not the attempt's.

The signature arithmetic deliberately does not sit behind the gateway interface.
Behind it, a test double would decide whether signatures verify, and every
payment-security test would assert against a `return true`.

### The webhook endpoint

Unauthenticated by necessity — the provider has no account here — and gated by
an HMAC over the **raw** body, checked before anything is parsed and before
anything at all is written.

**Only verified deliveries are recorded.** The endpoint is public: recording a
rejected delivery under the event id it claimed would let an attacker post a
forged body carrying the event id of a payment about to happen, causing the
genuine delivery to collide with the unique index and be discarded as a
duplicate — an order paid for and left unpaid, by somebody who never had the
secret.

The webhook secret is separate from the API secret, because the provider signs
the two messages with two different keys.

### Data this platform does not keep

- **No card data of any kind**, and no column one could be written into.
- **No webhook payloads** — only a SHA-256 digest of the raw body.
- **No provider decline text shown to customers.** It is written for a merchant
  dashboard and says things about a card that are not ours to relay.

### Fail closed

With no credentials the container binds a gateway that refuses every call, and
`ProductionConfigGuard` refuses to boot in staging or production — including
when the webhook secret alone is missing, since a live endpoint that can verify
nothing is indistinguishable from a provider that has stopped sending.

**As this project stands there are no Razorpay credentials, and none were
invented.**

## Order creation and pickup credentials (Module 16)

### The property being protected

A pickup credential is the thing that causes food to be handed to a person. It
is authentication material, and it is treated the way authentication material
is treated rather than the way an order field is treated.

### Nothing plaintext is stored

The code and the QR token are **derived on demand** and never written:

```
code   = base32   ( HMAC-SHA256( pepper, "pickup-code:v{n}:{order_uuid}:{restaurant_id}"  ) )[0..8]
token  = base64url( HMAC-SHA256( pepper, "pickup-token:v{n}:{order_uuid}:{restaurant_id}" ) )
digest =            HMAC-SHA256( pepper, "{purpose}:{value}" )
```

`orders` holds the two digests. There is no column a plaintext code can be read
out of, so a database dump, a backup, a support tool or a `SELECT *` in a log
cannot leak one. Verification is `hash_equals` against the digest.

The digest is **keyed with the pepper**, not a bare SHA-256. An 8-character
code over a 32-character alphabet is 2^40 — small enough to enumerate offline,
so a plain hash in a stolen dump is a lookup table away from plaintext. A keyed
digest is not, unless the pepper was stolen too.

### Replay resistance is arithmetic, not a check

The order uuid and the restaurant id are **inside the HMAC input**. A
credential minted for order A at restaurant X does not equal the one for order
B at restaurant Y, so cross-order and cross-tenant replay fail without any call
site having to remember to compare anything.

This matters because checks get forgotten when a second call site appears —
which is exactly what the Module 14T tenancy work was about. Here there is
nothing to forget. `OrderPlacementTest` asserts it in both directions across
two restaurants, with a positive assertion alongside so an implementation that
matched *nothing* could not pass the negatives.

### Rotation

`orders.pickup_credential_version` is inside the HMAC input, so bumping it
changes both derived values. The tests record the part that is easy to get
wrong: **rotation is not complete until the stored digests are re-minted**,
because the old digest otherwise keeps matching the old code.

### The pepper

`PICKUP_CREDENTIAL_PEPPER` is the single secret the scheme rests on, and that
trade is stated in the service rather than hidden. `ProductionConfigGuard`
refuses to boot staging or production without it. `derive()` throws
`PickupCredentialUnavailable` rather than deriving under an empty key — a
scheme that silently degrades to `HMAC(pepper: "")` is worse than one that
stops.

### An order number authorises nothing

`FOTG-YYMMDD-XXXXXXXXXX` is drawn from `random_int` (CSPRNG) over the same
32-character alphabet. It is **not** the database id, a timestamp,
`Math.random`, or any sequence — a sequential public number tells its holder
how many orders the platform has ever taken and lets them guess their
neighbours'.

But the reason it can be printed, read aloud at a counter and quoted in a
support ticket is not its entropy. It is that **knowing an order number is
never sufficient to collect food.** Entropy here defends against enumeration of
other customers' references, not against pickup.

### Not logged

Never, on any path: the plaintext pickup code, the plaintext QR token, special
instructions, payment signatures, provider secrets.
`PickupCredential::toString()` returns `PickupCredential(v2)` so that an
accidental interpolation cannot spill the value.

### Credentials are not served with the order

`GET /customer/orders/{order}/pickup-credential` is a separate, per-order,
authenticated call answering with `Cache-Control: no-store, private,
max-age=0`. Putting the credential on the order resource would ship it through
every list refresh and every status poll, and every proxy in between.

Ownership is `where('customer_id', $customer->id)` and a miss is a 404, not a
403 — a 403 confirms the order exists, which is the fact an attacker trying
identifiers is trying to learn.

### At most one order per captured payment

The security-relevant half of idempotency: a duplicate webhook, a retried
client call and the recovery sweep all reach the same
`CreateOrderFromCapturedPayment`, and the **unique index on
`orders.placed_from_payment_id`** is what makes a second order impossible. The
lock and the status re-read are the fast path; the index is the guarantee.

No client assertion is an input to order creation. `payment_success = true` in
a request body is not read. The only thing that causes an order is a payment
this server recorded as `CAPTURED` after verifying it with the provider, whose
amount and currency agree with `orders.payable_total_minor`.

### Open, and named rather than implied

**There is no redemption endpoint yet, so there is no attempt limit on guessing
a code yet.** Whichever module builds pickup verification inherits that: a
typed code must be attempt-limited per order, or 2^40 stops being a large
number. Tracked in [13-known-issues.md](13-known-issues.md).
