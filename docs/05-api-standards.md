# 05 — API standards

Base path: **`/api/v1`**. The version is in the path, not a header — it survives a browser address
bar, a `curl` pasted into a bug report, and a CDN cache key.

## Response envelope

Success:

```json
{
  "data": { "status": "ready" },
  "meta": { "request_id": "0f7c1b2e-..." }
}
```

Failure:

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "The submitted data is not valid.",
    "details": { "fields": { "origin": ["An origin is required."] } },
    "request_id": "0f7c1b2e-..."
  }
}
```

A client can tell success from failure by key presence alone, without consulting the status code.

### Paginated responses

```json
{
  "data": [ ... ],
  "meta": {
    "request_id": "...",
    "pagination": { "total": 240, "per_page": 25, "current_page": 1, "last_page": 10, "has_more": true }
  }
}
```

The shape is identical on every endpoint that pages, so a client's list component is written once.

## Error codes

Clients branch on `code`, never on `message` — the message is free to be reworded or translated.

| Code | HTTP | Meaning |
| --- | --- | --- |
| `VALIDATION_FAILED` | 422 | Input failed validation; `details.fields` lists them |
| `UNAUTHENTICATED` | 401 | No valid credentials |
| `FORBIDDEN` | 403 | Authenticated, not permitted |
| `NOT_FOUND` | 404 | No such resource, or not visible to this caller |
| `METHOD_NOT_ALLOWED` | 405 | Wrong HTTP method |
| `CONFLICT` | 409 | State conflict |
| `IDEMPOTENCY_KEY_REUSED` | 409 | Same key, different body |
| `RATE_LIMITED` | 429 | Too many requests |
| `BUSINESS_RULE_VIOLATED` | 422 | Valid input, disallowed by a domain rule |
| `DEPENDENCY_UNAVAILABLE` | 503 | MySQL or Redis is down |
| `SERVER_ERROR` | 500 | A bug — never described to the client |

Added in Module 03 ([18-customer-authentication.md](18-customer-authentication.md)):

| Code | HTTP | Meaning |
| --- | --- | --- |
| `INVALID_PHONE` | 422 | Not a number we can serve |
| `UNSUPPORTED_PHONE_REGION` | 422 | A valid number in a country we do not operate in |
| `OTP_SEND_FAILED` | 503 | The sender definitely did not deliver |
| `OTP_RATE_LIMITED` | 429 | Too many code requests for this number or IP |
| `OTP_INVALID` | 422 | Wrong code |
| `OTP_EXPIRED` | 422 | Expired, already used, or no live challenge |
| `OTP_TOO_MANY_ATTEMPTS` | 422 | The challenge is dead; request a new code |
| `OTP_RESEND_TOO_SOON` | 429 | Inside the resend cooldown |
| `REGISTRATION_TOKEN_INVALID` | 401 | Forged, altered, or not from a completed verification |
| `REGISTRATION_TOKEN_EXPIRED` | 401 | Verified too long ago |
| `ACCOUNT_SUSPENDED` | 403 | The account cannot authenticate right now |
| `ACCOUNT_DISABLED` | 403 | The account cannot authenticate at all |

Added in Module 04 ([19-customer-profile-and-addresses.md](19-customer-profile-and-addresses.md)):

| Code | HTTP | Meaning |
| --- | --- | --- |
| `ADDRESS_LIMIT_REACHED` | 422 | The customer already holds the maximum saved addresses |
| `ADDRESS_NOT_FOUND` | 404 | No such address *for this customer* — the same answer either way |

`ADDRESS_NOT_FOUND` is returned both when the address does not exist and when it belongs to someone
else. A 403 for the second case would confirm that the identifier is real, which is the whole of what
an attacker wants; the two answers are byte-identical.

Added in Module 05 ([20-trip-planner.md](20-trip-planner.md)):

| Code | HTTP | Meaning |
| --- | --- | --- |
| `ORIGIN_REQUIRED` / `DESTINATION_REQUIRED` | 422 | An end of the journey was not supplied |
| `SAME_LOCATION` | 422 | Both ends resolve to the same place |
| `INVALID_COORDINATES` | 422 | Out of range, or the (0, 0) sentinel |
| `SAVED_ADDRESS_NOT_LOCATED` | 422 | That address has never been located |
| `TRIP_NOT_FOUND` | 404 | No such journey, or not visible to this caller |
| `TRIP_LIMIT_REACHED` | 422 | Too many journeys still open |
| `TRIP_NOT_EDITABLE` | 422 | The journey has already been discarded |
| `TRIP_CREATE_FAILED` | 500 | Ours — offer a retry, not a field |
| `PLACE_NOT_FOUND` | 404 | The place provider does not know that id |
| `PLACE_LOOKUP_FAILED` | 503 | The place provider is unavailable |
| `ROUTE_INPUT_INVALID` | 422 | The journey's own endpoints cannot be routed between |
| `ROUTE_NOT_FOUND` | 404 | No such route on this journey |
| `ROUTE_SELECTION_INVALID` | 422 | That route id is not one of this journey's |
| `ROUTE_STALE` | 409 | The endpoints moved while the screen was open |
| `ROUTE_ALREADY_CURRENT` | 409 | That route is already the selected one |
| `ROUTE_NO_ROUTE_FOUND` | 422 | The provider found no road route |
| `ROUTE_PROVIDER_UNAVAILABLE` | 503 | The routing provider is down or unreachable |
| `ROUTE_PROVIDER_RATE_LIMITED` | 429 | The routing provider refused on quota |
| `ROUTE_TIMEOUT` | 504 | The routing provider did not answer in time |
| `ROUTE_RESPONSE_INVALID` | 502 | The routing provider answered with something unusable |
| `ROUTE_CALCULATION_IN_PROGRESS` | 409 | A calculation is already running for this journey |

The eleven routing codes are eleven rather than one because the customer's next
move differs for each: `ROUTE_NO_ROUTE_FOUND` is the provider's considered answer
and must not offer a retry, `ROUTE_TIMEOUT` should, and `ROUTE_STALE` means the
screen is out of date rather than the network. A single "something went wrong"
offers the same useless button to all of them.

Like `PLACE_LOOKUP_FAILED`, none of them carries a word of the provider's own
message: an upstream routing error names our project, our key state and our
quota.

| `ROUTE_NOT_READY` | 409 | The journey has no usable selected route to search along |
| `DISCOVERY_FAILED` | 500 | The restaurant search could not complete |
| `DISCOVERY_RATE_LIMITED` | 429 | Too many discovery requests |
| `RESTAURANT_DATA_UNAVAILABLE` | 503 | The restaurant store is unreachable |
| `DETOUR_PROVIDER_UNAVAILABLE` | 503 | The routing provider is down |

`ROUTE_NOT_READY` is deliberately distinct from `ROUTE_NOT_FOUND`. The route
exists and the customer can see it; it is simply not in a state discovery can
search along, and the client's answer is to send them back to the route screen
rather than to report a missing journey.

**A read may be expensive without becoming a POST.** Restaurant discovery is a
`GET` even though it can reach a billed provider: it writes nothing, and a
customer reopening it expects what they saw before. The spending is controlled by
a cache, a hard evaluation budget and its own throttle — not by making the verb
inconvenient. The rule this module follows, and the next one should: **the verb
describes the effect, the budget controls the cost.**

**A response says what it cost.** Discovery returns a `meta` block —
candidates considered, how many survived the corridor, how many detours were
evaluated, whether the answer came from cache. It is there so a client can say
something useful about an empty screen instead of guessing, and so performance
evidence is a measurement rather than an assertion.

**A guest is answered 401, whatever they sent.** Laravel's default redirects an
unauthenticated request that does not announce `Accept: application/json` to a
`login` route. This API has none, so that path threw and the caller was told 500
when the truth was 401. The guest redirect is configured to return null so the
authentication exception survives to the renderer.

`SAVED_ADDRESS_NOT_LOCATED` earns its own code rather than folding into
`VALIDATION_FAILED` because the client's answer is specific and different:
locate the address, do not retry the request.

`PLACE_LOOKUP_FAILED` carries nothing from the provider's own message. An
upstream error names our project, our key state and our quota.

`TRIP_NOT_FOUND` is a 404 for the same reason `ADDRESS_NOT_FOUND` is: not-yours
and does-not-exist are one answer, so the endpoint cannot be walked to discover
which identifiers are real.

Two deliberate choices in that table. `OTP_RESEND_TOO_SOON` and `OTP_RATE_LIMITED` share a status so
a caller cannot distinguish "too soon" from "too many". `ACCOUNT_DISABLED` also covers a deleted
account: reporting deletion would confirm to whoever now holds that number that an account existed.

Rate-limit errors carry `details.retry_after_seconds` — a client needs it for a countdown — and
never the threshold, which would hand a caller the shape of the limit to work around.

Adding a code is backwards compatible. Changing or removing one is a breaking change requiring a new
API version. `GET /api/v1/meta` returns this table so clients read it from the server rather than
copying it into three codebases.

**A 5xx never describes itself.** Message, class, file, line and a truncated stack go to the log
against the same `request_id` the client was given. The client receives a fixed sentence and that
id. This is asserted by a test that throws an exception containing a fake password and asserts the
response body contains neither it nor the exception class.

## Authentication

Bearer tokens (Laravel Sanctum). `Authorization: Bearer <token>` and nowhere else — a token in a
query string ends up in access logs, proxy logs and `Referer` headers, and the API rejects one there.

`config/sanctum.php` sets `'guard' => []`: session cookies never authenticate an API request, so no
state-changing route is reachable with an ambient cookie.

A protected route carries **three** middleware, not one:

```php
Route::middleware(['auth:sanctum', 'role:customer', 'abilities:customer', 'throttle:api-public'])
```

`auth:sanctum` proves the token is real and unexpired. `role:` proves the account is the kind that
belongs on this surface. `abilities:` proves this particular token was minted for this work. A route
that checks only the first has checked neither of the others, and a valid customer token is a
perfectly good credential with no business reaching a restaurant's order queue.

## Correlation IDs

Every request gets an `X-Request-Id`, echoed in the response header **and** in the body. An inbound
`X-Request-Id` is honoured only if it is a valid UUID — accepting an arbitrary client string would
let a caller forge or poison log lines.

## Rate limiting

Keyed by authenticated user where there is one, by IP otherwise, so a shared corporate NAT is not
throttled as a single caller.

| Limit | Default |
| --- | --- |
| `RATE_LIMIT_PUBLIC` | 60/min |
| `RATE_LIMIT_AUTHENTICATED` | 120/min |

`/api/v1/health/*` is **exempt**. An orchestrator polls liveness far more often than the public limit
allows; throttling it turns a healthy instance into a restart loop.

## Idempotency

Send `Idempotency-Key` on an unsafe request. A retry with the same key returns the first response
byte-for-byte, with `Idempotency-Replayed: true`.

- Keys are namespaced **per authenticated actor**, so one user cannot guess another's key and read
  back their response body.
- The same key with a **different body** returns `IDEMPOTENCY_KEY_REUSED` rather than the old
  response — that is a client bug, not a retry.
- Only responses below 500 are stored; caching a transient 5xx would make it permanent.

The scenario this exists for: a traveller on a patchy motorway connection taps "place order", the
response is lost, the app retries — and without this they are charged twice.

## Health

| Endpoint | Answers |
| --- | --- |
| `GET /api/v1/health/live` | Is the process running? Touches nothing else. |
| `GET /api/v1/health/ready` | Can this instance serve? Runs `SELECT 1` and Redis `PING`. |

Conflating them turns a slow database into a restart loop.

## Conventions for future modules

- Resource paths are plural nouns: `/api/v1/restaurants/{restaurant}/menu-items`
- Route keys are UUIDs, never auto-increment ids
- Money is an integer of minor units, with the currency alongside — never a float
- Timestamps are ISO-8601 UTC
- Filtering `?status=pending&status=confirmed`; paging `?page=2&per_page=25`

Two conventions that arrived with the self-service modules and are expected to
hold for every resource a customer owns:

- **No customer identifier in a self-service path.** The owner is the token.
  `/customer/addresses/{uuid}` and `/customer/trips/{uuid}`, never
  `/customers/{id}/…` — there is then no ownership check to forget and no id for
  a caller to change.
- **A literal segment is declared before a parameter that could swallow it.**
  `/customer/trips/current` before `/customer/trips/{trip}`, or "current" is
  captured as a journey id and answered 404.
- **A child resource is nested under the parent that gives it meaning, and
  carries no id of its own in the path.** `/customer/trips/{trip}/routes`, and
  `/customer/trips/{trip}/restaurants` — which names no route, because the route
  searched is whichever one the customer selected on their own trip. There is
  nothing to substitute for somebody else's.
- **A filter uses the server's own vocabulary.** `/customer/trips?status=` takes
  a `TripStatus` value, not a client-side word. An unknown query parameter is
  *ignored* rather than refused, so a client sending its own dialect gets an
  unfiltered list and looks entirely healthy — a defect that reached a running
  server in Module 05 and is now pinned by a test.
- A resource a customer owns is addressed without naming the owner: `/api/v1/customer/addresses/{uuid}`,
  never `/api/v1/customers/{customer}/addresses/{uuid}`. The actor comes from the token. Admin and
  support surfaces, when they exist, get their own routes with their own abilities rather than
  reusing a self-service path with an id in it.
- Update requests take an allow-list of fields, declared in the form request. A field a customer may
  not change is not "rejected" — it is not read. `PATCH` with `phone_e164` in the body returns 200
  and changes nothing about the phone.

---

## Filtering, sorting and pagination (Module 08)

The discovery endpoint is the first to take a filter set, and it sets the
conventions the rest of the API should follow.

**Comma-separated repeated values.** `?cuisines=north_indian,cafe`, not
`cuisines[]=…&cuisines[]=…`. One parameter, one meaning, and a query string
that stays readable in a log line.

**Slugs, never labels.** A filter value is a stable identifier
(`^[a-z0-9_]{1,60}$`), generated by the database, never a display string. A
localised label as a filter value breaks the day the interface is translated.

**Normalise, then echo back.** Values are trimmed, deduplicated and sorted, so
`facilities=restroom,parking` and `facilities=parking,restroom` are the same
request. `meta.applied` returns the query as the server understood it, which is
the fastest way for a client to notice a parameter that was dropped.

**Reject, never ignore.** Every malformed filter is a `422` with
`error.code = VALIDATION_FAILED` and `error.details.fields.<name>` naming the
parameter. Silently dropping an unrecognised filter and returning a full list
hides the client's bug behind a healthy-looking response.

**Sorts are enums.** A sort value's only possible destination is an enum case
with a hand-written comparator. It never becomes a column name. A sort the data
cannot support yet is refused with a reason, not silently downgraded.

**Pagination metadata.** `page`, `per_page`, `last_page`, `total`, `has_more`,
and — where the endpoint filters — `eligible_total` and `filtered_empty`, so a
client can tell "nothing here" from "your filters hid everything".

**Facets travel with the results.** Filter options for the current context are
part of the response rather than a second endpoint, when they are computed from
the same set and cost nothing extra.

---

## Sub-resources, and telling refusals apart (Module 09)

`GET /customer/trips/{trip}/restaurants/{restaurant}` is the first
sub-resource of a nested collection, and it sets two conventions.

**A sub-resource keeps its parent in the path.** The restaurant's figures on
this screen were measured against one particular route, so the journey stays in
the URL rather than being inferred from a session or a header. A detail endpoint
that answered without one would be a different product.

**Refusals that a prober could use are made identical.** A restaurant that does
not exist and one that has been suspended both answer `404`. A `403` on the
second would let anyone holding a list of uuids discover which businesses this
platform has suspended. Where the distinction is *not* dangerous — a restaurant
that is trading but on a different road — it is made, because the customer's
next move differs:

| Situation | Code | Status |
| --- | --- | --- |
| No such restaurant | `RESTAURANT_NOT_FOUND` | 404 |
| Real, and withdrawn | `RESTAURANT_UNAVAILABLE` | 404 |
| Real, trading, elsewhere | `RESTAURANT_OUTSIDE_ROUTE` | 409 |

**A derived field never renames the one it derives from.** The response carries
both `availability` (Module 07's vocabulary, unchanged) and `ordering.state`
(Module 09's rollup). Two names for one concept would be a bug; one name for
two concepts is worse.

**Freshness travels with the payload.** `generated_at` lets an offline client
say how old what it is showing is, rather than implying the data is live.

---

## Money on the wire (Module 10)

An amount is always an object, never a number and never a string:

```json
"price": { "amount_minor": 24900, "currency": "INR" }
```

- **`amount_minor` is an integer count of the currency's smallest unit.** Paise
  for INR. Not rupees, not a decimal string, and never a float — a JSON number
  with a fractional part is a contract violation and clients reject it.
- **`currency` is ISO 4217, upper case, and always present.** An amount without
  one is not a price.
- **The server never sends a rendered string.** No `"₹249"`, no `"price_label"`.
  What a price looks like — symbol, grouping, decimals — is a locale decision,
  and the server does not know the customer's locale. An integration test
  asserts no `₹` appears anywhere in a menu response.

This applies to every money field in every later module: cart totals, taxes,
delivery fees, refunds.

---

## Two counts for two empty states (Modules 08 and 10)

A collection endpoint that can be filtered returns **both** counts:

```json
"meta": { "item_count": 0, "visible_item_count": 18, "search_empty": true, "menu_empty": false }
```

`item_count` is after the filter; `visible_item_count` is before it. The client
needs both to tell "there is nothing here" from "your search found nothing" —
two different problems whose answers are opposite: leave, or clear the box. An
endpoint that returned only the first forces the client to guess, and it guesses
wrong on exactly the day a restaurant has no menu.
