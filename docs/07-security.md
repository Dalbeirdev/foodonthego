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
  arrives with the first resource that more than one role can reach.
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
