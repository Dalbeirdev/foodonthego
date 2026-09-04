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
- A resource a customer owns is addressed without naming the owner: `/api/v1/customer/addresses/{uuid}`,
  never `/api/v1/customers/{customer}/addresses/{uuid}`. The actor comes from the token. Admin and
  support surfaces, when they exist, get their own routes with their own abilities rather than
  reusing a self-service path with an id in it.
- Update requests take an allow-list of fields, declared in the form request. A field a customer may
  not change is not "rejected" — it is not read. `PATCH` with `phone_e164` in the body returns 200
  and changes nothing about the phone.
